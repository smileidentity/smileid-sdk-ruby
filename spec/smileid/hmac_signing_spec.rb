# frozen_string_literal: true

require 'spec_helper'
require 'openssl'

# HMAC request signing (spec section 2.5): wired but OFF unless partner_secret
# is configured. The construction is provisional.
RSpec.describe 'HMAC request signing' do
  it 'sends no signing headers when partner_secret is unset' do
    client = build_client
    stub_token
    captured = nil
    stub_request(:post, "#{TestHelpers::SANDBOX}/v3/enhanced_kyc")
      .to_return do |request|
        captured = request
        { status: 202, body: accepted_body, headers: { 'Content-Type' => 'application/json' } }
      end

    client.enhanced_kyc.verify(country: 'NG', id_type: 'NIN', id_number: '1',
                               user_details: valid_user_details, consent: valid_consent)

    expect(captured.headers['Smileid-Timestamp']).to be_nil
    expect(captured.headers['Smileid-Request-Signature']).to be_nil
  end

  it 'signs the exact serialized body bytes when partner_secret is set' do
    client = build_client(partner_secret: 'shh-secret')
    stub_token
    captured = nil
    stub_request(:post, "#{TestHelpers::SANDBOX}/v3/enhanced_kyc")
      .to_return do |request|
        captured = request
        { status: 202, body: accepted_body, headers: { 'Content-Type' => 'application/json' } }
      end

    client.enhanced_kyc.verify(country: 'NG', id_type: 'NIN', id_number: '1',
                               user_details: valid_user_details, consent: valid_consent)

    timestamp = captured.headers['Smileid-Timestamp']
    signature = captured.headers['Smileid-Request-Signature']
    expect(timestamp).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/)

    expected = OpenSSL::HMAC.hexdigest('SHA256', 'shh-secret', timestamp + captured.body)
    expect(signature).to eq(expected)
  end

  it 'signs the timestamp alone on bodyless requests' do
    client = build_client(partner_secret: 'shh-secret')
    stub_token
    captured = nil
    stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/job_01h8x9y2z3a4b5c6d7e8f9g0h1")
      .to_return do |request|
        captured = request
        { status: 200,
          body: JSON.generate(status: 'complete', job_id: 'job_01h8x9y2z3a4b5c6d7e8f9g0h1'),
          headers: { 'Content-Type' => 'application/json' } }
      end

    client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1')

    timestamp = captured.headers['Smileid-Timestamp']
    expected = OpenSSL::HMAC.hexdigest('SHA256', 'shh-secret', timestamp.to_s)
    expect(captured.headers['Smileid-Request-Signature']).to eq(expected)
  end
end
