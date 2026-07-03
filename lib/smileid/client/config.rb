# frozen_string_literal: true

require 'uri'

module SmileID
  # Immutable client configuration (spec section 2.1). Sandbox by default.
  #
  # Fleet standards (2026-07-03): base_url must be an absolute https URL with
  # no query or fragment — there is deliberately no allow-insecure option.
  # Callback URLs must be https, validated at construction for the default and
  # before send for per-request values.
  class Config
    PARTNER_ID = /\A[1-9]\d*\z/
    BASE_URLS = {
      sandbox: 'https://testapi.smileidentity.com',
      production: 'https://api.smileidentity.com'
    }.freeze
    DEFAULT_TIMEOUT = 30
    DEFAULT_MAX_RETRIES = 2

    attr_reader :partner_id, :api_key, :environment,
                :default_callback_url, :base_url, :timeout, :max_retries, :http_client

    def initialize(partner_id:, api_key:, environment: :sandbox,
                   default_callback_url: nil, base_url: nil, timeout: DEFAULT_TIMEOUT,
                   max_retries: DEFAULT_MAX_RETRIES, http_client: nil)
      @partner_id = partner_id.to_s
      @api_key = api_key.to_s
      @environment = normalize_environment(environment)
      @default_callback_url = default_callback_url
      @timeout = timeout
      @max_retries = max_retries
      @http_client = http_client
      @base_url = (base_url || BASE_URLS.fetch(@environment)).chomp('/')
      validate!
    end

    # Validate that a callback URL is an absolute https URL. Raises the local
    # validation error so no request is made with an insecure callback.
    def self.validate_callback_url!(value, field: 'callback_url')
      uri = begin
        URI.parse(value.to_s)
      rescue URI::InvalidURIError
        nil
      end
      unless uri.is_a?(URI::Generic) && uri.absolute? && uri.host
        raise Errors::ValidationError.new("#{field} must be an absolute https URL")
      end
      return if uri.scheme == 'https'

      raise Errors::ValidationError.new("#{field} must use https")
    end

    private

    def normalize_environment(env)
      sym = env.to_s.downcase.to_sym
      return sym if BASE_URLS.key?(sym)

      raise ArgumentError, "environment must be one of #{BASE_URLS.keys.join(', ')}"
    end

    def validate!
      raise ArgumentError, 'partner_id is required' if @partner_id.empty?
      raise ArgumentError, 'api_key is required' if @api_key.empty?
      unless @partner_id.match?(PARTNER_ID)
        raise ArgumentError, 'partner_id must be a numeric string with no leading zeros'
      end

      validate_base_url!
      return if @default_callback_url.nil?

      self.class.validate_callback_url!(@default_callback_url, field: 'default_callback_url')
    end

    def validate_base_url!
      uri = begin
        URI.parse(@base_url)
      rescue URI::InvalidURIError
        nil
      end
      unless uri.is_a?(URI::Generic) && uri.absolute? && uri.host
        raise ArgumentError, 'base_url must be an absolute URL'
      end
      raise ArgumentError, 'base_url must use https' unless uri.scheme == 'https'
      return unless uri.query || uri.fragment

      raise ArgumentError, 'base_url must not include a query or fragment'
    end
  end

  # Telemetry headers sent on every request (spec section 2.4).
  module Telemetry
    SDK_NAME = 'ruby'

    module_function

    def headers
      {
        'SmileID-Source-SDK' => SDK_NAME,
        'SmileID-Source-SDK-Version' => SmileID::VERSION,
        'User-Agent' => "smileid-sdk-ruby/#{SmileID::VERSION} (ruby/#{RUBY_VERSION})"
      }
    end
  end
end
