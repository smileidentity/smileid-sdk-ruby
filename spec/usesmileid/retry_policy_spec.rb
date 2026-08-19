# frozen_string_literal: true

require 'spec_helper'

# Matrix item 3: retry policy (spec section 2.6).
RSpec.describe 'retry policy' do
  let(:client) { build_client }

  before do
    # Backoff sleeps are stubbed out to keep the suite fast.
    allow_any_instance_of(SmileID::Transport).to receive(:sleep_for)
  end

  def stub_status_sequence(*responses)
    stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/job_01h8x9y2z3a4b5c6d7e8f9g0h1")
      .to_return(*responses)
  end

  def complete_response
    { status: 200,
      body: JSON.generate(status: 'clear', message: 'Job completed',
                          job_id: 'job_01h8x9y2z3a4b5c6d7e8f9g0h1'),
      headers: { 'Content-Type' => 'application/json' } }
  end

  def error_response(status)
    { status: status, body: JSON.generate(status: 'Error', message: 'transient'),
      headers: { 'Content-Type' => 'application/json' } }
  end

  it 'retries GET /v3/status on 5xx up to max_retries then succeeds' do
    stub_token
    stub = stub_status_sequence(error_response(503), error_response(502), complete_response)

    status = client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
    expect(status.complete?).to be(true)
    expect(stub).to have_been_requested.times(3)
  end

  it 'retries on 408 and 429' do
    stub_token
    stub = stub_status_sequence(error_response(408), error_response(429), complete_response)

    client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
    expect(stub).to have_been_requested.times(3)
  end

  it 'gives up after max_retries and raises the typed error' do
    stub_token
    stub = stub_status_sequence(error_response(503), error_response(503), error_response(503))

    expect { client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1') }
      .to raise_error(SmileID::Errors::APIError)
    expect(stub).to have_been_requested.times(3)
  end

  it 'honours the Retry-After header when present' do
    stub_token
    slept = []
    transport = client.instance_variable_get(:@transport)
    allow(transport).to receive(:sleep_for) { |seconds| slept << seconds }

    stub_status_sequence(
      error_response(429).merge(headers: { 'Content-Type' => 'application/json',
                                           'Retry-After' => '7' }),
      complete_response
    )

    client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
    expect(slept).to eq([7.0])
  end

  it 'honours the Retry-After HTTP-date form' do
    stub_token
    slept = []
    transport = client.instance_variable_get(:@transport)
    allow(transport).to receive(:sleep_for) { |seconds| slept << seconds }

    stub_status_sequence(
      error_response(503).merge(headers: { 'Content-Type' => 'application/json',
                                           'Retry-After' => (Time.now + 10).httpdate }),
      complete_response
    )

    client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
    expect(slept.length).to eq(1)
    expect(slept.first).to be_between(8, 10)
  end

  it 'floors a past Retry-After HTTP-date at zero' do
    stub_token
    slept = []
    transport = client.instance_variable_get(:@transport)
    allow(transport).to receive(:sleep_for) { |seconds| slept << seconds }

    stub_status_sequence(
      error_response(503).merge(headers: { 'Content-Type' => 'application/json',
                                           'Retry-After' => (Time.now - 60).httpdate }),
      complete_response
    )

    client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
    expect(slept).to eq([0])
  end

  it 'caps an honoured Retry-After at 60 seconds' do
    stub_token
    slept = []
    transport = client.instance_variable_get(:@transport)
    allow(transport).to receive(:sleep_for) { |seconds| slept << seconds }

    stub_status_sequence(
      error_response(429).merge(headers: { 'Content-Type' => 'application/json',
                                           'Retry-After' => '3600' }),
      complete_response
    )

    client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
    expect(slept).to eq([60])
  end

  it 'falls back to exponential backoff on an unparseable Retry-After' do
    stub_token
    slept = []
    transport = client.instance_variable_get(:@transport)
    allow(transport).to receive(:sleep_for) { |seconds| slept << seconds }

    stub_status_sequence(
      error_response(503).merge(headers: { 'Content-Type' => 'application/json',
                                           'Retry-After' => 'soonish' }),
      complete_response
    )

    client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
    expect(slept.length).to eq(1)
    expect(slept.first).to be_between(0.5, 1.0)
  end

  it 'retries connection errors on idempotent operations' do
    stub_token
    stub = stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/job_01h8x9y2z3a4b5c6d7e8f9g0h1")
           .to_raise(Errno::ECONNREFUSED).then
           .to_return(complete_response)

    status = client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
    expect(status.complete?).to be(true)
    expect(stub).to have_been_requested.times(2)
  end

  it 'retries the token fetch itself' do
    token_stub = stub_request(:post, "#{TestHelpers::SANDBOX}/v3/token")
                 .to_return(error_response(500),
                            { status: 200, body: JSON.generate(token: make_jwt),
                              headers: { 'Content-Type' => 'application/json' } })
    stub_status_sequence(complete_response)

    client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
    expect(token_stub).to have_been_requested.times(2)
  end

  it 'never retries entry POSTs on 5xx' do
    stub_token
    stub = stub_request(:post, "#{TestHelpers::SANDBOX}/v3/enhanced_kyc")
           .to_return(error_response(503))

    expect do
      client.enhanced_kyc.verify(
        country: 'NG', id_type: 'NIN', id_number: '1',
        user_details: valid_user_details, consent: valid_consent
      )
    end.to raise_error(SmileID::Errors::APIError)
    expect(stub).to have_been_requested.once
  end

  it 'surfaces connection errors on entry POSTs as ConnectionError without retrying' do
    stub_token
    stub = stub_request(:post, "#{TestHelpers::SANDBOX}/v3/enhanced_kyc")
           .to_raise(Errno::ECONNREFUSED)

    expect do
      client.enhanced_kyc.verify(
        country: 'NG', id_type: 'NIN', id_number: '1',
        user_details: valid_user_details, consent: valid_consent
      )
    end.to raise_error(SmileID::Errors::ConnectionError)
    expect(stub).to have_been_requested.once
  end

  # Faraday::SSLError is a sibling of ConnectionFailed, not a subclass, so a
  # dropped TLS socket escapes unwrapped unless it is rescued by name.
  it 'wraps a TLS failure as ConnectionError' do
    stub_token
    stub_request(:post, "#{TestHelpers::SANDBOX}/v3/enhanced_kyc")
      .to_raise(Faraday::SSLError.new('SSL_connect returned=1 errno=0'))

    expect do
      client.enhanced_kyc.verify(
        country: 'NG', id_type: 'NIN', id_number: '1',
        user_details: valid_user_details, consent: valid_consent
      )
    end.to raise_error(SmileID::Errors::ConnectionError, /SSL_connect/)
  end

  it 'never retries replay, even though 409 is conflict-shaped' do
    stub_token
    stub = stub_request(:post, "#{TestHelpers::SANDBOX}/v3/replay/job_01h8x9y2z3a4b5c6d7e8f9g0h1")
           .to_return(status: 409,
                      body: JSON.generate(status: 'Conflict',
                                          message: 'Verification is still processing.'),
                      headers: { 'Content-Type' => 'application/json' })

    expect { client.verifications.replay('job_01h8x9y2z3a4b5c6d7e8f9g0h1') }
      .to raise_error(SmileID::Errors::ConflictError)
    expect(stub).to have_been_requested.once
  end

  it 'does not retry 409 even on idempotent operations' do
    transport = SmileID::Transport.new(client.config)
    stub = stub_request(:get, "#{TestHelpers::SANDBOX}/v3/services/bank_codes")
           .to_return(status: 409, body: JSON.generate(status: 'Conflict', message: 'conflict'),
                      headers: { 'Content-Type' => 'application/json' })

    response = transport.send_request(
      method: :get, url: "#{TestHelpers::SANDBOX}/v3/services/bank_codes",
      headers: {}, retryable: true
    )
    expect(response.status).to eq(409)
    expect(stub).to have_been_requested.once
  end

  it 'never retries report_fraud' do
    stub_token
    stub = stub_request(:post, "#{TestHelpers::SANDBOX}/v3/users/user-1/report_fraud")
           .to_return(error_response(500))

    expect do
      client.users.report_fraud('user-1', is_fraud: false, notes: 'cleared after review',
                                          reported_by: 'risk@example.com')
    end.to raise_error(SmileID::Errors::APIError)
    expect(stub).to have_been_requested.once
  end
end
