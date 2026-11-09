# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

RSpec.describe 'scripts/previous-release-tag.sh' do
  let(:script) { File.expand_path('../../scripts/previous-release-tag.sh', __dir__) }
  let(:repo) { Dir.mktmpdir }
  let(:git_env) do
    { 'GIT_AUTHOR_NAME' => 'Test', 'GIT_AUTHOR_EMAIL' => 'test@example.com',
      'GIT_COMMITTER_NAME' => 'Test', 'GIT_COMMITTER_EMAIL' => 'test@example.com' }
  end

  after { FileUtils.remove_entry(repo) }

  def git(*args)
    _, err, status = Open3.capture3(git_env, 'git', *args, chdir: repo)
    raise err unless status.success?
  end

  def commit(tag = nil)
    git('commit', '-q', '--allow-empty', '-m', tag || 'change')
    git('tag', tag) if tag
  end

  def previous_tag(ref)
    stdout, stderr, status = Open3.capture3('bash', script, ref, chdir: repo)
    raise stderr unless status.success?

    stdout.chomp
  end

  before do
    git('init', '-q', '-b', 'main')
    commit('v0.9.0')
    commit('v1.0.0')
    commit('v1.9.0')
    commit('v1.10.0')
    commit('v2.0.0-rc.1')
    commit
  end

  it 'picks the newest stable tag by version, skipping pre-releases' do
    expect(previous_tag('main')).to eq('v1.10.0')
  end

  it 'excludes the tag itself when given the commit before it' do
    commit('v2.0.0')
    expect(previous_tag('v2.0.0^')).to eq('v1.10.0')
  end

  it 'only sees tags on the ref history, so a backport sees its own line' do
    git('checkout', '-q', '-b', 'release-1.0', 'v1.0.0')
    commit('v1.0.1')
    expect(previous_tag('v1.0.1^')).to eq('v1.0.0')
    expect(previous_tag('main')).to eq('v1.10.0')
  end

  it 'prints nothing when there is no stable tag' do
    git('checkout', '-q', '--orphan', 'fresh')
    commit
    expect(previous_tag('fresh')).to eq('')
  end

  it 'fails for an unknown ref' do
    _, _, status = Open3.capture3('bash', script, 'no-such-ref', chdir: repo)
    expect(status.success?).to be(false)
  end
end
