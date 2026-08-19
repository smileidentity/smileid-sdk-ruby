# frozen_string_literal: true

require 'spec_helper'

# Matrix item 7: wait_until_complete polling helper (spec section 6.9).
RSpec.describe 'verifications.wait_until_complete' do
  let(:client) { build_client }
  let(:job_id) { 'job_01h8x9y2z3a4b5c6d7e8f9g0h1' }
  let(:verifications) { client.verifications }

  before do
    stub_token
    allow(verifications).to receive(:sleep_interval)
  end

  # The wire returns the decision itself as `status`; only `processing` and
  # `not_found` are non-terminal.
  def job_body(status, message = 'Job completed')
    { status: (status == 'processing' ? 202 : 200),
      body: JSON.generate(status: status, job_id: job_id, message: message),
      headers: { 'Content-Type' => 'application/json' } }
  end

  def not_found_body
    { status: 404,
      body: JSON.generate(status: 'not_found', job_id: job_id, user_id: 'unknown',
                          message: 'Verification not found'),
      headers: { 'Content-Type' => 'application/json' } }
  end

  it 'polls until the job reaches a clear decision' do
    stub = stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/#{job_id}")
           .to_return(job_body('processing'), job_body('processing'), job_body('clear'))

    status = verifications.wait_until_complete(job_id)
    expect(status.complete?).to be(true)
    expect(status.status).to eq('clear')
    expect(status.message).to eq('Job completed')
    expect(stub).to have_been_requested.times(3)
  end

  it 'returns on a block decision too' do
    stub = stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/#{job_id}")
           .to_return(job_body('processing'), job_body('block'))

    status = verifications.wait_until_complete(job_id)
    expect(status.complete?).to be(true)
    expect(status.status).to eq('block')
    expect(stub).to have_been_requested.times(2)
  end

  it 'keeps polling while the job is processing' do
    stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/#{job_id}")
      .to_return(job_body('processing'), job_body('processing'), job_body('attention'))

    status = verifications.wait_until_complete(job_id)
    expect(status.status).to eq('attention')
    expect(verifications).to have_received(:sleep_interval).twice
  end

  it 'sleeps for the configured interval between polls' do
    stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/#{job_id}")
      .to_return(job_body('processing'), job_body('clear'))

    verifications.wait_until_complete(job_id, interval: 5)
    expect(verifications).to have_received(:sleep_interval).with(5).once
  end

  it 'treats not_found as pending by default' do
    stub = stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/#{job_id}")
           .to_return(not_found_body, job_body('clear'))

    status = verifications.wait_until_complete(job_id)
    expect(status.complete?).to be(true)
    expect(stub).to have_been_requested.times(2)
  end

  it 'returns not_found immediately when treat_not_found_as_pending is false' do
    stub = stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/#{job_id}")
           .to_return(not_found_body)

    status = verifications.wait_until_complete(job_id, treat_not_found_as_pending: false)
    expect(status.not_found?).to be(true)
    expect(stub).to have_been_requested.once
  end

  it 'raises TimeoutError when the deadline passes' do
    stub_request(:get, "#{TestHelpers::SANDBOX}/v3/status/#{job_id}")
      .to_return(job_body('processing'))

    fake_clock = 0.0
    allow(verifications).to receive(:monotonic) { fake_clock += 10 }

    expect { verifications.wait_until_complete(job_id, timeout: 15) }
      .to raise_error(SmileID::Errors::TimeoutError, /timed out after 15s/)
  end
end
