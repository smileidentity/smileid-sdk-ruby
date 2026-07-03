# frozen_string_literal: true

require 'usesmileid'
require 'webmock/rspec'
require 'json'
require 'base64'

# Shared helpers for building clients, tokens, and valid request fixtures.
module TestHelpers
  SANDBOX = 'https://testapi.smileidentity.com'
  PRODUCTION = 'https://api.smileidentity.com'

  # Build a JWT with the given exp claim. The signature is a placeholder — the
  # SDK never verifies it, it only decodes the exp claim.
  def make_jwt(exp: (Time.now + 3600).to_i)
    header = base64url(JSON.generate(alg: 'HS256', typ: 'JWT'))
    payload = base64url(JSON.generate(exp: exp))
    "#{header}.#{payload}.signature"
  end

  def base64url(str)
    Base64.urlsafe_encode64(str).delete('=')
  end

  def stub_token(jwt = make_jwt, host: SANDBOX)
    stub_request(:post, "#{host}/v3/token")
      .to_return(status: 200, body: JSON.generate(token: jwt),
                 headers: { 'Content-Type' => 'application/json' })
  end

  def build_client(**opts)
    SmileID::Client.new(partner_id: '1234', api_key: 'test-api-key', **opts)
  end

  def valid_user_details
    { given_names: 'John', last_name: 'Doe', email: 'john@example.com' }
  end

  def valid_consent
    SmileID::Consent.granted(
      granted_at: Time.utc(2026, 3, 6, 12, 0, 0),
      notice_language: 'EN',
      notice_privacy_policy_url: 'https://example.com/privacy'
    )
  end

  def accepted_body(status: 'Accepted')
    JSON.generate(
      status: status,
      message: 'Request accepted and queued for processing.',
      job_id: 'job_01h8x9y2z3a4b5c6d7e8f9g0h1',
      user_id: 'user_01h8x9y2z3a4b5c6d7e8f9g0h1'
    )
  end
end

RSpec.configure do |config|
  config.include TestHelpers

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
