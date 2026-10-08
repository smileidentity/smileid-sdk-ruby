# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SmileID do
  it 'has a version number' do
    expect(SmileID::VERSION).to eq('12.2.0')
  end
end
