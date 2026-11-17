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

  it 'checks the real repository files are in the expected shape' do
    real_root = File.expand_path('../..', __dir__)
    version_rb = File.read(File.join(real_root, 'lib/usesmileid/version.rb'))
    expect(version_rb).to match(/^  VERSION = '\d+\.\d+\.\d+'$/)
    expect(File.read(File.join(real_root, 'CHANGELOG.md')).scan(/^## \[Unreleased\]$/).size).to eq(1)
  end
end
