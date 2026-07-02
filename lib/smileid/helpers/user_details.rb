# frozen_string_literal: true

module SmileID
  # Builder and validator for the shared `user_details` object required on all
  # seven entry endpoints (spec section 5.1). Serialized as a JSON multipart part.
  #
  # At least one of email / phone_number MUST be present — enforced client-side
  # before the request is sent.
  class UserDetails
    PHONE_NUMBER = /\A\+[1-9]\d{6,14}\z/

    attr_reader :given_names, :last_name, :email, :phone_number

    def initialize(given_names:, last_name:, email: nil, phone_number: nil)
      @given_names = given_names
      @last_name = last_name
      @email = email
      @phone_number = phone_number
    end

    def to_h
      {
        'given_names' => given_names,
        'last_name' => last_name,
        'email' => email,
        'phone_number' => phone_number
      }.compact
    end

    # Coerce a UserDetails or plain Hash into a validated wire hash.
    def self.coerce(input)
      details = input.is_a?(UserDetails) ? input : from_hash(input)
      details.validate!
      details.to_h
    end

    def self.from_hash(hash)
      raise Errors::ValidationError.new('user_details is required') if hash.nil?

      h = hash.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
      new(
        given_names: h['given_names'],
        last_name: h['last_name'],
        email: h['email'],
        phone_number: h['phone_number']
      )
    end

    def validate!
      raise Errors::ValidationError.new('user_details.given_names is required') if given_names.to_s.empty?
      raise Errors::ValidationError.new('user_details.last_name is required') if last_name.to_s.empty?

      if email.to_s.empty? && phone_number.to_s.empty?
        raise Errors::ValidationError.new(
          'user_details requires at least one of email or phone_number'
        )
      end
      return unless !phone_number.to_s.empty? && !phone_number.to_s.match?(PHONE_NUMBER)

      raise Errors::ValidationError.new('user_details.phone_number must be E.164 format')
    end
  end
end
