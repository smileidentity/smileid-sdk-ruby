# frozen_string_literal: true

require 'spec_helper'

# Matrix item 8: end-to-end sandbox test (spec section 11, gate item 5).
#
# Reads SMILE_PARTNER_ID and SMILE_API_KEY from the environment and skips
# cleanly when either is unset. Runs a real Enhanced KYC submission against the
# sandbox, then polls with wait_until_complete. Credentials are never printed.
RSpec.describe 'sandbox Enhanced KYC end to end', :e2e do
  let(:partner_id) { ENV.fetch('SMILE_PARTNER_ID', nil) }
  let(:api_key) { ENV.fetch('SMILE_API_KEY', nil) }

  before do
    skip 'SMILE_PARTNER_ID and SMILE_API_KEY are not set' if partner_id.nil? || api_key.nil?
    WebMock.allow_net_connect!
  end

  after { WebMock.disable_net_connect! }

  it 'submits an Enhanced KYC job and observes it reach a terminal state' do
    client = SmileID::Client.new(
      partner_id: partner_id, api_key: api_key, environment: :sandbox
    )

    accepted = client.enhanced_kyc.verify(
      country: 'NG',
      id_type: 'NIN',
      id_number: '12345678901',
      # The sandbox only accepts recognized test identities, matched on
      # given_names + last_name + email.
      user_details: { given_names: 'Amina Fatou', last_name: 'Clearwater',
                      email: 'amina.clearwater@example.com' },
      consent: SmileID::Consent.granted(
        granted_at: Time.now.utc,
        notice_language: 'EN',
        notice_privacy_policy_url: 'https://example.com/privacy'
      )
    )

    expect(accepted.accepted?).to be(true)
    expect(accepted.job_id).to start_with('job_')

    status = client.verifications.wait_until_complete(accepted.job_id, interval: 2, timeout: 120)
    expect(status.complete?).to be(true)
  end
end
