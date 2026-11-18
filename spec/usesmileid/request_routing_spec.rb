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

  describe 'documents.verify_residency' do
    it 'posts the visa as a binary part, defaulting id_type to PASSPORT' do
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/residency_document_verification")
        .to_return do |request|
          captured = request
          { status: 202, body: accepted_body(status: 'accepted'),
            headers: { 'Content-Type' => 'application/json' } }
        end

      client.documents.verify_residency(
        selfie_image: 's', liveness_images: %w[a b c d e f],
        document: 'd', visa: 'v', country: 'ZA', **entry_args
      )

      expect(captured.headers['Smileid-Partner-Id']).to eq('1234')
      body = captured.body.dup.force_encoding('UTF-8')
      expect(body).to match(%r{name="visa"; filename="visa\.jpg"\r\nContent-Type: image/jpeg})
      expect(body).to include("name=\"id_type\"\r\n\r\nPASSPORT")
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

  describe 'verifications.replay (spec 6.10, multipart body)' do
    it 'sends a multipart body with a single callback_url text part' do
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

      expect(captured.headers['Content-Type']).to start_with('multipart/form-data; boundary=')
      body = captured.body.dup.force_encoding('UTF-8')
      expect(body).to include('Content-Disposition: form-data; name="callback_url"' \
                              "\r\n\r\nhttps://example.com/cb\r\n")
      expect(body.scan('Content-Disposition').length).to eq(1)
      expect(response.accepted?).to be(true)
    end

    it 'sends no body and no content type when callback_url is omitted' do
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
      expect(captured.headers['Content-Type'].to_s).not_to include('json')
      expect(captured.headers['Content-Type'].to_s).not_to include('multipart')
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

  describe 'path parameter encoding (fleet standard)' do
    it 'keeps golden ids byte-identical on the wire' do
      stub = stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/job_01h8x9y2z3a4b5c6d7e8f9g0h1")
             .to_return(status: 200,
                        body: JSON.generate(status: 'clear', message: 'Job completed',
                                            job_id: 'job_01h8x9y2z3a4b5c6d7e8f9g0h1'),
                        headers: { 'Content-Type' => 'application/json' })

      client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
      expect(stub).to have_been_requested
    end

    it 'encodes a hostile user_id as a single path segment' do
      encoded = 'user%2F..%2Fadmin%20x'
      stub = stub_request(:post, "#{TestHelpers::SANDBOX}/v3/users/#{encoded}/report_fraud")
             .to_return(status: 202,
                        body: JSON.generate(status: 'accepted', message: 'ok',
                                            user_id: 'user/../admin x'),
                        headers: { 'Content-Type' => 'application/json' })

      client.users.report_fraud('user/../admin x', is_fraud: false, notes: 'cleared',
                                                   reported_by: 'risk@example.com')
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

  describe 'aml.submit (One-Time AML)' do
    let(:aml_args) { { countries: %w[NG KE], full_name: 'John Doe', **entry_args } }

    it 'sends countries and aliases as JSON parts and binds the token to one_time_aml' do
      captured = nil
      token_stub = stub_request(:post, "#{TestHelpers::SANDBOX}/v3/token")
                   .with { |request| request.body.include?('name="product"') }
                   .to_return(status: 200, body: JSON.generate(token: jwt),
                              headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/aml")
        .to_return do |request|
          captured = request
          { status: 202, body: accepted_body(status: 'accepted'),
            headers: { 'Content-Type' => 'application/json' } }
        end

      response = client.aml.submit(
        **aml_args, aliases: ['Johnny Doe'], birth_year: '1990', strict_match: false,
                    search_existing_user: false, callback_url: 'https://example.com/cb',
                    partner_params: { 'order_id' => 'ORD-1' }, user_id: 'user-1234'
      )

      expect(token_stub).to have_been_requested
      expect(captured.headers['Smileid-Token']).to eq(jwt)
      expect(captured.headers['User-Id']).to eq('user-1234')
      expect(captured.headers['Smileid-Partner-Id']).to be_nil
      expect(captured.headers['Content-Type']).to start_with('multipart/form-data; boundary=')
      body = captured.body.dup.force_encoding('UTF-8')
      expect(body).to include("name=\"countries\"\r\nContent-Type: application/json\r\n\r\n" \
                              "[\"NG\",\"KE\"]\r\n")
      expect(body).to include("name=\"aliases\"\r\nContent-Type: application/json\r\n\r\n" \
                              "[\"Johnny Doe\"]\r\n")
      expect(body).to include("name=\"full_name\"\r\n\r\nJohn Doe\r\n")
      expect(body).to include("name=\"birth_year\"\r\n\r\n1990\r\n")
      expect(body).to include("name=\"strict_match\"\r\n\r\nfalse\r\n")
      expect(body).to include("name=\"search_existing_user\"\r\n\r\nfalse\r\n")
      expect(body).to include("name=\"user_id\"\r\n\r\nuser-1234\r\n")
      expect(body).to include("name=\"callback_url\"\r\n\r\nhttps://example.com/cb\r\n")
      expect(body).to include("name=\"partner_params\"\r\nContent-Type: application/json\r\n\r\n" \
                              '{"order_id":"ORD-1"}')
      expect(body).to include("name=\"user_details\"\r\nContent-Type: application/json\r\n\r\n" \
                              '{"given_names":"John","last_name":"Doe","email":"john@example.com"}')
      expect(response.job_id).to eq('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
      expect(response.accepted?).to be(true)
    end

    it 'falls back to the default callback URL' do
      cb_client = build_client(default_callback_url: 'https://example.com/default-cb')
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/aml")
        .to_return do |request|
          captured = request
          { status: 202, body: accepted_body, headers: { 'Content-Type' => 'application/json' } }
        end

      cb_client.aml.submit(**aml_args)
      expect(captured.body.dup.force_encoding('UTF-8'))
        .to include("name=\"callback_url\"\r\n\r\nhttps://example.com/default-cb")
    end

    it 'rejects a non-https callback URL before sending' do
      expect { client.aml.submit(**aml_args, callback_url: 'http://example.com/cb') }
        .to raise_error(SmileID::Errors::ValidationError)
    end
  end

  describe 'aml.submit_sync (One-Time AML, inline result)' do
    let(:aml_args) { { countries: ['NG'], full_name: 'John Doe', **entry_args } }
    let(:result_body) do
      JSON.generate(
        status: 'attention', message: 'Screening completed: matches found.',
        reason: 'aml_match_found', created_at: '2026-07-20T12:00:00.000Z',
        completed_at: '2026-07-20T12:00:01.000Z', product: 'one_time_aml',
        partner_params: nil, kyc_receipt: 'https://example.com/receipt', strict_match: true,
        no_of_persons_found: 1, people: [{ 'name' => 'Gbenga Afolabi' }],
        user_provided_info: { given_names: 'John', last_name: 'Doe',
                              email: 'john@example.com', phone_number: nil },
        consent: { granted: true }, antifraud: nil, device_signals: nil
      )
    end

    it 'sends the idempotency key and parses the inline result with its headers' do
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/aml/sync")
        .to_return do |request|
          captured = request
          { status: 200, body: result_body,
            headers: { 'Content-Type' => 'application/json',
                       'SmileID-Job-ID' => 'job_01h8x9y2z3a4b5c6d7e8f9g0h1',
                       'User-ID' => 'user-1234', 'Response-Signature' => 'c2ln',
                       'Response-Timestamp' => '2026-07-20T12:00:01.000Z' } }
        end

      result = client.aml.submit_sync(**aml_args, user_id: 'user-1234',
                                                  idempotency_key: 'kuda-onboarding-8f14e45fceea167a',
                                                  callback_url: 'https://example.com/cb')

      expect(captured.headers['Smileid-Idempotency-Key']).to eq('kuda-onboarding-8f14e45fceea167a')
      expect(captured.headers['Smileid-Token']).to eq(jwt)
      body = captured.body.dup.force_encoding('UTF-8')
      expect(body).to include("name=\"countries\"\r\nContent-Type: application/json\r\n\r\n" \
                              "[\"NG\"]\r\n")
      expect(body).to include("name=\"callback_url\"\r\n\r\nhttps://example.com/cb\r\n")
      expect(result.status).to eq('attention')
      expect(result.reason).to eq('aml_match_found')
      expect(result.no_of_persons_found).to eq(1)
      expect(result.people.first['name']).to eq('Gbenga Afolabi')
      expect(result.user_provided_info['given_names']).to eq('John')
      expect(result.job_id).to eq('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
      expect(result.user_id).to eq('user-1234')
      expect(result.response_signature).to eq('c2ln')
      expect(result.response_timestamp).to eq('2026-07-20T12:00:01.000Z')
    end

    it 'sends no idempotency key or callback_url when none is given' do
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/aml/sync")
        .to_return do |request|
          captured = request
          { status: 200, body: result_body, headers: { 'Content-Type' => 'application/json' } }
        end

      client.aml.submit_sync(**aml_args)
      expect(captured.headers).not_to have_key('Smileid-Idempotency-Key')
      expect(captured.body.dup.force_encoding('UTF-8')).not_to include('name="callback_url"')
    end

    it 'raises a SmileIDError with status 408 on a provider timeout, without retrying' do
      stub = stub_request(:post, "#{TestHelpers::SANDBOX}/v3/aml/sync")
             .to_return(status: 408,
                        body: JSON.generate(status: 'Request Timeout', message: 'Provider timed out.'),
                        headers: { 'Content-Type' => 'application/json' })

      expect { client.aml.submit_sync(**aml_args) }
        .to raise_error(SmileID::Errors::SmileIDError) { |error|
          expect(error.status_code).to eq(408)
          expect(error.message).to eq('Provider timed out.')
        }
      expect(stub).to have_been_requested.once
    end

    it 'rejects a non-https callback URL before sending' do
      expect { client.aml.submit_sync(**aml_args, callback_url: 'http://example.com/cb') }
        .to raise_error(SmileID::Errors::ValidationError)
    end
  end

  describe 'aml_monitoring.submit' do
    it 'sends the golden multipart shape and binds the token to the aml product' do
      captured = nil
      token_stub = stub_request(:post, "#{TestHelpers::SANDBOX}/v3/token")
                   .with { |request| request.body.include?("\r\n\r\naml\r\n") }
                   .to_return(status: 200, body: JSON.generate(token: jwt),
                              headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/aml/monitoring")
        .to_return do |request|
          captured = request
          { status: 202, body: accepted_body(status: 'accepted'),
            headers: { 'Content-Type' => 'application/json' } }
        end

      response = client.aml_monitoring.submit(
        countries: %w[NG GH], full_name: 'Jane Doe', aliases: ['J. Doe'],
        callback_url: 'https://example.com/cb', **entry_args
      )

      expect(token_stub).to have_been_requested
      expect(captured.headers['Smileid-Token']).to eq(jwt)
      expect(captured.headers['Smileid-Partner-Id']).to be_nil
      body = captured.body.dup.force_encoding('UTF-8')
      expect(body).to include("name=\"countries\"\r\nContent-Type: application/json\r\n\r\n" \
                              "[\"NG\",\"GH\"]\r\n")
      expect(body).to include("name=\"aliases\"\r\nContent-Type: application/json\r\n\r\n" \
                              "[\"J. Doe\"]\r\n")
      expect(body).to include("name=\"full_name\"\r\n\r\nJane Doe\r\n")
      expect(body).to include("name=\"callback_url\"\r\n\r\nhttps://example.com/cb\r\n")
      expect(body).to include("name=\"consent\"\r\nContent-Type: application/json\r\n\r\n")
      expect(response.job_id).to eq('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
      expect(response.accepted?).to be(true)
    end

    it 'omits full_name when reusing an existing user' do
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/aml/monitoring")
        .to_return do |request|
          captured = request
          { status: 202, body: accepted_body, headers: { 'Content-Type' => 'application/json' } }
        end

      client.aml_monitoring.submit(countries: ['NG'], search_existing_user: true, user_id: 'user-1234',
                                   callback_url: 'https://example.com/cb', **entry_args)
      body = captured.body.dup.force_encoding('UTF-8')
      expect(body).not_to include('name="full_name"')
      expect(body).to include("name=\"search_existing_user\"\r\n\r\ntrue\r\n")
      expect(captured.headers['User-Id']).to eq('user-1234')
    end
  end

  describe 'aml_monitoring.news' do
    let(:news_body) do
      JSON.generate(
        job_id: 'a1b2c3d4e5', product: 'aml_monitoring_news', user_id: 'user_123',
        meta: { current_page: 1, limit: 25, total_count: 1 },
        news: [{ body: 'Sample adverse-media content.', published_date: '2023-01-01',
                 publisher: 'Publisher 1', publisher_country_code: 'NG',
                 title: 'Sample AML Monitoring News Item', url: 'www.example.com/article1' }]
      )
    end

    it 'routes the path and query, sends the token and parses the articles' do
      stub = stub_request(:get, "#{TestHelpers::SANDBOX}/v3/aml/monitoring/a1b2c3d4e5/news/ref%20001")
             .with(query: { 'news_category' => 'financial_crime', 'page' => '2', 'limit' => '10' },
                   headers: { 'SmileID-Token' => jwt })
             .to_return(status: 200, body: news_body, headers: { 'Content-Type' => 'application/json' })

      response = client.aml_monitoring.news('a1b2c3d4e5', 'ref 001',
                                            news_category: 'financial_crime', page: 2, limit: 10)

      expect(stub).to have_been_requested
      expect(response.job_id).to eq('a1b2c3d4e5')
      expect(response.product).to eq('aml_monitoring_news')
      expect(response.meta).to eq('current_page' => 1, 'limit' => 25, 'total_count' => 1)
      item = response.news.first
      expect(item).to be_a(SmileID::Generated::Models::AmlMonitoringNewsItem)
      expect([item.title, item.publisher, item.publisher_country_code, item.published_date, item.url])
        .to eq(['Sample AML Monitoring News Item', 'Publisher 1', 'NG', '2023-01-01',
                'www.example.com/article1'])
      expect(item.body).to eq('Sample adverse-media content.')
    end

    it 'omits page and limit when not given' do
      stub = stub_request(:get, "#{TestHelpers::SANDBOX}/v3/aml/monitoring/a1b2c3d4e5/news/ref_001")
             .with(query: { 'news_category' => 'terrorism' })
             .to_return(status: 200, body: JSON.generate(job_id: 'a1b2c3d4e5'),
                        headers: { 'Content-Type' => 'application/json' })

      response = client.aml_monitoring.news('a1b2c3d4e5', 'ref_001', news_category: 'terrorism')
      expect(stub).to have_been_requested
      expect(response.news).to eq([])
    end

    it 'rejects an unknown news category before sending' do
      expect { client.aml_monitoring.news('a1b2c3d4e5', 'ref_001', news_category: 'gossip') }
        .to raise_error(SmileID::Errors::ValidationError, /news_category must be one of/)
    end

    it 'raises NotFoundError for an unknown reference' do
      stub_request(:get, "#{TestHelpers::SANDBOX}/v3/aml/monitoring/a1b2c3d4e5/news/nope")
        .with(query: { 'news_category' => 'other' })
        .to_return(status: 404,
                   body: JSON.generate(status: 'Not Found', message: 'REF not found for this AML job'),
                   headers: { 'Content-Type' => 'application/json' })

      expect { client.aml_monitoring.news('a1b2c3d4e5', 'nope', news_category: 'other') }
        .to raise_error(SmileID::Errors::NotFoundError, 'REF not found for this AML job')
    end
  end

  describe 'base_url override (spec 2.1)' do
    it 'wins over environment' do
      override = build_client(base_url: 'https://api.smileidentity.com', environment: :sandbox)
      stub_token(host: TestHelpers::PRODUCTION)
      stub = stub_request(:get, "#{TestHelpers::PRODUCTION}/v3/status/job_01h8x9y2z3a4b5c6d7e8f9g0h1")
             .to_return(status: 200,
                        body: JSON.generate(status: 'clear', message: 'Job completed',
                                            job_id: 'job_01h8x9y2z3a4b5c6d7e8f9g0h1'),
                        headers: { 'Content-Type' => 'application/json' })

      override.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
      expect(stub).to have_been_requested
    end
  end
end
