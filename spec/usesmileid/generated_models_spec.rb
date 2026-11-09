# frozen_string_literal: true

require 'spec_helper'

# Wire response models in lib/usesmileid/generated/models.rb.
RSpec.describe SmileID::Generated::Models do
  describe SmileID::Generated::Models::JobStatus do
    def status_of(value)
      described_class.from('status' => value, 'job_id' => 'job_1')
    end

    it 'is complete for each terminal decision' do
      %w[clear block attention error].each do |decision|
        status = status_of(decision)
        expect([status.complete?, status.processing?, status.not_found?]).to eq([true, false, false])
      end
    end

    it 'is not complete while processing' do
      status = status_of('processing')
      expect([status.complete?, status.processing?, status.not_found?]).to eq([false, true, false])
    end

    it 'is not complete when the job is not found' do
      status = status_of('not_found')
      expect([status.complete?, status.processing?, status.not_found?]).to eq([false, false, true])
    end

    it 'is not complete when the status is missing or empty' do
      expect(status_of(nil).complete?).to be(false)
      expect(status_of('').complete?).to be(false)
    end

    it 'keeps every wire field and the raw hash' do
      hash = { 'status' => 'clear', 'job_id' => 'job_1', 'user_id' => 'user_1', 'message' => 'done' }
      status = described_class.from(hash)
      expect([status.status, status.job_id, status.user_id, status.message, status.raw])
        .to eq(['clear', 'job_1', 'user_1', 'done', hash])
    end
  end

  describe SmileID::Generated::Models::AcceptedResponse do
    it 'reads every wire field and treats any casing of accepted as accepted' do
      hash = { 'status' => 'Accepted', 'message' => 'queued', 'job_id' => 'job_1',
               'user_id' => 'user_1', 'created_at' => '2026-01-01T00:00:00Z' }
      response = described_class.from(hash)
      expect([response.status, response.message, response.job_id, response.user_id,
              response.created_at, response.raw])
        .to eq(['Accepted', 'queued', 'job_1', 'user_1', '2026-01-01T00:00:00Z', hash])
      expect(response.accepted?).to be(true)
      expect(described_class.from('status' => 'accepted').accepted?).to be(true)
      expect(described_class.from('status' => 'rejected').accepted?).to be(false)
    end
  end

  describe SmileID::Generated::Models::AcceptedStatusResponse do
    it 'reads every wire field and treats any casing of accepted as accepted' do
      hash = { 'status' => 'ACCEPTED', 'message' => 'queued', 'job_id' => 'job_1', 'user_id' => 'user_1' }
      response = described_class.from(hash)
      expect([response.status, response.message, response.job_id, response.user_id, response.raw])
        .to eq(['ACCEPTED', 'queued', 'job_1', 'user_1', hash])
      expect(response.accepted?).to be(true)
      expect(described_class.from('status' => nil).accepted?).to be(false)
    end
  end

  {
    SmileID::Generated::Models::BankCodesResponse => 'bank_codes',
    SmileID::Generated::Models::SupportedIdTypesResponse => 'id_types',
    SmileID::Generated::Models::SupportedDocumentsResponse => 'valid_documents'
  }.each do |model, field|
    describe model do
      it "exposes #{field} as it arrives on the wire" do
        hash = { field => [{ 'code' => 'X' }] }
        response = model.from(hash)
        expect([response.public_send(field), response.raw]).to eq([[{ 'code' => 'X' }], hash])
      end

      it "defaults #{field} to an empty list when absent" do
        expect(model.from({}).public_send(field)).to eq([])
      end
    end
  end

  describe SmileID::Generated::Models::IdStatusResponse do
    it 'reads every wire field' do
      hash = { 'last_checked' => '2026-01-01T00:00:00Z', 'last_check_status' => 'up',
               'last_hour_success_rate' => 0.99, 'last_known_status' => 'up',
               'last_check_success_rate' => 1.0 }
      response = described_class.from(hash)
      expect([response.last_checked, response.last_check_status, response.last_hour_success_rate,
              response.last_known_status, response.last_check_success_rate, response.raw])
        .to eq(['2026-01-01T00:00:00Z', 'up', 0.99, 'up', 1.0, hash])
    end
  end
end
