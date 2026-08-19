# frozen_string_literal: true

require 'spec_helper'

# Matrix item 2: token lifecycle (spec sections 2.3 and 2A).
RSpec.describe 'token lifecycle' do
  let(:client) { build_client }

  def stub_status(job_id = 'job_01h8x9y2z3a4b5c6d7e8f9g0h1', **overrides)
    stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/#{job_id}")
      .to_return({ status: 200,
                   body: JSON.generate(status: 'clear', job_id: job_id, message: 'Job completed'),
                   headers: { 'Content-Type' => 'application/json' } }.merge(overrides))
  end

  it 'sends partner credentials as headers and no body to /v3/token' do
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

  it 'caches the token across calls until exp minus 60s' do
    token_stub = stub_token(make_jwt(exp: (Time.now + 3600).to_i))
    stub_status

    3.times { client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1') }

    expect(token_stub).to have_been_requested.once
  end

  it 'refreshes when the cached token is within the 60s expiry skew' do
    token_stub = stub_token(make_jwt(exp: (Time.now + 30).to_i))
    stub_status

    2.times { client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1') }

    expect(token_stub).to have_been_requested.twice
  end

  it 'treats an undecodable token as single-use' do
    stub = stub_request(:post, "#{TestHelpers::SANDBOX}/v3/token")
           .to_return(status: 200, body: JSON.generate(token: 'not-a-jwt'),
                      headers: { 'Content-Type' => 'application/json' })
    stub_status

    2.times { client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1') }

    expect(stub).to have_been_requested.twice
  end

  it 'refreshes once on a 401 then raises AuthenticationError on a second 401' do
    token_stub = stub_token
    stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/job_01h8x9y2z3a4b5c6d7e8f9g0h1")
      .to_return(status: 401,
                 body: JSON.generate(status: 'Unauthorized', message: 'Token expired'),
                 headers: { 'Content-Type' => 'application/json' })

    expect { client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1') }
      .to raise_error(SmileID::Errors::AuthenticationError, 'Token expired')
    expect(token_stub).to have_been_requested.twice
  end

  it 'recovers when the refreshed token succeeds after a 401' do
    stub_token
    call_count = 0
    stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/job_01h8x9y2z3a4b5c6d7e8f9g0h1")
      .to_return do
        call_count += 1
        if call_count == 1
          { status: 401, body: JSON.generate(status: 'Unauthorized', message: 'expired'),
            headers: { 'Content-Type' => 'application/json' } }
        else
          { status: 200,
            body: JSON.generate(status: 'clear', message: 'Job completed',
                                job_id: 'job_01h8x9y2z3a4b5c6d7e8f9g0h1'),
            headers: { 'Content-Type' => 'application/json' } }
        end
      end

    status = client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1')
    expect(status.complete?).to be(true)
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

  it 'is thread-safe: concurrent calls do not stampede the token endpoint' do
    jwt = make_jwt
    token_calls = 0
    stub_request(:post, "#{TestHelpers::SANDBOX}/v3/token")
      .to_return do
        token_calls += 1
        sleep 0.05
        { status: 200, body: JSON.generate(token: jwt),
          headers: { 'Content-Type' => 'application/json' } }
      end
    stub_status

    threads = Array.new(8) do
      Thread.new { client.verifications.retrieve('job_01h8x9y2z3a4b5c6d7e8f9g0h1') }
    end
    threads.each(&:join)

    expect(token_calls).to eq(1)
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
