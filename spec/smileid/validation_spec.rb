# frozen_string_literal: true

require 'spec_helper'

# Matrix item 6: client-side validation (spec sections 5.1, 6.6, 6.11).
RSpec.describe 'client-side validation' do
  let(:client) { build_client }

  describe 'user_details email-or-phone rule' do
    it 'raises before sending when both email and phone_number are missing' do
      expect do
        client.enhanced_kyc.verify(
          country: 'NG', id_type: 'NIN', id_number: '1',
          user_details: { given_names: 'John', last_name: 'Doe' },
          consent: valid_consent
        )
      end.to raise_error(SmileID::Errors::ValidationError, /email or phone_number/)
      expect(WebMock).not_to have_requested(:any, //)
    end

    it 'accepts phone_number alone in E.164 format' do
      details = SmileID::UserDetails.coerce(
        given_names: 'John', last_name: 'Doe', phone_number: '+2348012345678'
      )
      expect(details).to eq('given_names' => 'John', 'last_name' => 'Doe',
                            'phone_number' => '+2348012345678')
    end

    it 'rejects a phone_number that is not E.164' do
      expect do
        SmileID::UserDetails.coerce(given_names: 'John', last_name: 'Doe', phone_number: '0801234')
      end.to raise_error(SmileID::Errors::ValidationError, /E\.164/)
    end

    it 'requires given_names and last_name' do
      expect { SmileID::UserDetails.coerce(last_name: 'Doe', email: 'john@example.com') }
        .to raise_error(SmileID::Errors::ValidationError, /given_names/)
      expect { SmileID::UserDetails.coerce(given_names: 'John', email: 'john@example.com') }
        .to raise_error(SmileID::Errors::ValidationError, /last_name/)
    end
  end

  describe 'consent builder and validation' do
    it 'builds a granted consent with ISO 8601 millisecond timestamps' do
      consent = SmileID::Consent.granted(
        granted_at: Time.utc(2026, 3, 6, 12, 0, 0),
        notice_language: 'EN', notice_privacy_policy_url: 'https://example.com/privacy'
      )
      expect(consent.to_h).to eq(
        'granted' => true,
        'granted_at' => '2026-03-06T12:00:00.000Z',
        'notice_language' => 'EN',
        'notice_privacy_policy_url' => 'https://example.com/privacy'
      )
    end

    it 'rejects consent where granted is not true' do
      expect do
        SmileID::Consent.coerce(granted: false, granted_at: '2026-03-06T12:00:00.000Z',
                                notice_language: 'EN',
                                notice_privacy_policy_url: 'https://example.com/privacy')
      end.to raise_error(SmileID::Errors::ValidationError, /granted must be true/)
    end

    it 'rejects a lowercase notice_language' do
      expect do
        SmileID::Consent.coerce(granted: true, granted_at: '2026-03-06T12:00:00.000Z',
                                notice_language: 'en',
                                notice_privacy_policy_url: 'https://example.com/privacy')
      end.to raise_error(SmileID::Errors::ValidationError, /notice_language/)
    end
  end

  describe 'report_fraud conditional rules (spec 6.11)' do
    it 'requires reason when is_fraud is true' do
      expect do
        client.users.report_fraud('user-1', is_fraud: true, reported_by: 'risk@example.com')
      end.to raise_error(SmileID::Errors::ValidationError, /reason is required/)
    end

    it 'rejects a reason outside the enum' do
      expect do
        client.users.report_fraud('user-1', is_fraud: true, reason: 'BAD_VIBES',
                                            reported_by: 'risk@example.com')
      end.to raise_error(SmileID::Errors::ValidationError, /reason must be one of/)
    end

    it 'requires notes when reason is OTHER' do
      expect do
        client.users.report_fraud('user-1', is_fraud: true, reason: 'OTHER',
                                            reported_by: 'risk@example.com')
      end.to raise_error(SmileID::Errors::ValidationError, /notes is required when reason is OTHER/)
    end

    it 'requires notes when is_fraud is false' do
      expect do
        client.users.report_fraud('user-1', is_fraud: false, reported_by: 'risk@example.com')
      end.to raise_error(SmileID::Errors::ValidationError, /notes is required when is_fraud is false/)
    end

    it 'flag_fraud wraps report_fraud with is_fraud=true' do
      stub_token
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/users/user-1/report_fraud")
        .to_return do |request|
          captured = request
          { status: 202,
            body: JSON.generate(status: 'accepted', message: 'Fraud report accepted',
                                user_id: 'user-1'),
            headers: { 'Content-Type' => 'application/json' } }
        end

      client.users.flag_fraud('user-1', reason: 'ACCOUNT_TAKEOVER', reported_by: 'risk@example.com')
      expect(captured.body.dup.force_encoding('UTF-8')).to include("name=\"is_fraud\"\r\n\r\ntrue")
    end

    it 'clear_fraud wraps report_fraud with is_fraud=false' do
      stub_token
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/users/user-1/report_fraud")
        .to_return do |request|
          captured = request
          { status: 202,
            body: JSON.generate(status: 'accepted', message: 'Fraud report accepted',
                                user_id: 'user-1'),
            headers: { 'Content-Type' => 'application/json' } }
        end

      client.users.clear_fraud('user-1', notes: 'cleared after review',
                                         reported_by: 'risk@example.com')
      body = captured.body.dup.force_encoding('UTF-8')
      expect(body).to include("name=\"is_fraud\"\r\n\r\nfalse")
      expect(body).to include("name=\"notes\"\r\n\r\ncleared after review")
    end
  end

  describe 'enhanced document verification id_type rule (spec 6.3)' do
    it 'raises before sending when id_type is nil or empty' do
      [nil, ''].each do |id_type|
        expect do
          client.documents.verify_enhanced(
            id_type: id_type, selfie_image: 's', liveness_images: %w[a b c d e f],
            document: 'd', country: 'NG',
            user_details: valid_user_details, consent: valid_consent
          )
        end.to raise_error(SmileID::Errors::ValidationError, /id_type is required/)
      end
      expect(WebMock).not_to have_requested(:any, //)
    end
  end

  describe 'authentication image rule (spec 6.6)' do
    it 'requires images unless use_enrolled_image is true' do
      expect do
        client.biometric.authenticate(user_id: 'user-1', user_details: valid_user_details,
                                      consent: valid_consent)
      end.to raise_error(SmileID::Errors::ValidationError, /selfie_image and liveness_images/)
    end

    it 'allows omitting images when use_enrolled_image is true' do
      stub_token
      captured = nil
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/authentication")
        .to_return do |request|
          captured = request
          { status: 202, body: accepted_body, headers: { 'Content-Type' => 'application/json' } }
        end

      client.biometric.authenticate(
        user_id: 'user-1', use_enrolled_image: true,
        user_details: valid_user_details, consent: valid_consent
      )
      body = captured.body.dup.force_encoding('UTF-8')
      expect(body).to include("name=\"use_enrolled_image\"\r\n\r\ntrue")
      expect(body).not_to include('selfie_image')
    end
  end

  describe 'client configuration (spec 2.1)' do
    it 'rejects a partner_id with leading zeros' do
      expect { SmileID::Client.new(partner_id: '0123', api_key: 'k') }
        .to raise_error(ArgumentError, /partner_id/)
    end

    it 'rejects an unknown environment' do
      expect { SmileID::Client.new(partner_id: '1234', api_key: 'k', environment: :staging) }
        .to raise_error(ArgumentError, /environment/)
    end

    it 'rejects an insecure base_url override' do
      expect { build_client(base_url: 'http://api.example.com') }
        .to raise_error(ArgumentError, /base_url/)
    end

    it 'rejects insecure default and per-request callback URLs' do
      expect { build_client(default_callback_url: 'http://partner.example.com/webhook') }
        .to raise_error(ArgumentError, /default_callback_url/)

      expect do
        client.enhanced_kyc.verify(
          country: 'NG', id_type: 'NIN', id_number: '1',
          user_details: valid_user_details, consent: valid_consent,
          callback_url: 'http://partner.example.com/webhook'
        )
      end.to raise_error(ArgumentError, /callback_url/)
      expect(WebMock).not_to have_requested(:any, //)
    end

    it 'defaults to sandbox' do
      expect(build_client.config.base_url).to eq('https://testapi.smileidentity.com')
    end

    it 'selects the production base URL' do
      client = build_client(environment: :production)
      expect(client.config.base_url).to eq('https://api.smileidentity.com')
    end
  end

  describe 'successful response parsing' do
    it 'raises a typed error for malformed JSON on a success status' do
      stub_token
      stub_request(:post, "#{TestHelpers::SANDBOX}/v3/enhanced_kyc")
        .to_return(status: 202, body: '<html>not json</html>',
                   headers: { 'X-Request-ID' => 'req_123' })

      expect do
        client.enhanced_kyc.verify(
          country: 'NG', id_type: 'NIN', id_number: '1',
          user_details: valid_user_details, consent: valid_consent
        )
      end.to raise_error(SmileID::Errors::UnexpectedResponseError) { |error|
        expect(error.status_code).to eq(202)
        expect(error.request_id).to eq('req_123')
        expect(error.raw_body).to eq('<html>not json</html>')
      }
    end
  end
end
