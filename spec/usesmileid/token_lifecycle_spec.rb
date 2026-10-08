# frozen_string_literal: true

require 'spec_helper'

# Matrix item 2: token lifecycle (spec sections 2.3 and 2A). One token per request.
RSpec.describe 'token lifecycle' do
  let(:client) { build_client }

  def stub_status(job_id = 'job_01h8x9y2z3a4b5c6d7e8f9g0h1', **overrides)
    stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/#{job_id}")
      .to_return({ status: 200,
                   body: JSON.generate(status: 'clear', job_id: job_id, message: 'Job completed'),
                   headers: { 'Content-Type' => 'application/json' } }.merge(overrides))
  end

  it 'sends partner credentials as headers and no body to /v3/token without claims' do
    captured = nil
    stub_request(:post, "#{TestHelpers::SANDBOX}/v3/token")
      .to_return do |request|
        captured = request
        { status: 200, body: JSON.generate(token: make_jwt),
          headers: { 'Content-Type' => 'application/json' } }
      end
    stub_status

    client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1')

    expect(captured.headers['Smileid-Partner-Id']).to eq('1234')
    expect(captured.headers['Smileid-Api-Key']).to eq('test-api-key')
    expect(captured.body.to_s).to eq('')
  end

  let(:job_id) { 'job_01h8x9y2z3a4b5c6d7e8f9g0h1' }

  def json_headers
    { 'Content-Type' => 'application/json' }
  end

  # Records the body of every /v3/token request, parsed to its text claims.
  def capture_token_claims
    claims = []
    stub = stub_request(:post, "#{TestHelpers::SANDBOX}/v3/token")
           .to_return do |request|
      body = request.body.to_s.dup.force_encoding('UTF-8')
      claims << body.scan(/name="([^"]+)"\r\n\r\n([^\r]*)\r\n/).to_h
      { status: 200, body: JSON.generate(token: make_jwt), headers: json_headers }
    end
    [stub, claims]
  end

  def stub_accepted(path)
    stub_request(:post, "#{TestHelpers::SANDBOX}/v3/#{path}")
      .to_return(status: 202, body: accepted_body, headers: json_headers)
  end

  def enhanced_kyc(**opts)
    client.enhanced_kyc.verify(country: 'NG', id_type: 'NIN', id_number: '12345678901',
                               user_details: valid_user_details, consent: valid_consent, **opts)
  end

  def biometric_kyc_enrolled
    client.biometric_kyc.verify(use_enrolled_image: true, user_id: 'user-1', country: 'NG',
                                id_type: 'NIN', id_number: '12345678901',
                                user_details: valid_user_details, consent: valid_consent)
  end

  it 'mints a fresh token for every job' do
    token_stub, = capture_token_claims
    stub_accepted('enhanced_kyc')

    3.times { enhanced_kyc }

    expect(token_stub).to have_been_requested.times(3)
  end

  it 'mints a fresh token for every status call' do
    token_stub = stub_token
    stub_status

    3.times { client.verifications.retrieve(job_id) }

    expect(token_stub).to have_been_requested.times(3)
  end

  it 'binds the job user_id and product into the token' do
    _, claims = capture_token_claims
    stub_accepted('enhanced_kyc')

    enhanced_kyc(user_id: 'user-1')

    expect(claims).to eq([{ 'user_id' => 'user-1', 'product' => 'enhanced_kyc' }])
  end

  it 'binds the body user_id for authentication' do
    _, claims = capture_token_claims
    stub_accepted('authentication')

    client.biometric.authenticate(user_id: 'user-1', selfie_image: 's', liveness_images: %w[a b],
                                  user_details: valid_user_details, consent: valid_consent)

    expect(claims).to eq([{ 'user_id' => 'user-1', 'product' => 'smart_selfie_authentication' }])
  end

  it 'binds only the product when compare has no user_id' do
    _, claims = capture_token_claims
    stub_accepted('compare')

    client.biometric.compare(selfie_image: 's', comparison_image: 'c',
                             comparison_image_type: 'ID_PHOTO',
                             user_details: valid_user_details, consent: valid_consent)

    expect(claims).to eq([{ 'product' => 'smart_selfie_compare' }])
  end

  it 'does not retry a 401' do
    token_stub = stub_token
    status_stub = stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/#{job_id}")
                  .to_return(status: 401,
                             body: JSON.generate(status: 'Unauthorized', message: 'Token expired'),
                             headers: json_headers)

    expect { client.verifications.retrieve(job_id) }
      .to raise_error(SmileID::Errors::AuthenticationError, 'Token expired')
    expect(status_stub).to have_been_requested.once
    expect(token_stub).to have_been_requested.once
  end

  it 'reuses the request token when an idempotent request is retried' do
    allow_any_instance_of(SmileID::Transport).to receive(:sleep_for)
    token_stub = stub_token
    tokens = []
    stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/#{job_id}")
      .to_return do |request|
      tokens << request.headers['Smileid-Token']
      if tokens.length == 1
        { status: 503, body: JSON.generate(status: 'Error', message: 'busy'), headers: json_headers }
      else
        { status: 200, body: JSON.generate(status: 'clear', job_id: job_id, message: 'done'),
          headers: json_headers }
      end
    end

    client.verifications.retrieve(job_id)

    expect(tokens.length).to eq(2)
    expect(tokens.uniq.length).to eq(1)
    expect(token_stub).to have_been_requested.once
  end

  it 'binds the enrolled image grant to the biometric KYC token and keeps it out of the body' do
    _, claims = capture_token_claims
    stub_accepted('biometric_kyc')

    biometric_kyc_enrolled

    expect(claims).to eq([{ 'user_id' => 'user-1', 'product' => 'biometric_kyc',
                            'use_enrolled_image' => 'true' }])
    expect(WebMock).to(have_requested(:post, "#{TestHelpers::SANDBOX}/v3/biometric_kyc").with do |req|
      %w[use_enrolled_image selfie_image liveness_images].none? { |name| req.body.to_s.include?(name) }
    end)
  end

  it 'does not leak the grant into a later status call token' do
    _, claims = capture_token_claims
    stub_accepted('biometric_kyc')
    stub_status

    biometric_kyc_enrolled
    client.verifications.retrieve(job_id)

    expect(claims.length).to eq(2)
    expect(claims.last).to eq({})
  end

  it 'does not fetch or send a token for the three unauthenticated services calls' do
    token_stub = stub_token
    %w[bank_codes supported_id_types supported_documents].each do |path|
      stub_request(:get, "#{TestHelpers::SANDBOX}/v3/services/#{path}")
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
    end

    client.services.bank_codes
    client.services.supported_id_types
    client.services.supported_documents

    expect(token_stub).not_to have_been_requested
    expect(WebMock).to(have_requested(:get, "#{TestHelpers::SANDBOX}/v3/services/bank_codes")
      .with { |req| req.headers['Smileid-Token'].nil? })
  end

  it 'raises the parsed error when the token endpoint itself fails' do
    stub_request(:post, "#{TestHelpers::SANDBOX}/v3/token")
      .to_return(status: 401,
                 body: JSON.generate(status: 'Unauthorized', message: 'Invalid API key'),
                 headers: { 'Content-Type' => 'application/json' })
    stub_status

    expect { client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1') }
      .to raise_error(SmileID::Errors::AuthenticationError, 'Invalid API key')
  end
end
