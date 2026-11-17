# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

RSpec.describe 'scripts/check-coverage-exclusions.sh' do
  let(:script) { File.expand_path('../../scripts/check-coverage-exclusions.sh', __dir__) }
  let(:repo) { Dir.mktmpdir }
  let(:git_env) do
    { 'GIT_AUTHOR_NAME' => 'Test', 'GIT_AUTHOR_EMAIL' => 'test@example.com',
      'GIT_COMMITTER_NAME' => 'Test', 'GIT_COMMITTER_EMAIL' => 'test@example.com' }
  end

  let(:nocov) { '# :nocov:' }

  before do
    git('init', '-q', '-b', 'main')
    write('lib/a.rb', "x = 1\n")
    git('add', '.')
    git('commit', '-q', '-m', 'base')
  end

  after { FileUtils.remove_entry(repo) }

  def git(*args)
    _, err, status = Open3.capture3(git_env, 'git', *args, chdir: repo)
    raise err unless status.success?
  end

  def write(path, content)
    full = File.join(repo, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def commit_and_check(files)
    git('checkout', '-q', '-B', 'feature', 'main')
    files.each { |path, content| write(path, content) }
    git('add', '.')
    git('commit', '-q', '-m', 'change')
    Open3.capture3('bash', script, 'main', chdir: repo)
  end

  it 'passes when no exclusions are added' do
    stdout, _, status = commit_and_check('lib/a.rb' => "x = 1\ny = 2\n")
    expect(status.success?).to be(true)
    expect(stdout).to include('No coverage exclusions')
  end

  it 'reports each added exclusion with its file and line' do
    stdout, _, status = commit_and_check(
      'lib/a.rb' => "x = 1\n#{nocov}\ny = 2\n#{nocov}\n",
      'src/b.py' => "# pragma: no cover\n",
      'src/c.ts' => "/* c8 ignore next */\n/* istanbul ignore next */\n",
      'src/D.php' => "/** @codeCoverageIgnore */\n",
      'src/e.rs' => "#[coverage(off)]\n"
    )

    expect(status.exitstatus).to eq(1)
    expect(stdout.lines.map { |line| line.split(': ').first })
      .to contain_exactly('lib/a.rb:2', 'lib/a.rb:4', 'src/b.py:1', 'src/c.ts:1', 'src/c.ts:2',
                          'src/D.php:1', 'src/e.rs:1')
  end

  it 'reports @Generated outside generated code only' do
    annotation = "@Generated\n"
    stdout, _, status = commit_and_check('src/main/Client.java' => annotation,
                                         'src/main/generated/Model.java' => annotation)

    expect(status.exitstatus).to eq(1)
    expect(stdout).to include('src/main/Client.java:1: @Generated outside generated code')
    expect(stdout).not_to include('Model.java')
  end

  it 'reports new excludes in a JaCoCo config' do
    pom = "<plugin><artifactId>jacoco-maven-plugin</artifactId>\n<excludes>\n</plugin>\n"
    stdout, _, status = commit_and_check('pom.xml' => pom)

    expect(status.exitstatus).to eq(1)
    expect(stdout).to include('pom.xml:2: JaCoCo exclusion')
  end

  it 'ignores exclusions that were already on the base branch' do
    write('lib/a.rb', "#{nocov}\n")
    git('commit', '-q', '-am', 'existing exclusion')
    _, _, status = commit_and_check('lib/a.rb' => "#{nocov}\ny = 2\n")
    expect(status.success?).to be(true)
  end

  it 'does not treat an added line starting with "++ " as a new file header' do
    stdout, _, status = commit_and_check('lib/a.rb' => "x = 1\n++ b/other.rb\n#{nocov}\n")

    expect(status.exitstatus).to eq(1)
    expect(stdout).to start_with('lib/a.rb:3: coverage exclusion')
  end

  it 'reports the right file and line across several files and hunks' do
    write('lib/b.rb', "a\nb\nc\nd\ne\n")
    git('add', '.')
    git('commit', '-q', '-m', 'second file')
    stdout, _, status = commit_and_check('lib/a.rb' => "x = 1\n#{nocov}\n",
                                         'lib/b.rb' => "#{nocov}\na\nb\nc\nd\ne\n#{nocov}\n")

    expect(status.exitstatus).to eq(1)
    expect(stdout.lines.map { |line| line.split(': ').first })
      .to eq(['lib/a.rb:2', 'lib/b.rb:1', 'lib/b.rb:7'])
  end

  it 'does not flag a lowercase @generated docblock' do
    _, _, status = commit_and_check('src/x.js' => "/** @generated */\n")
    expect(status.success?).to be(true)
  end

  it 'fails when the base ref does not exist' do
    _, _, status = Open3.capture3('bash', script, 'no-such-ref', chdir: repo)
    expect(status.success?).to be(false)
  end

  it 'requires a base ref' do
    _, stderr, status = Open3.capture3('bash', script, chdir: repo)
    expect(status.exitstatus).to eq(2)
    expect(stderr).to include('Usage')
  end
end
