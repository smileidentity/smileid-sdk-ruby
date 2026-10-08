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

    # Execute an operation end to end: mint its token, build the request, attach
    # auth and telemetry, send it, and either return the response or raise a
    # typed error (spec section 2A, 7). Every authenticated call mints its own
    # token; retries of an idempotent call reuse it.
    #
    # @return [SmileID::Response] on a success status for the operation.
    def call(op_key, form: nil, path_params: {}, query: {}, user_id_header: nil, timeout: nil,
             use_enrolled_image: false)
      op = Generated::Operations.fetch(op_key)
      url = @config.base_url + interpolate(op.path, path_params)
      content_type, body = serialize(op, form)
      token = mint_token(op, form, user_id_header, use_enrolled_image) if op.authenticated

      headers = build_headers(op, content_type, user_id_header, token)
      response = @transport.send_request(
        method: op.http_method, url: url, headers: headers, query: query || {},
        body: body, retryable: op.idempotent, timeout: timeout
      )
      handle(op, response)
    end

    private

    # Multipart bodies only; an op with an optional body (replay) sends no
    # body at all when there are no fields.
    def serialize(op, form)
      return [nil, nil] unless op.body_kind == :multipart
      return [nil, nil] if form.nil? || form.empty?

      Helpers::Multipart.build(form)
    end

    def build_headers(op, content_type, user_id_header, token)
      headers = Telemetry.headers
      headers['Content-Type'] = content_type if content_type
      headers['SmileID-Token'] = token if token
      headers['SmileID-Partner-ID'] = @config.partner_id if op.partner_id_header
      headers['User-ID'] = user_id_header if user_id_header
      headers
    end

    # The token is bound to this one request's user and product. A grant
    # (use_enrolled_image) authorises a captureless job for one user, so it must
    # never reach another call's token.
    def mint_token(op, form, user_id_header, use_enrolled_image)
      user_id = op.token_user_id == :header ? user_id_header : form && form['user_id']
      claims = {
        'user_id' => user_id,
        'product' => op.product,
        'use_enrolled_image' => (true if use_enrolled_image)
      }.compact
      content_type, body = Helpers::Multipart.build(claims) unless claims.empty?
      response = @transport.send_request(
        method: :post,
        url: "#{@config.base_url}/v3/token",
        headers: token_headers(content_type),
        body: body,
        retryable: true
      )

      unless response.status == 200
        raise Errors.from_response(
          status_code: response.status,
          body: response.json,
          raw_body: response.raw_body,
          headers: response.headers
        )
      end

      jwt = response.json && response.json['token']
      raise Errors::AuthenticationError.new('token endpoint returned no token') if jwt.nil?

      jwt
    end

    def token_headers(content_type)
      headers = Telemetry.headers.merge(
        'smileid-partner-id' => @config.partner_id,
        'smileid-api-key' => @config.api_key
      )
      headers['Content-Type'] = content_type if content_type
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
