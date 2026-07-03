# frozen_string_literal: true

require 'uri'

module SmileID
  # Immutable client configuration (spec section 2.1). Sandbox by default.
  class Config
    PARTNER_ID = /\A[1-9]\d*\z/
    BASE_URLS = {
      sandbox: 'https://testapi.smileidentity.com',
      production: 'https://api.smileidentity.com'
    }.freeze
    DEFAULT_TIMEOUT = 30
    DEFAULT_MAX_RETRIES = 2

    attr_reader :partner_id, :api_key, :environment, :partner_secret,
                :default_callback_url, :base_url, :timeout, :max_retries, :http_client

    def initialize(partner_id:, api_key:, environment: :sandbox, partner_secret: nil,
                   default_callback_url: nil, base_url: nil, timeout: DEFAULT_TIMEOUT,
                   max_retries: DEFAULT_MAX_RETRIES, http_client: nil)
      @partner_id = partner_id.to_s
      @api_key = api_key.to_s
      @environment = normalize_environment(environment)
      @partner_secret = partner_secret
      @default_callback_url = default_callback_url
      @timeout = timeout
      @max_retries = max_retries
      @http_client = http_client
      @base_url = (base_url || BASE_URLS.fetch(@environment)).chomp('/')
      validate!
    end

    # True when HMAC request signing is enabled (spec section 2.5).
    def signing_enabled?
      !partner_secret.nil? && !partner_secret.to_s.empty?
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
      validate_base_url!
      validate_callback_url!(@default_callback_url) if @default_callback_url

      return if @partner_id.match?(PARTNER_ID)

      raise ArgumentError, 'partner_id must be a numeric string with no leading zeros'
    end

    def validate_base_url!
      uri = URI.parse(@base_url)
      raise ArgumentError, 'base_url must be an absolute URL' unless uri.is_a?(URI::HTTP) && uri.host
      raise ArgumentError, 'base_url must use https' unless uri.scheme == 'https'
      raise ArgumentError, 'base_url must not include query or fragment' if uri.query || uri.fragment
    rescue URI::InvalidURIError
      raise ArgumentError, 'base_url must be an absolute URL'
    end

    def self.validate_callback_url!(value, field: 'callback_url')
      uri = URI.parse(value.to_s)
      raise ArgumentError, "#{field} must be an absolute URL" unless uri.is_a?(URI::HTTP) && uri.host
      raise ArgumentError, "#{field} must use https" unless uri.scheme == 'https'
    rescue URI::InvalidURIError
      raise ArgumentError, "#{field} must be an absolute URL"
    end

    def validate_callback_url!(value)
      self.class.validate_callback_url!(value, field: 'default_callback_url')
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
