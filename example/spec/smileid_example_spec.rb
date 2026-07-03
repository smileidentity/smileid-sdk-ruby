# frozen_string_literal: true

require 'base64'
require 'faraday'
require 'json'
require 'rspec'
require 'smileid_example'

RSpec.describe SmileIDExample do
  def env
    { 'SMILE_PARTNER_ID' => '12345', 'SMILE_API_KEY' => 'test-api-key' }
  end

  def make_client(stubs)
    Faraday.new do |f|
      f.request :multipart
      f.adapter :test, stubs
    end
  end

  def json_response(status, body)
    [status, { 'Content-Type' => 'application/json' }, JSON.generate(body)]
  end

  def jwt
    header = Base64.urlsafe_encode64(JSON.generate(alg: 'HS256', typ: 'JWT')).delete('=')
    payload = Base64.urlsafe_encode64(JSON.generate(exp: Time.now.to_i + 3600)).delete('=')
    "#{header}.#{payload}.signature"
  end

  it 'lists service reference data without authentication' do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get('/v3/services/bank_codes') do |env|
        expect(env.params['country']).to eq('NG')
        json_response(200, bank_codes: [{ code: '001', country: 'NG', name: 'Example Bank' }])
      end
      stub.get('/v3/services/supported_id_types') do |env|
        expect(env.params['country']).to eq('NG')
        id_types = [
          {
            country: 'NG',
            label: 'National Identification Number',
            regex: '^\\d{11}$',
            required_fields: ['id_number'],
            type: 'NIN'
          }
        ]
        json_response(200, id_types: id_types)
      end
      stub.get('/v3/services/supported_documents') do |env|
        expect(env.params['country_code']).to eq('NG')
        valid_documents = [
          {
            country: { code: 'NG', name: 'Nigeria', continent: 'Africa' },
            id_types: [
              {
                code: 'PASSPORT',
                name: 'Passport',
                example: ['A12345678'],
                has_back: false
              }
            ]
          }
        ]
        json_response(200, valid_documents: valid_documents)
      end
    end
    out = StringIO.new
    described_class.run(
      ['--base-url', 'https://api.test', 'services', '--country', 'NG'],
      env: env,
      stdout: out,
      http_client: make_client(stubs)
    )

    parsed = JSON.parse(out.string)
    expect(parsed['country']).to eq('NG')
    expect(parsed['bank_codes'].first['code']).to eq('001')
    expect(parsed['id_types'].first['type']).to eq('NIN')
    stubs.verify_stubbed_calls
  end

  it 'submits enhanced KYC' do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/v3/token') { json_response(200, token: jwt) }
      stub.post('/v3/enhanced_kyc') do |env|
        expect(env.request_headers['SmileID-Token']).to start_with('eyJ')
        body = env.body.to_s
        expect(body).to include('name="country"', 'NG')
        expect(body).to include('name="id_type"', 'NIN')
        expect(body).to include('https://example.com/smile-callback')
        expect(body).to include('"given_names":"Amina"')
        json_response(202, status: 'Accepted', message: 'submitted', job_id: 'job_enhanced_123', user_id: 'user_123')
      end
    end
    out = StringIO.new
    described_class.run(
      [
        '--base-url', 'https://api.test',
        '--callback-url', 'https://example.com/smile-callback',
        'enhanced-kyc',
        '--country', 'NG',
        '--id-type', 'NIN',
        '--id-number', '12345678901',
        '--given-names', 'Amina',
        '--last-name', 'Okafor',
        '--email', 'amina@example.com'
      ],
      env: env,
      stdout: out,
      http_client: make_client(stubs)
    )

    parsed = JSON.parse(out.string)
    expect(parsed['job_id']).to eq('job_enhanced_123')
    expect(parsed['accepted']).to be(true)
    stubs.verify_stubbed_calls
  end

  it 'retrieves status' do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/v3/token') { json_response(200, token: jwt) }
      stub.get('/v3/status/job_enhanced_123') do |env|
        expect(env.request_headers['SmileID-Token']).to start_with('eyJ')
        json_response(200, status: 'complete', message: 'clear', job_id: 'job_enhanced_123', user_id: 'user_123')
      end
    end
    out = StringIO.new
    described_class.run(
      ['--base-url', 'https://api.test', 'status', '--job-id', 'job_enhanced_123'],
      env: env,
      stdout: out,
      http_client: make_client(stubs)
    )

    parsed = JSON.parse(out.string)
    expect(parsed['status']).to eq('complete')
    expect(parsed['message']).to eq('clear')
    stubs.verify_stubbed_calls
  end

  it 'replays callbacks' do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/v3/token') { json_response(200, token: jwt) }
      stub.post('/v3/replay/job_enhanced_123') do |env|
        expect(JSON.parse(env.body)).to eq('callback_url' => 'https://example.com/replay-callback')
        json_response(200, status: 'success', message: 'replayed', job_id: 'job_enhanced_123', user_id: 'user_123')
      end
    end
    out = StringIO.new
    described_class.run(
      [
        '--base-url', 'https://api.test',
        'replay',
        '--job-id', 'job_enhanced_123',
        '--callback-url', 'https://example.com/replay-callback'
      ],
      env: env,
      stdout: out,
      http_client: make_client(stubs)
    )

    parsed = JSON.parse(out.string)
    expect(parsed['status']).to eq('success')
    expect(parsed['job_id']).to eq('job_enhanced_123')
    stubs.verify_stubbed_calls
  end

  it 'prints help without credentials' do
    out = StringIO.new
    described_class.run(['help'], env: {}, stdout: out)
    expect(out.string).to include('Usage:')
  end

  it 'raises usage errors for missing credentials' do
    expect { described_class.run(['services'], env: {}, stdout: StringIO.new) }
      .to raise_error(SmileIDExample::UsageError, /SMILE_PARTNER_ID/)
  end
end
