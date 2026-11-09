# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tmpdir'
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

  describe '.run' do
    let(:dir) { Dir.mktmpdir }
    let(:release) { ['module SmileID', 'method SmileID::A#old()', 'method SmileID::A#keep(x)'] }
    let(:base) { ['module SmileID', 'method SmileID::A#keep(x)'] }

    after { FileUtils.remove_entry(dir) }

    def snapshot(name, lines)
      File.join(dir, name).tap { |path| File.write(path, "#{lines.join("\n")}\n") }
    end

    def run_compat(*snapshots, annotate: false)
      out = StringIO.new
      paths = snapshots.each_with_index.map { |lines, i| snapshot("s#{i}.txt", lines) }
      [described_class.run(paths, out: out, annotate: annotate), out.string]
    end

    it 'passes with a warning when the break is already on the base branch' do
      status, output = run_compat(release, base, base + ['method SmileID::A#added()'])

      expect(status).to eq(0)
      expect(output).to include('already on the base branch', 'warning: removed: method SmileID::A#old()',
                                'No breaking changes to the public API in this pull request.')
    end

    it 'writes inherited breaks as GitHub warning annotations in CI' do
      _, output = run_compat(release, base, base, annotate: true)
      expect(output).to include('::warning title=Inherited API break::removed: method SmileID::A#old()')
    end

    it 'fails only on the break the pull request adds' do
      status, output = run_compat(release, base, ['module SmileID', 'method SmileID::A#keep(x, y)'])

      expect(status).to eq(1)
      expect(output).to include('1 breaking change(s) to the public API in this pull request:',
                                'required positional arguments went from 1 to 2')
      expect(output.scan('removed: method SmileID::A#old()').size).to eq(1)
    end

    it 'compares two snapshots directly' do
      expect(run_compat(release, base).first).to eq(1)
      expect(run_compat(base, release).first).to eq(0)
    end

    it 'rejects a file that is not a snapshot, and the wrong number of files' do
      expect { run_compat([], base) }.to raise_error(ArgumentError, /not an API snapshot/)
      expect { run_compat(base) }.to raise_error(ArgumentError, /Usage/)
    end
  end
end
