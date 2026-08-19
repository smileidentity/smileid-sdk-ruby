# frozen_string_literal: true

require 'faraday'
require 'json'
require 'time'

module SmileID
  # Normalized HTTP response returned by the transport.
  class Response
    attr_reader :status, :headers, :raw_body

    def initialize(status:, headers:, raw_body:)
      @status = status
      @headers = headers
      @raw_body = raw_body
    end

    # Parsed JSON body, or nil when the body is empty or not JSON.
    def json
      return @json if defined?(@json)

      @json = parse
    end

    private

    def parse
      return nil if raw_body.nil? || raw_body.to_s.empty?

      JSON.parse(raw_body)
    rescue JSON::ParserError
      nil
    end
  end

  # The single HTTP transport (spec section 2.2, 2.6). Builds the Faraday
  # request, sends it, retries idempotent operations on transient failures
  # honouring Retry-After, and normalizes the response. It does not touch auth;
  # the client injects tokens and handles the refresh-on-401 dance.
  class Transport
    RETRY_STATUSES = [408, 429, 500, 502, 503, 504].freeze
    BACKOFF_BASE = 0.5
    # Ceiling for an honoured Retry-After, so a hostile or misconfigured
    # header cannot block the caller indefinitely.
    RETRY_AFTER_CAP = 60

    def initialize(config)
      @config = config
      @connection = build_connection
    end

    def send_request(method:, url:, headers:, query: {}, body: nil, retryable: false, timeout: nil)
      attempt = 0
      loop do
        response = perform(method, url, headers, query, body, timeout)
        if retryable && RETRY_STATUSES.include?(response.status) && attempt < @config.max_retries
          sleep_for(backoff(attempt, response.headers['retry-after']))
          attempt += 1
          next
        end
        return response
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::SSLError => e
        raise Errors::ConnectionError.new(e.message) unless retryable && attempt < @config.max_retries

        sleep_for(backoff(attempt, nil))
        attempt += 1
      end
    end

    private

    def perform(method, url, headers, query, body, timeout)
      resp = @connection.run_request(method, url, body, headers) do |req|
        req.params.update(query) if query && !query.empty?
        req.options.timeout = timeout || @config.timeout
      end
      Response.new(status: resp.status, headers: resp.headers, raw_body: resp.body)
    end

    def build_connection
      return @config.http_client if @config.http_client.is_a?(Faraday::Connection)

      Faraday.new do |f|
        f.adapter(Faraday.default_adapter)
      end
    end

    # Exponential backoff with jitter; honour Retry-After (capped) when present.
    def backoff(attempt, retry_after)
      honoured = parse_retry_after(retry_after)
      return [honoured, RETRY_AFTER_CAP].min if honoured

      (BACKOFF_BASE * (2**attempt)) + (rand * BACKOFF_BASE)
    end

    # Retry-After is either delta-seconds or an RFC 7231 HTTP-date. Returns
    # the delay in seconds (floored at 0), or nil when absent or unparseable.
    def parse_retry_after(value)
      str = value.to_s.strip
      return nil if str.empty?
      return str.to_f if str.match?(/\A\d+(\.\d+)?\z/)

      begin
        [Time.httpdate(str) - Time.now, 0].max
      rescue ArgumentError
        nil
      end
    end

    def sleep_for(seconds)
      sleep(seconds)
    end
  end
end
