# frozen_string_literal: true

require 'spec_helper'
require_relative '../../scripts/api_snapshot'

# api/public_api.txt records the gem's public API so that any change to it
# shows up in the pull request diff. CI's api-compat job compares the API with
# the last release separately.
RSpec.describe 'public API snapshot' do
  let(:snapshot_path) { File.expand_path('../../api/public_api.txt', __dir__) }

  it 'matches api/public_api.txt' do
    actual = "#{ApiSnapshot.lines(SmileID).join("\n")}\n"

    expect(actual).to eq(File.read(snapshot_path)),
                      'The public API changed. Regenerate the snapshot with ' \
                      '`bundle exec ruby scripts/api_snapshot.rb > api/public_api.txt` and commit it.'
  end
end
