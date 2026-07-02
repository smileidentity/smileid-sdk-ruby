# frozen_string_literal: true

require 'spec_helper'

# Matrix items 4 and 5: error hierarchy over both wire shapes, plus
# AcceptedResponse status normalization (spec sections 5.2 and 7).
RSpec.describe SmileID::Errors do
  let(:client) { build_client }

  describe 'class selection by HTTP status' do
    {
      400 => SmileID::Errors::InvalidRequestError,
      401 => SmileID::Errors::AuthenticationError,
      402 => SmileID::Errors::PaymentRequiredError,
      403 => SmileID::Errors::PermissionError,
      404 => SmileID::Errors::NotFoundError,
      409 => SmileID::Errors::ConflictError,
      413 => SmileID::Errors::PayloadTooLargeError,
      415 => SmileID::Errors::InvalidRequestError,
      429 => SmileID::Errors::RateLimitError,
      500 => SmileID::Errors::APIError,
      502 => SmileID::Errors::APIError,
      503 => SmileID::Errors::APIError
    }.each do |status, klass|
      it "maps #{status} to #{klass.name.split('::').last}" do
        expect(described_class.class_for(status)).to eq(klass)
      end
    end
  end

  describe 'the {status, message} wire shape' do
    it 'raises InvalidRequestError with all accessors populated (golden 400)' do
      stub_token
      raw = '{"status":"Bad Request","message":"Either email or phone_number is required."}'
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/enhanced_kyc")
        .to_return(status: 400, body: raw, headers: { 'Content-Type' => 'application/json' })

      expect do
        client.enhanced_kyc.verify(country: 'NG', id_type: 'NIN', id_number: '1',
                                   user_details: valid_user_details, consent: valid_consent)
      end.to raise_error(SmileID::Errors::InvalidRequestError) do |error|
        expect(error.status_code).to eq(400)
        expect(error.status).to eq('Bad Request')
        expect(error.message).to eq('Either email or phone_number is required.')
        expect(error.code).to be_nil
        expect(error.raw_body).to eq(raw)
      end
    end

    it 'raises PaymentRequiredError for the golden 402' do
      stub_token
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/enhanced_kyc")
        .to_return(status: 402,
                   body: '{"status":"Payment Required","message":"Insufficient wallet balance."}',
                   headers: { 'Content-Type' => 'application/json' })

      expect do
        client.enhanced_kyc.verify(country: 'NG', id_type: 'NIN', id_number: '1',
                                   user_details: valid_user_details, consent: valid_consent)
      end.to raise_error(SmileID::Errors::PaymentRequiredError, 'Insufficient wallet balance.')
    end

    it 'raises PayloadTooLargeError for the golden 413' do
      stub_token
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/document_verification")
        .to_return(status: 413,
                   body: '{"status":"Content Too Large","message":"selfie_image is too large."}',
                   headers: { 'Content-Type' => 'application/json' })

      expect do
        client.documents.verify(selfie_image: 's', liveness_images: %w[a b c d e f],
                                document: 'd', country: 'NG',
                                user_details: valid_user_details, consent: valid_consent)
      end.to raise_error(SmileID::Errors::PayloadTooLargeError, 'selfie_image is too large.')
    end

    it 'handles the id_status {message, status} key ordering' do
      stub_token
      stub_request(:get, "#{TestHelpers::SANDBOX}/v3/services/id_status")
        .with(query: { 'country' => 'NG', 'id_type' => 'BVN' })
        .to_return(status: 400,
                   body: '{"message":"\"country\" is required","status":"Bad Request"}',
                   headers: { 'Content-Type' => 'application/json' })

      expect { client.services.id_status(country: 'NG', id_type: 'BVN') }
        .to raise_error(SmileID::Errors::InvalidRequestError) do |error|
        expect(error.message).to eq('"country" is required')
        expect(error.status).to eq('Bad Request')
      end
    end
  end

  describe 'the {error, code} wire shape (services)' do
    it 'raises PermissionError with code populated for the golden 403' do
      raw = '{"error":"You are not authorized to do that.","code":"2413"}'
      stub_request(:get, "#{TestHelpers::SANDBOX}/v3/services/bank_codes")
        .to_return(status: 403, body: raw, headers: { 'Content-Type' => 'application/json' })

      expect { client.services.bank_codes }
        .to raise_error(SmileID::Errors::PermissionError) do |error|
        expect(error.status_code).to eq(403)
        expect(error.message).to eq('You are not authorized to do that.')
        expect(error.code).to eq('2413')
        expect(error.status).to be_nil
        expect(error.raw_body).to eq(raw)
      end
    end
  end

  describe 'non-JSON error bodies' do
    it 'still raises the status-typed error with the raw body attached' do
      stub_request(:get, "#{TestHelpers::SANDBOX}/v3/services/bank_codes")
        .to_return(status: 500, body: '<html>gateway error</html>')

      expect { client.services.bank_codes }
        .to raise_error(SmileID::Errors::APIError) do |error|
        expect(error.status_code).to eq(500)
        expect(error.raw_body).to eq('<html>gateway error</html>')
      end
    end
  end

  describe 'jobs.retrieve 404 handling (spec 6.8)' do
    it 'returns a not_found JobStatus instead of raising NotFoundError' do
      stub_token
      stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/job_01h8x9y2z3a4b5c6d7e8f9g0h1")
        .to_return(status: 404,
                   body: JSON.generate(status: 'not_found',
                                       job_id: 'job_01h8x9y2z3a4b5c6d7e8f9g0h1',
                                       user_id: 'unknown', message: 'Verification not found'),
                   headers: { 'Content-Type' => 'application/json' })

      status = client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
      expect(status.not_found?).to be(true)
      expect(status.user_id).to eq('unknown')
    end
  end

  describe 'AcceptedResponse status normalization (matrix item 5)' do
    it 'normalizes uppercase Accepted' do
      response = SmileID::Generated::Models::AcceptedResponse.from(
        'status' => 'Accepted', 'message' => 'ok', 'job_id' => 'job_x', 'user_id' => 'user_x'
      )
      expect(response.accepted?).to be(true)
    end

    it 'normalizes lowercase accepted' do
      response = SmileID::Generated::Models::AcceptedResponse.from(
        'status' => 'accepted', 'message' => 'ok', 'job_id' => 'job_x', 'user_id' => 'user_x'
      )
      expect(response.accepted?).to be(true)
    end

    it 'is false for other statuses' do
      response = SmileID::Generated::Models::AcceptedResponse.from('status' => 'rejected')
      expect(response.accepted?).to be(false)
    end

    it 'exposes created_at when present (document_verification shape)' do
      response = SmileID::Generated::Models::AcceptedResponse.from(
        'status' => 'accepted', 'created_at' => '2026-03-10T12:00:00.000Z'
      )
      expect(response.created_at).to eq('2026-03-10T12:00:00.000Z')
    end
  end
end
