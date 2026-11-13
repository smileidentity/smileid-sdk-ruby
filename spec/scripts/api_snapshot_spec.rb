# frozen_string_literal: true

require 'spec_helper'
require_relative '../../scripts/api_snapshot'
require_relative '../../scripts/api_compat'

RSpec.describe ApiSnapshot do
  def snapshot_of(root)
    stub_const('SnapshotFixture', root)
    described_class.lines(root)
  end

  def build_fixture(base_initialize)
    Module.new.tap do |root|
      base = Class.new { define_method(:initialize, &base_initialize) }
      root.const_set(:Base, base)
      root.const_set(:Child, Class.new(base))
      root.const_set(:Custom, Class.new do
        def self.new(name)
          allocate.tap do |obj|
            obj.instance_variable_set(:@name, name)
          end
        end
      end)
    end
  end

  it 'records the inherited constructor of a class that does not define initialize' do
    lines = snapshot_of(build_fixture(proc { |client, timeout: nil| [client, timeout] }))

    expect(lines).to include('method SnapshotFixture::Child.new(client, timeout: ?)',
                             'method SnapshotFixture::Base.new(client, timeout: ?)')
  end

  it 'records a custom self.new instead of initialize' do
    lines = snapshot_of(build_fixture(proc {}))

    expect(lines).to include('method SnapshotFixture::Custom.new(name)')
    expect(lines.grep(/Custom\.new/).size).to eq(1)
  end

  it 'reports a change to an inherited constructor as a break' do
    old_lines = snapshot_of(build_fixture(proc { |client, timeout: nil| [client, timeout] }))
    new_lines = snapshot_of(build_fixture(proc { |client, config| [client, config] }))

    expect(ApiCompat.breaks(old_lines, new_lines).join)
      .to include('changed: method SnapshotFixture::Child.new(client, timeout: ?)')
  end

  it 'renders **nil for a method that accepts no keywords' do
    expect(described_class.signature([%i[req x], [:nokey]])).to eq('x, **nil')
  end
end
