# frozen_string_literal: true

require 'json'
require 'optparse'
require 'smileid'

module SmileIDExample
  class UsageError < StandardError; end

  module_function

  def run(argv, env: ENV, stdout: $stdout, stderr: $stderr, http_client: nil)
    config, command, args = parse_global_flags(argv, env)
    if %w[help -h --help].include?(command)
      stdout.write(usage)
      return
    end
    raise UsageError, 'missing command; run one of: services, enhanced-kyc, status, replay' unless command

    validate_config!(config)
    client = SmileID::Client.new(
      partner_id: config.fetch(:partner_id),
      api_key: config.fetch(:api_key),
      partner_secret: config[:partner_secret],
      base_url: config[:base_url],
      default_callback_url: config[:callback_url],
      timeout: config.fetch(:timeout),
      http_client: http_client
    )

    case command
    when 'services'
      run_services(client, args, stdout)
    when 'enhanced-kyc'
      run_enhanced_kyc(client, args, config, stdout)
    when 'status'
      run_status(client, args, stdout)
    when 'replay'
      run_replay(client, args, stdout)
    else
      stderr.puts("unknown command #{command}")
      raise UsageError, "unknown command #{command}"
    end
  end

  def parse_global_flags(argv, env)
    config = {
      partner_id: env['SMILE_PARTNER_ID'].to_s,
      api_key: env['SMILE_API_KEY'].to_s,
      partner_secret: blank_to_nil(env['SMILE_PARTNER_SECRET']),
      base_url: blank_to_nil(env['SMILE_BASE_URL']),
      callback_url: blank_to_nil(env['SMILE_CALLBACK_URL']),
      timeout: (env['SMILE_TIMEOUT'] || '30').to_f
    }
    parser = OptionParser.new do |opts|
      opts.on('--partner-id VALUE') { |value| config[:partner_id] = value }
      opts.on('--api-key VALUE') { |value| config[:api_key] = value }
      opts.on('--partner-secret VALUE') { |value| config[:partner_secret] = value }
      opts.on('--base-url VALUE') { |value| config[:base_url] = value }
      opts.on('--callback-url VALUE') { |value| config[:callback_url] = value }
      opts.on('--timeout VALUE', Float) { |value| config[:timeout] = value }
    end
    rest = parser.order(argv.dup)
  rescue OptionParser::ParseError => e
    raise UsageError, e.message
  else
    [config, rest.shift, rest]
  end

  def validate_config!(config)
    missing = []
    missing << 'SMILE_PARTNER_ID or --partner-id' if config.fetch(:partner_id).empty?
    missing << 'SMILE_API_KEY or --api-key' if config.fetch(:api_key).empty?
    raise UsageError, "missing #{missing.join(' and ')}" unless missing.empty?
  end

  def run_services(client, args, stdout)
    options = { country: 'NG' }
    OptionParser.new { |opts| opts.on('--country VALUE') { |value| options[:country] = value } }.parse!(args)
    banks = client.services.bank_codes(country: options.fetch(:country))
    id_types = client.services.supported_id_types(country: options.fetch(:country))
    docs = client.services.supported_documents(country_code: options.fetch(:country))
    payload = {
      country: options.fetch(:country),
      bank_codes: banks.bank_codes,
      id_types: id_types.id_types,
      documents: docs.valid_documents
    }
    write_json(stdout, payload)
  end

  def run_enhanced_kyc(client, args, config, stdout)
    options = { country: 'NG', privacy_url: 'https://example.com/privacy', callback_url: config[:callback_url] }
    OptionParser.new do |opts|
      opts.on('--country VALUE') { |value| options[:country] = value }
      opts.on('--id-type VALUE') { |value| options[:id_type] = value }
      opts.on('--id-number VALUE') { |value| options[:id_number] = value }
      opts.on('--given-names VALUE') { |value| options[:given_names] = value }
      opts.on('--last-name VALUE') { |value| options[:last_name] = value }
      opts.on('--email VALUE') { |value| options[:email] = value }
      opts.on('--phone-number VALUE') { |value| options[:phone_number] = value }
      opts.on('--privacy-url VALUE') { |value| options[:privacy_url] = value }
      opts.on('--callback-url VALUE') { |value| options[:callback_url] = value }
    end.parse!(args)
    %i[id_type id_number given_names last_name].each do |key|
      raise UsageError, "--#{key.to_s.tr('_', '-')} is required" unless options[key]
    end
    accepted = client.enhanced_kyc.verify(
      country: options.fetch(:country),
      id_type: options.fetch(:id_type),
      id_number: options.fetch(:id_number),
      user_details: {
        given_names: options.fetch(:given_names),
        last_name: options.fetch(:last_name),
        email: options[:email],
        phone_number: options[:phone_number]
      }.compact,
      consent: SmileID::Consent.granted(
        granted_at: Time.now.utc,
        notice_language: 'EN',
        notice_privacy_policy_url: options.fetch(:privacy_url)
      ),
      callback_url: options[:callback_url]
    )
    payload = {
      status: accepted.status,
      message: accepted.message,
      job_id: accepted.job_id,
      user_id: accepted.user_id,
      accepted: accepted.accepted?
    }
    write_json(stdout, payload)
  end

  def run_status(client, args, stdout)
    options = {}
    OptionParser.new { |opts| opts.on('--job-id VALUE') { |value| options[:job_id] = value } }.parse!(args)
    raise UsageError, 'status requires --job-id' unless options[:job_id]

    status = client.verifications.retrieve(options.fetch(:job_id))
    payload = {
      status: status.status,
      message: status.message,
      job_id: status.job_id,
      user_id: status.user_id
    }
    write_json(stdout, payload)
  end

  def run_replay(client, args, stdout)
    options = {}
    OptionParser.new do |opts|
      opts.on('--job-id VALUE') { |value| options[:job_id] = value }
      opts.on('--callback-url VALUE') { |value| options[:callback_url] = value }
    end.parse!(args)
    raise UsageError, 'replay requires --job-id' unless options[:job_id]

    replay = client.verifications.replay(options.fetch(:job_id), callback_url: options[:callback_url])
    payload = {
      status: replay.status,
      message: replay.message,
      job_id: replay.job_id,
      user_id: replay.user_id
    }
    write_json(stdout, payload)
  end

  def write_json(stdout, value)
    stdout.write(JSON.pretty_generate(value))
    stdout.write("\n")
  end

  def blank_to_nil(value)
    value.to_s.empty? ? nil : value
  end

  def usage
    <<~USAGE
      Usage:
        smileid-example-ruby [global flags] services --country NG
        smileid-example-ruby [global flags] enhanced-kyc --country NG --id-type NIN --id-number 12345678901 --given-names Amina --last-name Okafor --email amina@example.com --privacy-url https://example.com/privacy
        smileid-example-ruby [global flags] status --job-id job_...
        smileid-example-ruby [global flags] replay --job-id job_... --callback-url https://example.com/webhook

      Global flags can also be set with SMILE_PARTNER_ID, SMILE_API_KEY, SMILE_PARTNER_SECRET, SMILE_BASE_URL, SMILE_CALLBACK_URL and SMILE_TIMEOUT.
    USAGE
  end
end
