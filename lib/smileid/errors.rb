# frozen_string_literal: true

module SmileID
  # Typed error hierarchy over both wire error shapes (spec section 7).
  #
  # Wire shapes handled:
  #   - { "status": <text>, "message": <human> }  (most endpoints; id_status reorders keys)
  #   - { "error": <human>, "code": <string> }     (the three unauthenticated services endpoints)
  #
  # The class is chosen by HTTP status, never by body contents.
  module Errors
    # Base class for every error the SDK raises.
    class SmileIDError < StandardError
      # HTTP status code (Integer), or nil for connection/local errors.
      attr_reader :status_code
      # HTTP status text from the body when present (e.g. "Bad Request").
      attr_reader :status
      # Machine code, present only on the services { error, code } shape.
      attr_reader :code
      # Request id, populated from a response header if one exists, else nil.
      attr_reader :request_id
      # The unparsed response body.
      attr_reader :raw_body

      def initialize(message = nil, status_code: nil, status: nil, code: nil,
                     request_id: nil, raw_body: nil)
        super(message)
        @status_code = status_code
        @status = status
        @code = code
        @request_id = request_id
        @raw_body = raw_body
      end
    end

    # 400 and 415 — malformed request, or a failed client-side validation.
    class InvalidRequestError < SmileIDError; end

    # Raised before send when a local validation rule fails (spec section 5.1, 6.11).
    class ValidationError < InvalidRequestError; end

    # 401 — token missing, invalid, or expired after a single refresh attempt.
    class AuthenticationError < SmileIDError; end

    # 402 — insufficient wallet balance.
    class PaymentRequiredError < SmileIDError; end

    # 403 — not authorized (includes the services { error, code } shape).
    class PermissionError < SmileIDError; end

    # 404 — not found. Note: jobs.retrieve does NOT raise this (spec section 6.8).
    class NotFoundError < SmileIDError; end

    # 409 — business-state conflict (replay still processing). Never auto-retried.
    class ConflictError < SmileIDError; end

    # 413 — payload too large.
    class PayloadTooLargeError < SmileIDError; end

    # 429 — rate limited.
    class RateLimitError < SmileIDError; end

    # 5xx — server error.
    class APIError < SmileIDError; end

    # Network failure or timeout with no HTTP response.
    class ConnectionError < SmileIDError; end

    # SDK-local — raised by verifications.wait_until_complete when the deadline passes.
    class TimeoutError < SmileIDError; end

    STATUS_CLASSES = {
      400 => InvalidRequestError,
      401 => AuthenticationError,
      402 => PaymentRequiredError,
      403 => PermissionError,
      404 => NotFoundError,
      409 => ConflictError,
      413 => PayloadTooLargeError,
      415 => InvalidRequestError,
      429 => RateLimitError
    }.freeze

    # The response header names we probe for a request id (none is defined in the
    # spec today; populate from a header if the backend ever sends one).
    REQUEST_ID_HEADERS = %w[x-request-id smileid-request-id request-id].freeze

    # Select the error class for an HTTP status code.
    def self.class_for(status_code)
      return STATUS_CLASSES[status_code] if STATUS_CLASSES.key?(status_code)
      return APIError if status_code && status_code >= 500

      SmileIDError
    end

    # Build a typed error from a response (see parse_error, spec section 2A).
    def self.from_response(status_code:, body:, raw_body:, headers: {})
      body = {} unless body.is_a?(Hash)
      message = body['message'] || body['error']
      klass = class_for(status_code)
      klass.new(
        message,
        status_code: status_code,
        status: body['status'],
        code: body['code'],
        request_id: request_id_from(headers),
        raw_body: raw_body
      )
    end

    def self.request_id_from(headers)
      return nil unless headers.respond_to?(:[])

      REQUEST_ID_HEADERS.each do |name|
        value = headers[name] || headers[name.split('-').map(&:capitalize).join('-')]
        return value if value
      end
      nil
    end
  end
end
