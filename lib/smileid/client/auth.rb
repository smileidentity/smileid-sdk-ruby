# frozen_string_literal: true

require 'base64'
require 'json'

module SmileID
  # Internal JWT lifecycle (spec section 2.3, 2A). Partners never see the token.
  #
  # The cache is thread-safe: concurrent calls do not stampede the token
  # endpoint. The token is cached until its JWT `exp` claim minus a 60s skew; a
  # token whose expiry cannot be decoded is treated as single-use (refreshed on
  # the next call, and always on a 401).
  class TokenManager
    EXPIRY_SKEW = 60

    def initialize(config, transport)
      @config = config
      @transport = transport
      @mutex = Mutex.new
      @cached = nil
    end

    # Return a valid token, fetching one if the cache is empty or expired.
    def token
      @mutex.synchronize do
        return @cached[:jwt] if valid?

        fetch
      end
    end

    # Force a refresh (used after a 401). Fetches a new token unconditionally.
    def force_refresh
      @mutex.synchronize do
        @cached = nil
        fetch
      end
    end

    private

    def valid?
      @cached && Time.now < @cached[:expires_at]
    end

    def fetch
      response = @transport.send_request(
        method: :post,
        url: "#{@config.base_url}/v3/token",
        headers: Telemetry.headers.merge(
          'smileid-partner-id' => @config.partner_id,
          'smileid-api-key' => @config.api_key
        ),
        query: {},
        body: nil,
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

      @cached = { jwt: jwt, expires_at: expires_at(jwt) }
      jwt
    end

    def expires_at(jwt)
      exp = decode_exp(jwt)
      exp ? Time.at(exp) - EXPIRY_SKEW : Time.now
    end

    # Decode the `exp` claim from a JWT without verifying the signature. Returns
    # nil when the token cannot be decoded.
    def decode_exp(jwt)
      payload_segment = jwt.to_s.split('.')[1]
      return nil if payload_segment.nil?

      payload = JSON.parse(Base64.urlsafe_decode64(pad(payload_segment)))
      exp = payload['exp']
      exp.is_a?(Numeric) ? exp : nil
    rescue ArgumentError, JSON::ParserError
      nil
    end

    def pad(segment)
      remainder = segment.length % 4
      remainder.zero? ? segment : segment + ('=' * (4 - remainder))
    end
  end
end
