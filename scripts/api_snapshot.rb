# frozen_string_literal: true

# Prints a snapshot of the gem's public API: every public constant, class and
# module under SmileID, and every public method with its parameters. Lines are
# sorted so two snapshots can be compared with scripts/api_compat.rb.
#
# Usage: ruby scripts/api_snapshot.rb [LIB_DIR]
#
# LIB_DIR defaults to this checkout's lib/. Pass another directory, such as
# the lib/ of a release tag checked out elsewhere, to snapshot that version.

module ApiSnapshot
  ROOT_NAMESPACE = 'SmileID'

  module_function

  def load_sdk(lib_dir)
    lib_dir = File.expand_path(lib_dir)
    # Under `bundle exec`, the gemspec has already loaded this checkout's
    # version.rb. Forget it so that LIB_DIR's own copy is loaded instead.
    Object.send(:remove_const, ROOT_NAMESPACE) if Object.const_defined?(ROOT_NAMESPACE, false)
    $LOADED_FEATURES.reject! { |path| path.match?(%r{/usesmileid(/|\.rb)}) }
    $LOAD_PATH.unshift(lib_dir)
    require 'usesmileid'

    stray = $LOADED_FEATURES.grep(%r{/usesmileid(/|\.rb)}).reject { |path| path.start_with?("#{lib_dir}/") }
    abort "Loaded SDK files from outside #{lib_dir}: #{stray.join(', ')}" unless stray.empty?

    Object.const_get(ROOT_NAMESPACE)
  end

  def lines(root)
    entries = []
    walk(root, root.name, entries, {})
    entries.sort.uniq
  end

  def walk(mod, name, entries, seen)
    return if seen[mod]

    seen[mod] = true
    entries << describe_module(mod, name)
    entries.concat(method_lines(mod, name))

    mod.constants(false).each do |const|
      value = mod.const_get(const, false)
      full_name = "#{name}::#{const}"
      if value.is_a?(Module) && value.name&.start_with?("#{name}::")
        walk(value, full_name, entries, seen)
      else
        entries << "constant #{full_name}: #{value.class}"
      end
    end
  end

  def describe_module(mod, name)
    return "module #{name}" unless mod.is_a?(Class)

    "class #{name} < #{mod.superclass.name}"
  end

  def method_lines(mod, name)
    # Struct.new defines class methods that vary by Ruby version, so a struct
    # is described by its members and accessors instead.
    if mod.is_a?(Class) && mod < Struct
      return ["struct #{name}: #{mod.members.join(', ')}"] + instance_method_lines(mod, name)
    end

    lines = mod.singleton_class.public_instance_methods(false).map do |meth|
      "method #{name}.#{meth}(#{signature(mod.method(meth).parameters)})"
    end

    # Record the effective constructor of every class, including one it
    # inherits, so a change to an inherited initialize shows up here too.
    if mod.is_a?(Class) && !mod.singleton_class.public_method_defined?(:new, false)
      lines << "method #{name}.new(#{signature(mod.instance_method(:initialize).parameters)})"
    end

    lines + instance_method_lines(mod, name)
  end

  def instance_method_lines(mod, name)
    mod.public_instance_methods(false).map do |meth|
      "method #{name}##{meth}(#{signature(mod.instance_method(meth).parameters)})"
    end
  end

  # Anonymous parameters are reported as nil, :*, :** or :& depending on the
  # Ruby version, so they are all shown by kind only.
  ANONYMOUS = [nil, :*, :**, :&].freeze

  # Render Method#parameters as a Ruby-like signature.
  def signature(parameters)
    parameters.map do |kind, param_name|
      param_name = nil if ANONYMOUS.include?(param_name)
      case kind
      when :req then param_name.to_s.empty? ? '_' : param_name.to_s
      when :opt then "#{param_name} = ?"
      when :rest then "*#{param_name}"
      when :keyreq then "#{param_name}:"
      when :key then "#{param_name}: ?"
      when :keyrest then "**#{param_name}"
      when :nokey then '**nil'
      when :block then "&#{param_name}"
      end
    end.join(', ')
  end
end

if $PROGRAM_NAME == __FILE__
  lib_dir = ARGV.fetch(0, File.expand_path('../lib', __dir__))
  puts ApiSnapshot.lines(ApiSnapshot.load_sdk(lib_dir))
end
