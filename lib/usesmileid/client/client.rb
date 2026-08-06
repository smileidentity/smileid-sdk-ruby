# frozen_string_literal: true

require 'erb'
require 'json'

module SmileID
  # The Smile ID client (spec section 2.1, 4). Construct once, then call
  # resource verbs, e.g. client.enhanced_kyc.verify(...).
  class Client
    attr_reader :config

    def initialize(partner_id:, api_key:, environment: :sandbox,
                   default_callback_url: nil, base_url: nil, timeout: Config::DEFAULT_TIMEOUT,
                   max_retries: Config::DEFAULT_MAX_RETRIES, http_client: nil)
      @config = Config.new(
        partner_id: partner_id, api_key: api_key, environment: environment,
        default_callback_url: default_callback_url,
        base_url: base_url, timeout: timeout, max_retries: max_retries, http_client: http_client
      )
      @transport = Transport.new(@config)
      @token_manager = TokenManager.new(@config, @transport)
    end

    def enhanced_kyc
      @enhanced_kyc ||= Resources::EnhancedKyc.new(self)
    end

    def documents
      @documents ||= Resources::Documents.new(self)
    end

    def biometric_kyc
      @biometric_kyc ||= Resources::BiometricKyc.new(self)
    end

    def biometric
      @biometric ||= Resources::Biometric.new(self)
    end

    def verifications
      @verifications ||= Resources::Verifications.new(self)
    end

    def users
      @users ||= Resources::Users.new(self)
    end

    def services
      @services ||= Resources::Services.new(self)
    end

    # Execute an operation end to end: build the request, attach auth and
    # telemetry, sign if configured, send it, refresh-on-401 once, and either
    # return the response or raise a typed error (spec section 2A, 7).
    #
    # @return [SmileID::Response] on a success status for the operation.
    def call(op_key, form: nil, path_params: {}, query: {}, user_id_header: nil, timeout: nil)
      op = Generated::Operations.fetch(op_key)
      url = @config.base_url + interpolate(op.path, path_params)
      content_type, body = serialize(op, form)
      refreshed = false

      loop do
        headers = build_headers(op, content_type, user_id_header)
        response = @transport.send_request(
          method: op.http_method, url: url, headers: headers, query: query || {},
          body: body, retryable: op.idempotent, timeout: timeout
        )

        if response.status == 401 && op.authenticated && !refreshed
          @token_manager.force_refresh
          refreshed = true
          next
        end

        return handle(op, response)
      end
    end

    private

    # Multipart bodies only; an op with an optional body (replay) sends no
    # body at all when there are no fields.
    def serialize(op, form)
      return [nil, nil] unless op.body_kind == :multipart
      return [nil, nil] if form.nil? || form.empty?

      Helpers::Multipart.build(form)
    end

    def build_headers(op, content_type, user_id_header)
      headers = Telemetry.headers
      headers['Content-Type'] = content_type if content_type
      headers['SmileID-Token'] = @token_manager.token if op.authenticated
      headers['SmileID-Partner-ID'] = @config.partner_id if op.partner_id_header
      headers['User-ID'] = user_id_header if user_id_header
      headers
    end

    def handle(op, response)
      if op.success_statuses.include?(response.status)
        return response if response.json.is_a?(Hash)

        raise Errors::UnexpectedResponseError.new(
          'expected a JSON object response body',
          status_code: response.status,
          request_id: Errors.request_id_from(response.headers),
          raw_body: response.raw_body
        )
      end

      raise Errors.from_response(
        status_code: response.status,
        body: response.json,
        raw_body: response.raw_body,
        headers: response.headers
      )
    end

    def interpolate(path, path_params)
      path.gsub(/\{(\w+)\}/) do
        key = Regexp.last_match(1)
        value = path_params[key] || path_params[key.to_sym]
        raise ArgumentError, "missing path parameter: #{key}" if value.nil?

        ERB::Util.url_encode(value.to_s)
      end
    end
  end
end
