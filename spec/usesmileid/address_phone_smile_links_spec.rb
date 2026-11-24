# frozen_string_literal: true

require 'spec_helper'

# Golden fixture and parsing tests for address.verify, phone.verify and the
# smile_links operations, which were in the spec before syncing started.
RSpec.describe 'address, phone and smile links' do
  let(:jwt) { make_jwt }
  let(:client) { build_client }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:base) { TestHelpers::SANDBOX }
  let(:ref_id) { '65983864-e8c6-4d09-890a-2e5f88fc50f6' }

  before { stub_token(jwt) }

  def body_of(request)
    request.body.dup.force_encoding('UTF-8')
  end

  # Records the claims of every /v3/token request.
  def capture_claims
    claims = []
    stub_request(:post, "#{base}/v3/token").to_return do |request|
      claims << body_of(request).scan(/name="([^"]+)"\r\n\r\n([^\r]*)\r\n/).to_h
      { status: 200, body: JSON.generate(token: jwt), headers: json }
    end
    claims
  end

  def capture(method, path, status:, body:)
    captured = []
    stub_request(method, "#{base}#{path}").to_return do |request|
      captured << request
      { status: status, body: body, headers: json }
    end
    captured
  end

  def link_hash(**extra)
    { 'ref_id' => ref_id, 'link' => "https://links.usesmileid.com/v3/2/#{ref_id}",
      'name' => 'Onboarding', 'company_name' => 'Acme Pay', 'description' => nil,
      'id_types' => [{ 'country' => 'NG', 'id_type' => 'NIN', 'verification_method' => 'enhanced_kyc' }],
      'is_single_use' => false, 'callback_url' => 'https://partner.example/callback',
      'notice_privacy_policy_url' => 'https://partner.example/privacy',
      'logo_url' => 'https://portal.usesmileid.com/logo.png', 'redirect_url' => nil,
      'theme_color' => '#000', 'expires_at' => nil, 'disabled_at' => nil, 'partner_params' => nil,
      'user_id' => nil, 'token_provided_fields' => [], 'token_provided_values' => {},
      'created_at' => '2024-01-15T10:30:00Z', 'updated_at' => '2024-01-20T08:15:00Z' }.merge(extra)
  end

  describe 'address.verify' do
    let(:accepted) do
      JSON.generate(status: 'accepted', message: 'Job submitted successfully',
                    job_id: 'job_1', user_id: 'user_1')
    end

    it 'sends the golden multipart shape and binds the address_verification product' do
      claims = capture_claims
      captured = capture(:post, '/v3/address', status: 202, body: accepted)

      result = client.address.verify(
        address: '12 Marina Rd, Lagos', country: 'NG', utility_number: '45012345678',
        utility_provider: 'ikeja_electric', utility_type: 'PrePaid', user_id: 'user_1',
        user_details: valid_user_details, consent: valid_consent,
        callback_url: 'https://example.com/cb', partner_params: { 'order' => '1' },
        metadata: [{ name: 'k', value: 'v' }]
      )

      request = captured.fetch(0)
      expect(request.headers['Smileid-Token']).to eq(jwt)
      expect(request.headers['Smileid-Partner-Id']).to be_nil
      expect(request.headers['User-Id']).to be_nil
      expect(request.headers['Content-Type']).to start_with('multipart/form-data; boundary=')
      body = body_of(request)
      expect(body).to include("name=\"address\"\r\n\r\n12 Marina Rd, Lagos\r\n")
      expect(body).to include("name=\"country\"\r\n\r\nNG\r\n")
      expect(body).to include("name=\"utility_number\"\r\n\r\n45012345678\r\n")
      expect(body).to include("name=\"utility_provider\"\r\n\r\nikeja_electric\r\n")
      expect(body).to include("name=\"utility_type\"\r\n\r\nPrePaid\r\n")
      expect(body).to include("name=\"user_id\"\r\n\r\nuser_1\r\n")
      expect(body).to include("name=\"callback_url\"\r\n\r\nhttps://example.com/cb\r\n")
      expect(body).not_to include('name="id_number"')
      expect(body).to include("name=\"partner_params\"\r\nContent-Type: application/json\r\n\r\n" \
                              '{"order":"1"}')
      expect(body).to include("name=\"metadata\"\r\nContent-Type: application/json\r\n\r\n" \
                              '[{"name":"k","value":"v"}]')
      expect(body).to include("name=\"user_details\"\r\nContent-Type: application/json\r\n\r\n" \
                              '{"given_names":"John","last_name":"Doe","email":"john@example.com"}')
      expect(claims).to eq([{ 'user_id' => 'user_1', 'product' => 'address_verification' }])
      expect([result.accepted?, result.job_id, result.user_id]).to eq([true, 'job_1', 'user_1'])
    end

    it 'sends an id_number for South Africa and falls back to the default callback URL' do
      default_client = build_client(default_callback_url: 'https://example.com/default')
      captured = capture(:post, '/v3/address', status: 202, body: accepted)

      default_client.address.verify(address: '1 Long St', country: 'ZA', id_number: '8001015009087',
                                    user_details: valid_user_details, consent: valid_consent)

      body = body_of(captured.fetch(0))
      expect(body).to include("name=\"id_number\"\r\n\r\n8001015009087\r\n")
      expect(body).to include("name=\"callback_url\"\r\n\r\nhttps://example.com/default\r\n")
    end

    it 'requires an id_number or a utility_number before sending' do
      expect do
        client.address.verify(address: 'a', country: 'NG', user_details: valid_user_details,
                              consent: valid_consent)
      end.to raise_error(SmileID::Errors::ValidationError, /id_number or utility_number/)
      expect(WebMock).not_to have_requested(:any, //)
    end

    it 'rejects an unknown utility_type before sending' do
      expect do
        client.address.verify(address: 'a', country: 'NG', utility_number: '1', utility_type: 'Other',
                              user_details: valid_user_details, consent: valid_consent)
      end.to raise_error(SmileID::Errors::ValidationError, /utility_type/)
      expect(WebMock).not_to have_requested(:any, //)
    end
  end

  describe 'phone.verify' do
    let(:accepted) do
      JSON.generate(status: 'accepted', message: 'Job submitted successfully', job_id: 'job_2',
                    user_id: 'user_2', created_at: '2026-03-10T12:00:00.000Z')
    end

    it 'sends the golden multipart shape and binds the phone_number_verification product' do
      claims = capture_claims
      captured = capture(:post, '/v3/phone', status: 202, body: accepted)

      result = client.phone.verify(
        country: 'GH', phone_number: '+233241234567', operator: 'MTN', id_number: 'GHA-1',
        user_id: 'user_2', user_details: valid_user_details, consent: valid_consent,
        callback_url: 'https://example.com/cb'
      )

      request = captured.fetch(0)
      expect(request.headers['Smileid-Token']).to eq(jwt)
      expect(request.headers['User-Id']).to be_nil
      expect(request.headers['Content-Type']).to start_with('multipart/form-data; boundary=')
      body = body_of(request)
      expect(body).to include("name=\"country\"\r\n\r\nGH\r\n")
      expect(body).to include("name=\"phone_number\"\r\n\r\n+233241234567\r\n")
      expect(body).to include("name=\"operator\"\r\n\r\nMTN\r\n")
      expect(body).to include("name=\"id_number\"\r\n\r\nGHA-1\r\n")
      expect(body).to include("name=\"user_id\"\r\n\r\nuser_2\r\n")
      expect(body).to include("name=\"callback_url\"\r\n\r\nhttps://example.com/cb\r\n")
      expect(body).to include("name=\"consent\"\r\nContent-Type: application/json\r\n\r\n")
      expect(claims).to eq([{ 'user_id' => 'user_2', 'product' => 'phone_number_verification' }])
      expect([result.accepted?, result.job_id, result.created_at])
        .to eq([true, 'job_2', '2026-03-10T12:00:00.000Z'])
    end

    it 'sends no operator or id_number outside Ghana and Kenya' do
      claims = capture_claims
      captured = capture(:post, '/v3/phone', status: 202, body: accepted)

      client.phone.verify(country: 'NG', phone_number: '+2348012345678',
                          user_details: valid_user_details, consent: valid_consent,
                          callback_url: 'https://example.com/cb')

      body = body_of(captured.fetch(0))
      expect(body).not_to include('name="operator"')
      expect(body).not_to include('name="id_number"')
      expect(claims).to eq([{ 'product' => 'phone_number_verification' }])
    end

    it 'requires an id_number for Kenya before sending' do
      expect do
        client.phone.verify(country: 'KE', phone_number: '+254712345678',
                            user_details: valid_user_details, consent: valid_consent)
      end.to raise_error(SmileID::Errors::ValidationError, /id_number is required for KE/)
      expect(WebMock).not_to have_requested(:any, //)
    end

    it 'rejects an unknown operator before sending' do
      expect do
        client.phone.verify(country: 'GH', phone_number: '+233241234567', operator: 'ORANGE',
                            user_details: valid_user_details, consent: valid_consent)
      end.to raise_error(SmileID::Errors::ValidationError, /operator must be one of/)
      expect(WebMock).not_to have_requested(:any, //)
    end
  end

  describe 'smile_links.create' do
    let(:created) do
      JSON.generate(link: "https://links.usesmileid.com/v3/2/#{ref_id}", message: 'Link created',
                    ref_id: ref_id, user_id: nil)
    end
    let(:id_types) { [{ country: 'NG', id_type: 'NIN', verification_method: 'enhanced_kyc' }] }

    it 'sends the golden multipart shape with a token that has no claims' do
      claims = capture_claims
      captured = capture(:post, '/v3/smile_links', status: 201, body: created)

      result = client.smile_links.create(
        id_types: id_types, name: 'Onboarding', notice_privacy_policy_url: 'https://p.example/privacy',
        is_single_use: true, company_name: 'Acme Pay', callback_url: 'https://p.example/cb',
        description: 'KYC', expires_at: Time.new(2027, 1, 2, 3, 4, 5, '+02:00'),
        logo_url: 'https://p.example/logo.png', redirect_url: 'https://p.example/done',
        theme_color: '#0a0a0a', partner_params: { 'k' => 'v' }, user_id: 'user_9'
      )

      request = captured.fetch(0)
      expect(request.headers['Smileid-Token']).to eq(jwt)
      expect(request.headers['Content-Type']).to start_with('multipart/form-data; boundary=')
      body = body_of(request)
      expect(body).to include("name=\"id_types\"\r\nContent-Type: application/json\r\n\r\n" \
                              '[{"country":"NG","id_type":"NIN","verification_method":"enhanced_kyc"}]')
      expect(body).to include("name=\"name\"\r\n\r\nOnboarding\r\n")
      expect(body).to include("name=\"company_name\"\r\n\r\nAcme Pay\r\n")
      expect(body).to include("name=\"notice_privacy_policy_url\"\r\n\r\nhttps://p.example/privacy\r\n")
      expect(body).to include("name=\"is_single_use\"\r\n\r\ntrue\r\n")
      expect(body).to include("name=\"callback_url\"\r\n\r\nhttps://p.example/cb\r\n")
      expect(body).to include("name=\"description\"\r\n\r\nKYC\r\n")
      expect(body).to include("name=\"expires_at\"\r\n\r\n2027-01-02T01:04:05.000Z\r\n")
      expect(body).to include("name=\"logo_url\"\r\n\r\nhttps://p.example/logo.png\r\n")
      expect(body).to include("name=\"redirect_url\"\r\n\r\nhttps://p.example/done\r\n")
      expect(body).to include("name=\"theme_color\"\r\n\r\n#0a0a0a\r\n")
      expect(body).to include("name=\"partner_params\"\r\nContent-Type: application/json\r\n\r\n" \
                              '{"k":"v"}')
      expect(body).to include("name=\"user_id\"\r\n\r\nuser_9\r\n")
      expect(claims).to eq([{}])
      expect([result.ref_id, result.link, result.message, result.user_id])
        .to eq([ref_id, "https://links.usesmileid.com/v3/2/#{ref_id}", 'Link created', nil])
      expect(result.raw['ref_id']).to eq(ref_id)
    end

    it 'sends an expires_at string as given and the default callback URL when none is passed' do
      default_client = build_client(default_callback_url: 'https://example.com/default')
      captured = capture(:post, '/v3/smile_links', status: 201, body: created)

      default_client.smile_links.create(
        id_types: id_types, name: 'n', notice_privacy_policy_url: 'https://p.example/privacy',
        is_single_use: false, expires_at: '2027-01-02T00:00:00Z'
      )

      body = body_of(captured.fetch(0))
      expect(body).to include("name=\"expires_at\"\r\n\r\n2027-01-02T00:00:00Z\r\n")
      expect(body).to include("name=\"is_single_use\"\r\n\r\nfalse\r\n")
      expect(body).to include("name=\"callback_url\"\r\n\r\nhttps://example.com/default\r\n")
    end

    it 'rejects missing id_types before sending' do
      [nil, [], 'NG'].each do |bad|
        expect do
          client.smile_links.create(id_types: bad, name: 'n', is_single_use: false,
                                    notice_privacy_policy_url: 'https://p.example/privacy')
        end.to raise_error(SmileID::Errors::ValidationError, /id_types must be a non-empty array/)
      end
      expect(WebMock).not_to have_requested(:any, //)
    end

    it 'raises a ConflictError for a user_id already in use' do
      capture(:post, '/v3/smile_links', status: 409,
                                        body: JSON.generate(status: 'Conflict', message: 'User ID is taken.'))

      expect do
        client.smile_links.create(id_types: id_types, name: 'n', is_single_use: true,
                                  notice_privacy_policy_url: 'https://p.example/privacy',
                                  callback_url: 'https://p.example/cb')
      end.to raise_error(SmileID::Errors::ConflictError)
    end
  end

  describe 'smile_links.list' do
    it 'sends the query and parses links with their counts and the pagination meta' do
      claims = capture_claims
      stub = stub_request(:get, "#{base}/v3/smile_links")
             .with(query: { 'limit' => '10', 'page' => '2', 'single_use' => 'false' })
             .to_return(status: 200, headers: json, body: JSON.generate(
               links: [link_hash('clear' => 12, 'block' => 1, 'attention' => 2, 'error' => 0,
                                 'successful_jobs' => 14, 'failed_jobs' => 1, 'total_jobs' => 15)],
               meta: { current_page: 2, limit: 10, total_count: 11, total_pages: 2 }
             ))

      page = client.smile_links.list(limit: 10, page: 2, single_use: false)

      expect(stub).to have_been_requested
      expect(claims).to eq([{}])
      expect(page.meta).to eq('current_page' => 2, 'limit' => 10, 'total_count' => 11, 'total_pages' => 2)
      link = page.links.fetch(0)
      expect([link.ref_id, link.name, link.is_single_use, link.clear, link.successful_jobs,
              link.failed_jobs, link.total_jobs, link.disabled?])
        .to eq([ref_id, 'Onboarding', false, 12, 14, 1, 15, false])
    end

    it 'sends no query by default and tolerates an empty response' do
      stub = stub_request(:get, "#{base}/v3/smile_links").with(query: {})
                                                         .to_return(status: 200, headers: json, body: '{}')

      page = client.smile_links.list

      expect(stub).to have_been_requested
      expect([page.links, page.meta]).to eq([[], {}])
    end
  end

  describe 'smile_links.get' do
    it 'reads the link, including the token-bound fields' do
      stub_request(:get, "#{base}/v3/smile_links/#{ref_id}").to_return(
        status: 200, headers: json,
        body: JSON.generate(link_hash(
                              'disabled_at' => '2024-02-01T00:00:00Z', 'user_id' => 'user_7',
                              'token_provided_fields' => %w[consent country],
                              'token_provided_values' => { 'country' => 'NG' }
                            ))
      )

      link = client.smile_links.get(ref_id)

      expect([link.ref_id, link.company_name, link.callback_url, link.user_id, link.disabled_at,
              link.token_provided_fields, link.token_provided_values, link.clear])
        .to eq([ref_id, 'Acme Pay', 'https://partner.example/callback', 'user_7',
                '2024-02-01T00:00:00Z', %w[consent country], { 'country' => 'NG' }, nil])
      expect(link.disabled?).to be(true)
      expect(link.raw['name']).to eq('Onboarding')
    end

    it 'raises NotFoundError for an unknown link' do
      stub_request(:get, "#{base}/v3/smile_links/#{ref_id}")
        .to_return(status: 404, headers: json,
                   body: JSON.generate(status: 'Not Found', message: 'Link not found'))

      expect { client.smile_links.get(ref_id) }.to raise_error(SmileID::Errors::NotFoundError)
    end
  end

  describe 'smile_links.update' do
    it 'sends a PUT with id_types and is_disabled as multipart parts' do
      claims = capture_claims
      disabled = JSON.generate(link_hash('disabled_at' => '2024-02-01T00:00:00Z'))
      captured = capture(:put, "/v3/smile_links/#{ref_id}", status: 200, body: disabled)

      link = client.smile_links.update(
        ref_id, id_types: [{ country: 'KE', id_type: 'NATIONAL_ID', verification_method: 'biometric_kyc' }],
                is_disabled: true
      )

      request = captured.fetch(0)
      expect(request.headers['Content-Type']).to start_with('multipart/form-data; boundary=')
      body = body_of(request)
      expect(body).to include("name=\"id_types\"\r\nContent-Type: application/json\r\n\r\n" \
                              '[{"country":"KE","id_type":"NATIONAL_ID",' \
                              '"verification_method":"biometric_kyc"}]')
      expect(body).to include("name=\"is_disabled\"\r\n\r\ntrue\r\n")
      expect(claims).to eq([{}])
      expect(link.disabled?).to be(true)
    end

    it 'sends is_disabled alone, including false to re-enable' do
      captured = capture(:put, "/v3/smile_links/#{ref_id}", status: 200, body: JSON.generate(link_hash))

      link = client.smile_links.update(ref_id, is_disabled: false)

      body = body_of(captured.fetch(0))
      expect(body).to include("name=\"is_disabled\"\r\n\r\nfalse\r\n")
      expect(body).not_to include('name="id_types"')
      expect(link.disabled?).to be(false)
    end

    it 'requires id_types or is_disabled before sending' do
      expect { client.smile_links.update(ref_id) }
        .to raise_error(SmileID::Errors::ValidationError, /id_types or is_disabled/)
      expect { client.smile_links.update(ref_id, id_types: []) }
        .to raise_error(SmileID::Errors::ValidationError, /id_types must be a non-empty array/)
      expect(WebMock).not_to have_requested(:any, //)
    end

    it 'raises a ConflictError for a single-use link that has been used' do
      capture(:put, "/v3/smile_links/#{ref_id}", status: 409,
                                                 body: JSON.generate(status: 'Conflict', message: 'used'))

      expect { client.smile_links.update(ref_id, is_disabled: true) }
        .to raise_error(SmileID::Errors::ConflictError)
    end
  end
end
