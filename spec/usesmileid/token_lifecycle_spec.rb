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

  # Records the body of every /v3/token request, parsed to its text claims, and
  # mints token-1, token-2, ... so each request's token is identifiable.
  def capture_token_claims
    claims = []
    stub = stub_request(:post, "#{TestHelpers::SANDBOX}/v3/token")
           .to_return do |request|
      body = request.body.to_s.dup.force_encoding('UTF-8')
      claims << body.scan(/name="([^"]+)"\r\n\r\n([^\r]*)\r\n/).to_h
      { status: 200, body: JSON.generate(token: "token-#{claims.length}"), headers: json_headers }
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

  def status_body
    JSON.generate(status: 'clear', job_id: job_id, message: 'ok')
  end

  def stub_ok(method, path)
    status = method == :get ? 200 : 202
    body = path.include?('status') ? status_body : accepted_body
    stub_request(method, /\A#{Regexp.escape(TestHelpers::SANDBOX + path)}(\?.*)?\z/)
      .to_return(status: status, body: body, headers: json_headers)
  end

  let(:kyc_id) { { country: 'NG', id_type: 'NIN', id_number: '12345678901' } }
  let(:person) { { user_details: valid_user_details, consent: valid_consent, user_id: 'user-1' } }
  let(:selfie) { { selfie_image: 's', liveness_images: %w[a b] } }
  let(:doc_images) { selfie.merge(document: 'd', country: 'NG') }
  let(:compare_args) do
    { selfie_image: 's', comparison_image: 'c', comparison_image_type: 'ID_PHOTO' }
  end

  # product => [path, call with user "user-1"]
  let(:job_calls) do
    {
      'enhanced_kyc' => ['/v3/enhanced_kyc',
                         -> { client.enhanced_kyc.verify(**kyc_id, **person) }],
      'document_verification' => ['/v3/document_verification',
                                  -> { client.documents.verify(**doc_images, **person) }],
      'enhanced_document_verification' => [
        '/v3/enhanced_document_verification',
        -> { client.documents.verify_enhanced(**doc_images, id_type: 'PASSPORT', **person) }
      ],
      'residency_document_verification' => [
        '/v3/residency_document_verification',
        -> { client.documents.verify_residency(**doc_images, visa: 'v', **person) }
      ],
      'biometric_kyc' => ['/v3/biometric_kyc',
                          -> { client.biometric_kyc.verify(**kyc_id, **selfie, **person) }],
      'smart_selfie_registration' => ['/v3/registration',
                                      -> { client.biometric.enroll(**selfie, **person) }],
      'smart_selfie_authentication' => ['/v3/authentication',
                                        -> { client.biometric.authenticate(**selfie, **person) }],
      'smart_selfie_compare' => ['/v3/compare',
                                 -> { client.biometric.compare(**compare_args, **person) }]
    }
  end

  # name => [method, path, call]
  let(:unbound_calls) do
    fraud = { reason: 'ACCOUNT_TAKEOVER', reported_by: 'risk@partner.example' }
    {
      'status' => [:get, "/v3/status/#{job_id}", -> { client.verifications.retrieve(job_id) }],
      'replay' => [:post, "/v3/replay/#{job_id}", -> { client.verifications.replay(job_id) }],
      'report_fraud' => [:post, '/v3/users/user-1/report_fraud',
                         -> { client.users.flag_fraud('user-1', **fraud) }],
      'id_status' => [:get, '/v3/services/id_status',
                      -> { client.services.id_status(country: 'NG', id_type: 'NIN') }]
    }
  end

  %w[enhanced_kyc document_verification enhanced_document_verification
     residency_document_verification biometric_kyc smart_selfie_registration
     smart_selfie_authentication smart_selfie_compare].each do |product|
    it "binds the user_id and product into the #{product} token" do
      path, call = job_calls.fetch(product)
      _, claims = capture_token_claims
      stub_ok(:post, path)

      instance_exec(&call)

      expect(claims).to eq([{ 'user_id' => 'user-1', 'product' => product }])
    end
  end

  %w[status replay report_fraud id_status].each do |name|
    it "sends no token body for #{name}" do
      method, path, call = unbound_calls.fetch(name)
      token_stub = stub_token
      stub_ok(method, path)

      instance_exec(&call)

      expect(token_stub).to have_been_requested.once
      expect(WebMock).to(have_requested(:post, "#{TestHelpers::SANDBOX}/v3/token")
        .with { |req| req.body.to_s.empty? })
    end
  end

  it 'binds only the product when the job has no user_id' do
    _, claims = capture_token_claims
    stub_accepted('enhanced_kyc')

    enhanced_kyc

    expect(claims).to eq([{ 'product' => 'enhanced_kyc' }])
  end

  it 'binds only the product when compare has no user_id' do
    _, claims = capture_token_claims
    stub_accepted('compare')

    client.biometric.compare(**compare_args, **person.except(:user_id))

    expect(claims).to eq([{ 'product' => 'smart_selfie_compare' }])
  end

  it 'sends each job the token minted for it' do
    capture_token_claims
    kyc_tokens = []
    stub_request(:post, "#{TestHelpers::SANDBOX}/v3/enhanced_kyc")
      .to_return do |request|
      kyc_tokens << request.headers['Smileid-Token']
      { status: 202, body: accepted_body, headers: json_headers }
    end

    3.times { enhanced_kyc }

    expect(kyc_tokens).to eq(%w[token-1 token-2 token-3])
  end

  [
    ['a 401', { status: 401, body: JSON.generate(status: 'Unauthorized', message: 'bad key') },
     SmileID::Errors::AuthenticationError],
    ['a 503', { status: 503, body: JSON.generate(status: 'Error', message: 'busy') },
     SmileID::Errors::SmileIDError],
    ['an empty token', { status: 200, body: JSON.generate(token: '') },
     SmileID::Errors::UnexpectedResponseError]
  ].each do |label, response, error|
    it "never sends the job when the token request returns #{label}" do
      allow_any_instance_of(SmileID::Transport).to receive(:sleep_for)
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/token")
        .to_return(response.merge(headers: json_headers))
      kyc_stub = stub_accepted('enhanced_kyc')

      expect { enhanced_kyc }.to raise_error(error)
      expect(kyc_stub).not_to have_been_requested
    end
  end

  it "uses the call's timeout for the token request" do
    stub_token
    stub_accepted('enhanced_kyc')
    timeouts = []
    allow_any_instance_of(SmileID::Transport).to receive(:perform).and_wrap_original do |orig, *args|
      timeouts << [args[1], args[5]]
      orig.call(*args)
    end

    enhanced_kyc(timeout: 7)

    expect(timeouts.map(&:last)).to eq([7, 7])
    expect(timeouts.first.first).to end_with('/v3/token')
  end

  ['', ' user-1', 'user-1 '].each do |user_id|
    it "rejects the user_id #{user_id.inspect} without any request" do
      expect { enhanced_kyc(user_id: user_id) }
        .to raise_error(SmileID::Errors::ValidationError, /user_id must not be empty or padded/)
      expect(WebMock).not_to have_requested(:any, //)
    end
  end

  it 'rejects a padded body user_id for authentication without any request' do
    expect do
      client.biometric.authenticate(**selfie, **person, user_id: 'user-1 ')
    end.to raise_error(SmileID::Errors::ValidationError, /user_id must not be empty or padded/)
    expect(WebMock).not_to have_requested(:any, //)
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
    expect(WebMock).to have_requested(:post, "#{TestHelpers::SANDBOX}/v3/biometric_kyc")
      .with(headers: { 'Smileid-Token' => 'token-1' })
    expect(WebMock).to have_requested(:get, "#{TestHelpers::SANDBOX}/v3/status/#{job_id}")
      .with(headers: { 'Smileid-Token' => 'token-2' })
  end

  it 'refuses a grant without a user at the transport' do
    expect do
      client.send(:mint_token, SmileID::Generated::Operations.fetch(:biometric_kyc), {}, nil, true, nil)
    end.to raise_error(SmileID::Errors::ValidationError, /user_id is required when use_enrolled_image/)
    expect(WebMock).not_to have_requested(:any, //)
  end

  ['true', 'false', 1, nil].each do |value|
    it "rejects the non-boolean use_enrolled_image #{value.inspect}" do
      expect do
        client.biometric_kyc.verify(use_enrolled_image: value, **kyc_id, **person)
      end.to raise_error(SmileID::Errors::ValidationError, /use_enrolled_image must be true or false/)
      expect(WebMock).not_to have_requested(:any, //)
    end
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
