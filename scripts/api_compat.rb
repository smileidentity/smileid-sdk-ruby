# frozen_string_literal: true

# Compares public API snapshots made by scripts/api_snapshot.rb and reports
# anything that is removed or changed in a way that could break a caller.
# Additions are allowed, including new optional parameters on an existing
# method.
#
# Usage:
#   ruby scripts/api_compat.rb OLD_SNAPSHOT NEW_SNAPSHOT
#   ruby scripts/api_compat.rb RELEASE_SNAPSHOT BASE_SNAPSHOT HEAD_SNAPSHOT
#
# With two snapshots, exits 1 if NEW breaks OLD. With three, as in CI, only
# breaks that HEAD (the pull request) adds to BASE (its base branch) fail.
# Breaks already on BASE since RELEASE (the last stable tag) are printed as
# warnings, because the next release deals with them, not this pull request.

module ApiCompat
  METHOD_LINE = /\Amethod (?<name>.+?)\((?<params>.*)\)\z/

  module_function

  # Returns a list of human-readable breaks; empty when compatible.
  def breaks(old_lines, new_lines)
    old_entries = index(old_lines)
    new_entries = index(new_lines)

    old_entries.flat_map do |key, old_value|
      new_value = new_entries[key]
      if new_value.nil?
        ["removed: #{old_value[:line]}"]
      elsif old_value[:params]
        method_breaks(old_value, new_value)
      elsif old_value[:line] != new_value[:line] && !struct_extended?(old_value[:line], new_value[:line])
        ["changed: #{old_value[:line]} -> #{new_value[:line]}"]
      else
        []
      end
    end
  end

  # Keys each line by what it names, so a changed value is seen as a change
  # rather than a removal plus an addition.
  def index(lines)
    lines.map(&:strip).reject(&:empty?).to_h do |line|
      match = METHOD_LINE.match(line)
      if match
        [line.sub(/\(.*\z/m, ''), { line: line, params: parse_params(match[:params]) }]
      else
        [line.split(/ < |: /, 2).first, { line: line }]
      end
    end
  end

  # Appending members to a struct keeps existing positional and keyword
  # construction working.
  def struct_extended?(old_line, new_line)
    old_line.start_with?('struct ') && new_line.start_with?("#{old_line}, ")
  end

  def parse_params(text)
    text.split(', ').map do |param|
      case param
      when /\A&/ then [:block, param[1..]]
      # `**nil` means the method accepts no keywords at all, not **options.
      when '**nil' then [:nokey, nil]
      when /\A\*\*/ then [:keyrest, param[2..]]
      when /\A\*/ then [:rest, param[1..]]
      when /\A(.+): \?\z/ then [:key, Regexp.last_match(1)]
      when /\A(.+):\z/ then [:keyreq, Regexp.last_match(1)]
      when /\A(.+) = \?\z/ then [:opt, Regexp.last_match(1)]
      else [:req, param]
      end
    end
  end

  # A new signature is compatible when every call that worked before still
  # works: no new required arguments, and no accepted argument taken away.
  def method_breaks(old_value, new_value)
    old_params = old_value[:params]
    new_params = new_value[:params]
    problems = positional_problems(old_params, new_params) + keyword_problems(old_params, new_params)
    return [] if problems.empty?

    ["changed: #{old_value[:line]} -> #{new_value[:line]} (#{problems.join('; ')})"]
  end

  def positional_problems(old_params, new_params)
    problems = []
    old_required = count(old_params, :req)
    new_required = count(new_params, :req)
    if new_required > old_required
      problems << "required positional arguments went from #{old_required} to #{new_required}"
    end

    unless kinds(new_params).include?(:rest)
      old_max = kinds(old_params).include?(:rest) ? Float::INFINITY : old_required + count(old_params, :opt)
      new_max = new_required + count(new_params, :opt)
      problems << 'accepts fewer positional arguments' if new_max < old_max
    end
    problems
  end

  def keyword_problems(old_params, new_params)
    old_keywords = keywords(old_params)
    new_keywords = keywords(new_params)
    new_keyrest = kinds(new_params).include?(:keyrest)
    problems = []

    old_keywords.each_key do |key|
      problems << "keyword #{key}: removed" unless new_keywords.key?(key) || new_keyrest
    end
    problems << 'no longer accepts arbitrary keywords' if kinds(old_params).include?(:keyrest) && !new_keyrest

    new_keywords.each do |key, kind|
      next unless kind == :keyreq && old_keywords[key] != :keyreq

      problems << "keyword #{key}: is now required"
    end
    problems
  end

  def kinds(params)
    params.map(&:first)
  end

  def count(params, kind)
    kinds(params).count(kind)
  end

  def keywords(params)
    params.filter_map { |kind, key| [key, kind] if %i[key keyreq].include?(kind) }.to_h
  end

  USAGE = 'Usage: ruby scripts/api_compat.rb OLD NEW, or RELEASE BASE HEAD'

  # Command-line entry point. Returns the exit status.
  def run(paths, out: $stdout, annotate: ENV.fetch('GITHUB_ACTIONS', nil) == 'true')
    raise ArgumentError, USAGE unless [2, 3].include?(paths.size)

    snapshots = paths.map { |path| read_snapshot(path) }
    *earlier, base, head = snapshots
    inherited = earlier.empty? ? [] : breaks(earlier.first, base)
    introduced = breaks(base, head)

    report_inherited(inherited, out, annotate)
    report_introduced(introduced, out, earlier.empty?)
    introduced.empty? ? 0 : 1
  end

  def read_snapshot(path)
    lines = File.readlines(path, chomp: true)
    raise ArgumentError, "#{path} is not an API snapshot; did the snapshot fail?" \
      unless lines.any? { |line| line.start_with?('module SmileID') }

    lines
  end

  def report_inherited(inherited, out, annotate)
    return if inherited.empty?

    out.puts "#{inherited.size} breaking change(s) are already on the base branch since the last release. " \
             'They do not fail this check; the next release must be a major version:'
    inherited.each do |line|
      out.puts(annotate ? "::warning title=Inherited API break::#{line}" : "  warning: #{line}")
    end
  end

  def report_introduced(introduced, out, two_way)
    scope = two_way ? '' : ' in this pull request'
    if introduced.empty?
      out.puts "No breaking changes to the public API#{scope}."
    else
      out.puts "#{introduced.size} breaking change(s) to the public API#{scope}:"
      introduced.each { |line| out.puts "  #{line}" }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    exit ApiCompat.run(ARGV)
  rescue ArgumentError => e
    abort e.message
  end
end
