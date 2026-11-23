# frozen_string_literal: true

require 'spec_helper'

# spec-coverage.json maps every public operation in the spec to the SDK method
# that calls it. CI checks the file against the spec; this checks it against
# the code, so it can't claim support the SDK doesn't have.
RSpec.describe 'spec-coverage.json' do
  let(:manifest) { JSON.parse(File.read(File.expand_path('../../spec-coverage.json', __dir__))) }
  let(:supported) { manifest['operations'].reject { |_, entry| entry.key?('unsupported') } }
  let(:client) { build_client }

  # The token endpoint has no public method: every authenticated call mints its
  # token through this private one.
  let(:token_entry) { supported.fetch('getV3Token') }

  # Placeholder names differ between the spec ({jobId}) and the table ({job_id}).
  def normalize(path)
    path.gsub(/\{\w+\}/, '{}')
  end

  # Follows "client.a.b" from the client. Every step but the token's last one
  # must be public.
  def resolve(method, allow_private: false)
    *namespaces, name = method.delete_prefix('client.').split('.')
    receiver = namespaces.reduce(client) do |object, step|
      expect(object).to respond_to(step), "#{method}: #{object.class} has no public #{step}"
      object.public_send(step)
    end
    message = "#{method}: #{receiver.class} has no #{name}"
    expect(receiver.respond_to?(name, allow_private)).to be(true), message
    receiver.method(name)
  end

  it 'names a method the client has for every supported operation' do
    supported.each do |op_id, entry|
      expect(resolve(entry['method'], allow_private: op_id == 'getV3Token')).to be_a(Method)
    end
  end

  it 'maps the token endpoint to the private method that calls it' do
    name = token_entry['method'].delete_prefix('client.')
    verb, path = token_entry['path'].split(' ', 2)
    stub = stub_request(verb.downcase.to_sym, "#{TestHelpers::SANDBOX}#{path}")
           .to_return(status: 200, body: JSON.generate(token: make_jwt))

    expect(client).not_to respond_to(name)
    client.send(name, {}, nil)
    expect(stub).to have_been_requested
  end

  it 'supports exactly the operations in the generated operations table' do
    table = SmileID::Generated::Operations::OPS.values.map do |op|
      normalize("#{op.http_method.to_s.upcase} #{op.path}")
    end
    paths = supported.except('getV3Token').values.map { |entry| normalize(entry['path']) }

    expect(paths).to match_array(table)
  end

  it 'names result and error fields that exist' do
    supported.each_value do |entry|
      entry.fetch('response_headers', {}).each_value do |where|
        next unless where.is_a?(String)

        where.scan(/\b([A-Z]\w+)\.(\w+)/).each do |type, field|
          klass = [SmileID::Generated::Models, SmileID::Errors].find { |mod| mod.const_defined?(type, false) }
          defined = klass&.const_get(type, false)&.method_defined?(field)
          expect(defined).to be(true), "#{type}.#{field} doesn't exist"
        end
      end
    end
  end
end
