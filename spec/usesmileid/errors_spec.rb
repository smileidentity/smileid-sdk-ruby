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

  describe 'UnexpectedResponseError on malformed 2xx bodies (fleet standard)' do
    it 'raises when a 2xx success body is not a JSON object' do
      stub_token
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/enhanced_kyc")
        .to_return(status: 202, body: '<html>proxy interference</html>',
                   headers: { 'Content-Type' => 'text/html' })

      expect do
        client.enhanced_kyc.verify(country: 'NG', id_type: 'NIN', id_number: '1',
                                   user_details: valid_user_details, consent: valid_consent)
      end.to raise_error(SmileID::Errors::UnexpectedResponseError) do |error|
        expect(error.status_code).to eq(202)
        expect(error.raw_body).to eq('<html>proxy interference</html>')
      end
    end

    it 'raises when a 2xx body is a JSON array rather than an object' do
      stub_request(:get, "#{TestHelpers::SANDBOX}/v3/services/bank_codes")
        .to_return(status: 200, body: '[1,2,3]', headers: { 'Content-Type' => 'application/json' })

      expect { client.services.bank_codes }
        .to raise_error(SmileID::Errors::UnexpectedResponseError)
    end

    it 'populates request_id from a response header when present' do
      stub_request(:get, "#{TestHelpers::SANDBOX}/v3/services/bank_codes")
        .to_return(status: 200, body: 'not-json',
                   headers: { 'Content-Type' => 'text/plain', 'X-Request-Id' => 'req-123' })

      expect { client.services.bank_codes }
        .to raise_error(SmileID::Errors::UnexpectedResponseError) do |error|
        expect(error.request_id).to eq('req-123')
      end
    end

    it 'is a SmileIDError subclass' do
      expect(SmileID::Errors::UnexpectedResponseError.ancestors)
        .to include(SmileID::Errors::SmileIDError)
    end
  end

  describe 'job_id from the SmileID-Job-ID header' do
    def error_for(status_code, headers)
      described_class.from_response(status_code: status_code, body: { 'message' => 'x' },
                                    raw_body: '{"message":"x"}', headers: headers)
    end

    it 'sets job_id on a 408 that carries the header' do
      error = error_for(408, 'SmileID-Job-ID' => 'job_408')
      expect(error).to be_a(SmileID::Errors::SmileIDError)
      expect(error.job_id).to eq('job_408')
    end

    it 'leaves job_id nil when the header is absent' do
      expect(error_for(500, 'Content-Type' => 'application/json').job_id).to be_nil
      expect(error_for(500, nil).job_id).to be_nil
    end

    it 'looks the header up ignoring case' do
      expect(error_for(424, 'smileid-job-id' => 'job_lower').job_id).to eq('job_lower')
      expect(error_for(424, 'SMILEID-JOB-ID' => 'job_upper').job_id).to eq('job_upper')
    end

    it 'treats a blank header as absent and strips the value' do
      expect(error_for(408, 'SmileID-Job-ID' => '').job_id).to be_nil
      expect(error_for(408, 'SmileID-Job-ID' => "  \t").job_id).to be_nil
      expect(error_for(408, 'SmileID-Job-ID' => ' job_408 ').job_id).to eq('job_408')
    end

    it 'defaults to nil on a hand-built error' do
      expect(SmileID::Errors::APIError.new('boom').job_id).to be_nil
    end

    it 'is set from the response on an error raised by an API call' do
      stub_token
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/enhanced_kyc")
        .to_return(status: 500, body: '{"status":"Failed","message":"Internal error."}',
                   headers: { 'Content-Type' => 'application/json', 'smileid-job-id' => 'job_500' })

      expect do
        client.enhanced_kyc.verify(country: 'NG', id_type: 'NIN', id_number: '1',
                                   user_details: valid_user_details, consent: valid_consent)
      end.to raise_error(SmileID::Errors::APIError) { |error| expect(error.job_id).to eq('job_500') }
    end

    it 'is set on an UnexpectedResponseError' do
      stub_request(:get, "#{TestHelpers::SANDBOX}/v3/services/bank_codes")
        .to_return(status: 200, body: 'not-json',
                   headers: { 'Content-Type' => 'text/plain', 'SmileID-Job-ID' => 'job_2xx' })

      expect { client.services.bank_codes }
        .to raise_error(SmileID::Errors::UnexpectedResponseError) { |error| expect(error.job_id).to eq('job_2xx') }
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
