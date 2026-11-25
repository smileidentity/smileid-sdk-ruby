# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

RSpec.describe 'scripts/bump-version.sh' do
  let(:script) { File.expand_path('../../scripts/bump-version.sh', __dir__) }
  let(:root) { Dir.mktmpdir }
  let(:version_file) { File.join(root, 'lib/usesmileid/version.rb') }
  let(:changelog) { File.join(root, 'CHANGELOG.md') }
  let(:lockfile) { File.join(root, 'Gemfile.lock') }
  let(:version_spec) { File.join(root, 'spec/usesmileid/version_spec.rb') }
  let(:repo) { 'https://github.com/smileidentity/smileid-sdk-ruby' }

  let(:unreleased_changelog) do
    <<~MD
      # Changelog

      ## [Unreleased]

      ### Added

      - Something new.

      ## [1.2.3] - 2026-01-01

      - Older change.

      [Unreleased]: #{repo}/compare/v1.2.3...HEAD
      [1.2.3]: #{repo}/compare/v1.2.2...v1.2.3
    MD
  end

  before do
    FileUtils.mkdir_p(File.dirname(version_file))
    File.write(version_file, "# frozen_string_literal: true\n\nmodule SmileID\n  VERSION = '1.2.3'\nend\n")
    File.write(changelog, unreleased_changelog)
  end

  after { FileUtils.remove_entry(root) }

  def bump(part)
    env = { 'BUMP_VERSION_ROOT' => root, 'BUMP_VERSION_DATE' => '2026-11-09' }
    Open3.capture3(env, 'bash', script, part)
  end

  def version
    File.read(version_file)[/VERSION = '(.*)'/, 1]
  end

  { 'major' => '2.0.0', 'minor' => '1.3.0', 'patch' => '1.2.4' }.each do |part, expected|
    it "bumps the #{part} version and prints it" do
      stdout, stderr, status = bump(part)
      expect([stdout, stderr, status.success?]).to eq(["#{expected}\n", '', true])
      expect(version).to eq(expected)
    end
  end

  it 'sets an exact version greater than the current one and prints it' do
    stdout, stderr, status = bump('13.3.0')
    expect([stdout, stderr, status.success?]).to eq(["13.3.0\n", '', true])
    expect(version).to eq('13.3.0')
    expect(File.read(changelog)).to include("## [13.3.0] - 2026-11-09\n")
    expect(File.read(changelog)).to include("[13.3.0]: #{repo}/compare/v1.2.3...v13.3.0\n")
  end

  { 'equal' => '1.2.3', 'lower' => '1.2.2', 'lower major' => '0.9.9' }.each do |kind, exact|
    it "rejects an exact version that is #{kind} without changing anything" do
      _, stderr, status = bump(exact)

      expect(status.success?).to be(false)
      expect(stderr).to include("version #{exact} must be greater than the current version 1.2.3")
      expect(version).to eq('1.2.3')
      expect(File.read(changelog)).to eq(unreleased_changelog)
    end
  end

  ['1.3', '1.3.0.0', '01.3.0', '1.03.0', '1.3.0-rc.1', '1.3.x', "1.3.0\nanything"].each do |malformed|
    it "rejects the malformed version #{malformed.inspect}" do
      _, stderr, status = bump(malformed)

      expect(status.success?).to be(false)
      expect(stderr).to include("invalid version '#{malformed}'")
      expect(version).to eq('1.2.3')
    end
  end

  context 'with a Gemfile.lock and a version spec' do
    let(:lock_text) do
      "PATH\n  remote: .\n  specs:\n    usesmileid (1.2.3)\n      faraday (~> 2.0)\n\n" \
        "GEM\n  specs:\n    faraday (2.14.0)\n    other (1.2.3)\n"
    end
    let(:spec_text) do
      <<~RUBY
        RSpec.describe SmileID do
          it 'has a version number' do
            expect(SmileID::VERSION).to eq('1.2.3')
          end
        end
      RUBY
    end

    before do
      FileUtils.mkdir_p(File.dirname(version_spec))
      File.write(lockfile, lock_text)
      File.write(version_spec, spec_text)
    end

    it "updates the gem's own lockfile entry and the pinned version only" do
      bump('2.0.0')

      expect(File.read(lockfile)).to eq(lock_text.sub('usesmileid (1.2.3)', 'usesmileid (2.0.0)'))
      expect(File.read(version_spec)).to eq(spec_text.sub("eq('1.2.3')", "eq('2.0.0')"))
    end

    it 'fails without changing anything when the lockfile does not list the current version' do
      File.write(lockfile, lock_text.sub('usesmileid (1.2.3)', 'usesmileid (1.2.2)'))
      _, stderr, status = bump('minor')

      expect(status.success?).to be(false)
      expect(stderr).to include('usesmileid (1.2.3)')
      expect(version).to eq('1.2.3')
      expect(File.read(changelog)).to eq(unreleased_changelog)
    end

    it 'fails without changing anything when the version spec pins another version' do
      File.write(version_spec, spec_text.sub("eq('1.2.3')", "eq('1.2.2')"))
      _, stderr, status = bump('minor')

      expect(status.success?).to be(false)
      expect(stderr).to include('pins a version other than the current 1.2.3')
      expect(version).to eq('1.2.3')
      expect(File.read(lockfile)).to eq(lock_text)
    end
  end

  it 'moves the Unreleased notes under a dated heading and updates the compare links' do
    bump('minor')

    expect(File.read(changelog)).to eq(<<~MD)
      # Changelog

      ## [Unreleased]

      ## [1.3.0] - 2026-11-09

      ### Added

      - Something new.

      ## [1.2.3] - 2026-01-01

      - Older change.

      [Unreleased]: #{repo}/compare/v1.3.0...HEAD
      [1.3.0]: #{repo}/compare/v1.2.3...v1.3.0
      [1.2.3]: #{repo}/compare/v1.2.2...v1.2.3
    MD
  end

  it 'refuses to run twice, because nothing is left unreleased' do
    bump('patch')
    _, stderr, status = bump('patch')

    expect(status.success?).to be(false)
    expect(stderr).to include('nothing to release')
    expect(version).to eq('1.2.4')
  end

  it 'fails without changing anything when the version file is not in the expected shape' do
    File.write(version_file, "module SmileID\n  VERSION = \"1.2.3\"\nend\n")
    _, stderr, status = bump('patch')

    expect(status.success?).to be(false)
    expect(stderr).to include('exactly one line')
    expect(File.read(changelog)).to eq(unreleased_changelog)
  end

  it 'fails when the changelog has no Unreleased heading' do
    File.write(changelog, "# Changelog\n\n## [1.2.3] - 2026-01-01\n")
    _, stderr, status = bump('patch')

    expect(status.success?).to be(false)
    expect(stderr).to include("'## [Unreleased]'")
    expect(version).to eq('1.2.3')
  end

  it 'rejects an unknown part' do
    _, stderr, status = bump('huge')

    expect(status.success?).to be(false)
    expect(stderr).to include("unknown part 'huge'")
  end

  it 'keeps the real Gemfile.lock and version spec in step with VERSION' do
    real_root = File.expand_path('../..', __dir__)
    expect(File.read(File.join(real_root, 'Gemfile.lock'))).to include("    usesmileid (#{SmileID::VERSION})\n")
    expect(File.read(File.join(real_root, 'spec/usesmileid/version_spec.rb')))
      .to include("expect(SmileID::VERSION).to eq('#{SmileID::VERSION}')")
  end

  it 'checks the real repository files are in the expected shape' do
    real_root = File.expand_path('../..', __dir__)
    version_rb = File.read(File.join(real_root, 'lib/usesmileid/version.rb'))
    expect(version_rb).to match(/^  VERSION = '\d+\.\d+\.\d+'$/)
    expect(File.read(File.join(real_root, 'CHANGELOG.md')).scan(/^## \[Unreleased\]$/).size).to eq(1)
  end
end
