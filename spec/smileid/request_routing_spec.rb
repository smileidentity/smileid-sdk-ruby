# frozen_string_literal: true

require 'spec_helper'

# Matrix item 1 (routing half): header routing per operation, wire shape per
# endpoint (spec sections 4 and 6).
RSpec.describe 'request routing' do
  let(:jwt) { make_jwt }
  let(:client) { build_client }

  before { stub_token(jwt) }

  def entry_args
    { user_details: valid_user_details, consent: valid_consent }
  end

  describe 'enhanced_kyc.verify (spec 6.1)' do
    it 'sends the golden multipart shape with User-ID header and no Partner-ID header' do
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/enhanced_kyc")
        .to_return do |request|
          captured = request
          { status: 202, body: accepted_body, headers: { 'Content-Type' => 'application/json' } }
        end

      response = client.enhanced_kyc.verify(
        country: 'NG', id_type: 'NIN', id_number: '12345678901',
        user_id: 'user_01h8x9y2z3a4b5c6d7e8f9g0h1', **entry_args
      )

      expect(captured.headers['Smileid-Token']).to eq(jwt)
      expect(captured.headers['User-Id']).to eq('user_01h8x9y2z3a4b5c6d7e8f9g0h1')
      expect(captured.headers['Smileid-Partner-Id']).to be_nil
      expect(captured.headers['Smileid-Source-Sdk']).to eq('ruby')
      expect(captured.headers['Smileid-Source-Sdk-Version']).to eq(SmileID::VERSION)
      expect(captured.headers['User-Agent'])
        .to eq("smileid-sdk-ruby/#{SmileID::VERSION} (ruby/#{RUBY_VERSION})")
      expect(captured.headers['Content-Type']).to start_with('multipart/form-data; boundary=')

      body = captured.body.dup.force_encoding('UTF-8')
      expect(body).to include("name=\"country\"\r\n\r\nNG\r\n")
      expect(body).to include("name=\"id_type\"\r\n\r\nNIN\r\n")
      expect(body).to include("name=\"id_number\"\r\n\r\n12345678901\r\n")
      expect(body).to include("name=\"user_details\"\r\nContent-Type: application/json\r\n\r\n" \
                              '{"given_names":"John","last_name":"Doe","email":"john@example.com"}')
      expect(body).to include("name=\"consent\"\r\nContent-Type: application/json\r\n\r\n" \
                              '{"granted":true,"granted_at":"2026-03-06T12:00:00.000Z",' \
                              '"notice_language":"EN",' \
                              '"notice_privacy_policy_url":"https://example.com/privacy"}')

      expect(response.job_id).to eq('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
      expect(response.accepted?).to be(true)
    end
  end

  describe 'documents.verify (spec 6.2)' do
    it 'sends SmileID-Partner-ID, repeated liveness_images, and binary parts' do
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/document_verification")
        .to_return do |request|
          captured = request
          { status: 202, body: accepted_body(status: 'accepted'),
            headers: { 'Content-Type' => 'application/json' } }
        end

      client.documents.verify(
        selfie_image: 'selfie-bytes',
        liveness_images: %w[l1 l2 l3 l4 l5 l6],
        document: 'doc-bytes',
        country: 'NG',
        user_id: 'user_01h8x9y2z3a4b5c6d7e8f9g0h1', **entry_args
      )

      expect(captured.headers['Smileid-Partner-Id']).to eq('1234')
      body = captured.body.dup.force_encoding('UTF-8')
      expect(body.scan('name="liveness_images"').length).to eq(6)
      expect(body).not_to include('liveness_images[')
      expect(body).to match(%r{name="selfie_image"; filename="selfie\.jpg"\r\nContent-Type: image/jpeg})
      expect(body).to match(/name="document"; filename="document\.jpg"/)
    end
  end

  describe 'documents.verify_enhanced (spec 6.3)' do
    it 'requires id_type and sends the Partner-ID header' do
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/enhanced_document_verification")
        .to_return do |request|
          captured = request
          { status: 202, body: accepted_body(status: 'accepted'),
            headers: { 'Content-Type' => 'application/json' } }
        end

      client.documents.verify_enhanced(
        id_type: 'PASSPORT', selfie_image: 's', liveness_images: %w[a b c d e f],
        document: 'd', country: 'NG', **entry_args
      )

      expect(captured.headers['Smileid-Partner-Id']).to eq('1234')
      expect(captured.body.dup.force_encoding('UTF-8')).to include("name=\"id_type\"\r\n\r\nPASSPORT")
    end
  end

  describe 'biometric_kyc.verify (spec 6.4)' do
    it 'sends the Partner-ID header with id fields and images' do
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/biometric_kyc")
        .to_return do |request|
          captured = request
          { status: 202, body: accepted_body(status: 'accepted'),
            headers: { 'Content-Type' => 'application/json' } }
        end

      client.biometric_kyc.verify(
        selfie_image: 's', liveness_images: %w[a b c d e f],
        country: 'NG', id_type: 'NIN', id_number: '12345678901', **entry_args
      )

      expect(captured.headers['Smileid-Partner-Id']).to eq('1234')
      body = captured.body.dup.force_encoding('UTF-8')
      expect(body).to include("name=\"id_number\"\r\n\r\n12345678901")
      expect(body.scan('name="liveness_images"').length).to eq(6)
    end
  end

  describe 'biometric.enroll (spec 6.5)' do
    it 'sends no Partner-ID header and scalars as text parts' do
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/registration")
        .to_return do |request|
          captured = request
          { status: 202, body: accepted_body, headers: { 'Content-Type' => 'application/json' } }
        end

      client.biometric.enroll(
        selfie_image: 's', liveness_images: %w[a b c d e f],
        allow_new_enroll: true, user_id: 'user-1', **entry_args
      )

      expect(captured.headers['Smileid-Partner-Id']).to be_nil
      expect(captured.headers['User-Id']).to eq('user-1')
      expect(captured.body.dup.force_encoding('UTF-8'))
        .to include("name=\"allow_new_enroll\"\r\n\r\ntrue")
    end
  end

  describe 'biometric.authenticate (spec 6.6)' do
    it 'puts user_id in the body, not the User-ID header' do
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/authentication")
        .to_return do |request|
          captured = request
          { status: 202, body: accepted_body, headers: { 'Content-Type' => 'application/json' } }
        end

      client.biometric.authenticate(
        user_id: 'user-42', selfie_image: 's', liveness_images: %w[a b c d e f], **entry_args
      )

      expect(captured.headers['User-Id']).to be_nil
      expect(captured.body.dup.force_encoding('UTF-8')).to include("name=\"user_id\"\r\n\r\nuser-42")
    end
  end

  describe 'biometric.compare (spec 6.7)' do
    it 'sends comparison image fields and optional body user_id' do
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/compare")
        .to_return do |request|
          captured = request
          { status: 202, body: accepted_body, headers: { 'Content-Type' => 'application/json' } }
        end

      client.biometric.compare(
        selfie_image: 's', comparison_image: 'c', comparison_image_type: 'ID_PHOTO',
        user_id: 'user-42', **entry_args
      )

      body = captured.body.dup.force_encoding('UTF-8')
      expect(body).to include("name=\"comparison_image_type\"\r\n\r\nID_PHOTO")
      expect(body).to match(/name="comparison_image"; filename="comparison\.jpg"/)
      expect(body).to include("name=\"user_id\"\r\n\r\nuser-42")
      expect(captured.headers['User-Id']).to be_nil
    end
  end

  describe 'verifications.replay (spec 6.10)' do
    it 'sends a JSON body, not multipart' do
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/replay/job_01h8x9y2z3a4b5c6d7e8f9g0h1")
        .to_return do |request|
          captured = request
          { status: 202,
            body: JSON.generate(status: 'accepted', job_id: 'job_01h8x9y2z3a4b5c6d7e8f9g0h1',
                                user_id: 'test-user', message: 'Callback replay queued successfully.'),
            headers: { 'Content-Type' => 'application/json' } }
        end

      response = client.verifications.replay(
        'job_01h8x9y2z3a4b5c6d7e8f9g0h1', callback_url: 'https://example.com/cb'
      )

      expect(captured.headers['Content-Type']).to eq('application/json')
      expect(JSON.parse(captured.body)).to eq('callback_url' => 'https://example.com/cb')
      expect(response.accepted?).to be(true)
    end

    it 'sends no body when callback_url is omitted' do
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/replay/job_01h8x9y2z3a4b5c6d7e8f9g0h1")
        .to_return do |request|
          captured = request
          { status: 202,
            body: JSON.generate(status: 'accepted', job_id: 'job_01h8x9y2z3a4b5c6d7e8f9g0h1',
                                user_id: 'test-user', message: 'ok'),
            headers: { 'Content-Type' => 'application/json' } }
        end

      client.verifications.replay('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
      expect(captured.body.to_s).to eq('')
    end
  end

  describe 'users.report_fraud (spec 6.11)' do
    it 'sends a multipart body with user_id in the path' do
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/users/user-123/report_fraud")
        .to_return do |request|
          captured = request
          { status: 202,
            body: JSON.generate(status: 'accepted', message: 'Fraud report accepted',
                                user_id: 'user-123'),
            headers: { 'Content-Type' => 'application/json' } }
        end

      response = client.users.report_fraud(
        'user-123', is_fraud: true, reason: 'FIRST_PARTY_FRAUD', reported_by: 'risk@example.com'
      )

      expect(captured.headers['Content-Type']).to start_with('multipart/form-data')
      body = captured.body.dup.force_encoding('UTF-8')
      expect(body).to include("name=\"is_fraud\"\r\n\r\ntrue")
      expect(body).to include("name=\"reason\"\r\n\r\nFIRST_PARTY_FRAUD")
      expect(body).to include("name=\"reported_by\"\r\n\r\nrisk@example.com")
      expect(response.accepted?).to be(true)
    end
  end

  describe 'services (spec 6.12-6.15)' do
    it 'passes query params on bank_codes and parses the response' do
      stub = stub_request(:get, "#{TestHelpers::SANDBOX}/v3/services/bank_codes")
             .with(query: { 'country' => 'NG' })
             .to_return(status: 200,
                        body: JSON.generate(bank_codes: [{ 'code' => '044', 'country' => 'NG',
                                                           'name' => 'Access Bank' }]),
                        headers: { 'Content-Type' => 'application/json' })

      response = client.services.bank_codes(country: 'NG')
      expect(stub).to have_been_requested
      expect(response.bank_codes.first['name']).to eq('Access Bank')
    end

    it 'requires country and id_type on id_status and sends the token' do
      stub = stub_request(:get, "#{TestHelpers::SANDBOX}/v3/services/id_status")
             .with(query: { 'country' => 'NG', 'id_type' => 'BVN' },
                   headers: { 'SmileID-Token' => jwt })
             .to_return(status: 200,
                        body: JSON.generate(last_checked: '2026-04-14T12:30:00.000Z',
                                            last_check_status: 'success',
                                            last_hour_success_rate: '95%',
                                            last_known_status: 'online',
                                            last_check_success_rate: '90%'),
                        headers: { 'Content-Type' => 'application/json' })

      response = client.services.id_status(country: 'NG', id_type: 'BVN')
      expect(stub).to have_been_requested
      expect(response.last_known_status).to eq('online')
      expect(response.last_hour_success_rate).to eq('95%')
    end

    it 'passes supported_documents query params' do
      stub = stub_request(:get, "#{TestHelpers::SANDBOX}/v3/services/supported_documents")
             .with(query: { 'continent' => 'AFRICA', 'country_code' => 'NG', 'locale' => 'en-GB' })
             .to_return(status: 200, body: JSON.generate(valid_documents: []),
                        headers: { 'Content-Type' => 'application/json' })

      client.services.supported_documents(continent: 'AFRICA', country_code: 'NG', locale: 'en-GB')
      expect(stub).to have_been_requested
    end
  end

  describe 'default_callback_url (spec 2.1)' do
    it 'is used when a call omits callback_url' do
      cb_client = build_client(default_callback_url: 'https://example.com/default-cb')
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/enhanced_kyc")
        .to_return do |request|
          captured = request
          { status: 202, body: accepted_body, headers: { 'Content-Type' => 'application/json' } }
        end

      cb_client.enhanced_kyc.verify(country: 'NG', id_type: 'NIN', id_number: '1', **entry_args)
      expect(captured.body.dup.force_encoding('UTF-8'))
        .to include("name=\"callback_url\"\r\n\r\nhttps://example.com/default-cb")
    end
  end

  describe 'base_url override (spec 2.1)' do
    it 'wins over environment' do
      override = build_client(base_url: 'https://api.smileidentity.com', environment: :sandbox)
      stub_token(host: TestHelpers::PRODUCTION)
      stub = stub_request(:get, "#{TestHelpers::PRODUCTION}/v3/status/job_01h8x9y2z3a4b5c6d7e8f9g0h1")
             .to_return(status: 200,
                        body: JSON.generate(status: 'complete', job_id: 'job_01h8x9y2z3a4b5c6d7e8f9g0h1'),
                        headers: { 'Content-Type' => 'application/json' })

      override.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
      expect(stub).to have_been_requested
    end
  end
end
