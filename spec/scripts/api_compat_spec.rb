# frozen_string_literal: true

require 'spec_helper'
require_relative '../../scripts/api_compat'

RSpec.describe ApiCompat do
  def breaks(old_lines, new_lines)
    described_class.breaks(old_lines, new_lines)
  end

  it 'allows additions' do
    old_lines = ['module SmileID', 'method SmileID::Client#users()']
    new_lines = old_lines + ['method SmileID::Client#links()', 'constant SmileID::LIMIT: Integer']
    expect(breaks(old_lines, new_lines)).to eq([])
  end

  it 'reports a removed method, class or constant' do
    old_lines = ['class SmileID::A < Object', 'constant SmileID::B: String', 'method SmileID::C#d()']
    expect(breaks(old_lines, [])).to eq(old_lines.map { |line| "removed: #{line}" })
  end

  it 'reports a changed superclass or constant type' do
    expect(breaks(['class SmileID::A < Object'], ['class SmileID::A < StandardError']))
      .to eq(['changed: class SmileID::A < Object -> class SmileID::A < StandardError'])
    expect(breaks(['constant SmileID::B: String'], ['constant SmileID::B: Symbol'])).not_to be_empty
  end

  it 'allows new optional parameters and keywords' do
    old_lines = ['method SmileID::A#b(job_id, timeout: ?)']
    new_lines = ['method SmileID::A#b(job_id, page = ?, timeout: ?, locale: ?, &block)']
    expect(breaks(old_lines, new_lines)).to eq([])
  end

  it 'allows a required keyword to become optional' do
    expect(breaks(['method SmileID::A#b(country:)'], ['method SmileID::A#b(country: ?)'])).to eq([])
  end

  it 'reports a removed keyword' do
    result = breaks(['method SmileID::A#b(country:, timeout: ?)'], ['method SmileID::A#b(country:)'])
    expect(result.join).to include('keyword timeout: removed')
  end

  it 'allows a removed keyword when the method now takes **options' do
    expect(breaks(['method SmileID::A#b(timeout: ?)'], ['method SmileID::A#b(**options)'])).to eq([])
  end

  it 'reports a new or newly required keyword' do
    result = breaks(['method SmileID::A#b(a: ?)'], ['method SmileID::A#b(a:, c:)'])
    expect(result.join).to include('keyword a: is now required', 'keyword c: is now required')
  end

  it 'reports a new required positional argument' do
    result = breaks(['method SmileID::A#b(x)'], ['method SmileID::A#b(x, y)'])
    expect(result.join).to include('required positional arguments went from 1 to 2')
  end

  it 'reports fewer accepted positional arguments' do
    expect(breaks(['method SmileID::A#b(x, y = ?)'], ['method SmileID::A#b(x)']).join)
      .to include('accepts fewer positional arguments')
    expect(breaks(['method SmileID::A#b(*args)'], ['method SmileID::A#b(x)']).join)
      .to include('accepts fewer positional arguments')
    expect(breaks(['method SmileID::A#b(x)'], ['method SmileID::A#b(*args)'])).to eq([])
  end

  it 'reports a lost **options' do
    expect(breaks(['method SmileID::A#b(**opts)'], ['method SmileID::A#b(a: ?)']).join)
      .to include('no longer accepts arbitrary keywords')
  end

  it 'allows new struct members at the end only' do
    old_line = 'struct SmileID::Op: a, b'
    expect(breaks([old_line], ['struct SmileID::Op: a, b, c'])).to eq([])
    expect(breaks([old_line], ['struct SmileID::Op: b, a'])).not_to be_empty
  end
end
