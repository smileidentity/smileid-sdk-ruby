# frozen_string_literal: true

require 'time'

module SmileID
  # Builder for the shared `consent` object required on all seven entry
  # endpoints (spec section 5.1). Serialized as a JSON multipart part.
  #
  #   SmileID::Consent.granted(
  #     granted_at: Time.now.utc,
  #     notice_language: "EN",
  #     notice_privacy_policy_url: "https://example.com/privacy"
  #   )
  class Consent
    NOTICE_LANGUAGE = /\A[A-Z]{2}\z/

    attr_reader :granted, :granted_at, :notice_language, :notice_privacy_policy_url

    def initialize(granted:, granted_at:, notice_language:, notice_privacy_policy_url:)
      @granted = granted
      @granted_at = granted_at
      @notice_language = notice_language
      @notice_privacy_policy_url = notice_privacy_policy_url
    end

    # Build a consent object with granted set to true.
    def self.granted(granted_at:, notice_language:, notice_privacy_policy_url:)
      new(
        granted: true,
        granted_at: granted_at,
        notice_language: notice_language,
        notice_privacy_policy_url: notice_privacy_policy_url
      )
    end

    def to_h
      {
        'granted' => granted,
        'granted_at' => format_time(granted_at),
        'notice_language' => notice_language,
        'notice_privacy_policy_url' => notice_privacy_policy_url
      }
    end

    # Coerce a Consent or a plain Hash into a validated wire hash.
    def self.coerce(input)
      consent = input.is_a?(Consent) ? input : from_hash(input)
      consent.validate!
      consent.to_h
    end

    def self.from_hash(hash)
      h = stringify(hash)
      new(
        granted: h.key?('granted') ? h['granted'] : true,
        granted_at: h['granted_at'],
        notice_language: h['notice_language'],
        notice_privacy_policy_url: h['notice_privacy_policy_url']
      )
    end

    def validate!
      raise Errors::ValidationError.new('consent.granted must be true') unless granted == true
      raise Errors::ValidationError.new('consent.granted_at is required') if granted_at.nil?
      unless notice_language.to_s.match?(NOTICE_LANGUAGE)
        raise Errors::ValidationError.new('consent.notice_language must be a two-letter uppercase code')
      end
      return unless notice_privacy_policy_url.to_s.empty?

      raise Errors::ValidationError.new('consent.notice_privacy_policy_url is required')
    end

    def self.stringify(hash)
      raise Errors::ValidationError.new('consent is required') if hash.nil?

      hash.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
    end

    def format_time(value)
      return value.utc.strftime('%Y-%m-%dT%H:%M:%S.%LZ') if value.is_a?(Time)

      value
    end
  end
end
