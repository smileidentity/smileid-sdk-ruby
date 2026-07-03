# frozen_string_literal: true

module SmileID
  # Resource namespaces exposing the public SDK surface (spec section 4).
  # Each maps a verb to an operation, coerces and validates input, and wraps the
  # response in a typed model.
  module Resources
    # Shared behaviour for all resources.
    class Base
      def initialize(client)
        @client = client
      end

      private

      def coerce_consent(consent)
        Consent.coerce(consent)
      end

      def coerce_user_details(user_details)
        UserDetails.coerce(user_details)
      end

      # Use an explicit callback_url, else fall back to the configured default.
      def resolve_callback(callback_url)
        resolved = callback_url || @client.config.default_callback_url
        Config.validate_callback_url!(resolved) if resolved
        resolved
      end

      def accepted(response)
        Generated::Models::AcceptedResponse.from(response.json)
      end
    end

    # POST /v3/enhanced_kyc
    class EnhancedKyc < Base
      def verify(country:, id_type:, id_number:, user_details:, consent:,
                 callback_url: nil, bank_code: nil, operator: nil,
                 partner_params: nil, metadata: nil, user_id: nil, timeout: nil)
        form = {
          'country' => country,
          'id_type' => id_type,
          'id_number' => id_number,
          'user_details' => coerce_user_details(user_details),
          'consent' => coerce_consent(consent),
          'callback_url' => resolve_callback(callback_url),
          'bank_code' => bank_code,
          'operator' => operator,
          'partner_params' => partner_params,
          'metadata' => metadata
        }.compact
        accepted(@client.call(:enhanced_kyc, form: form, user_id_header: user_id, timeout: timeout))
      end
    end

    # POST /v3/document_verification and /v3/enhanced_document_verification
    class Documents < Base
      def verify(selfie_image:, liveness_images:, document:, consent:, country:, user_details:,
                 document_back: nil, id_type: nil, callback_url: nil,
                 partner_params: nil, metadata: nil, user_id: nil, timeout: nil)
        form = document_form(
          selfie_image: selfie_image, liveness_images: liveness_images, document: document,
          document_back: document_back, consent: consent, country: country, id_type: id_type,
          user_details: user_details, callback_url: callback_url,
          partner_params: partner_params, metadata: metadata
        )
        accepted(@client.call(:document_verification, form: form, user_id_header: user_id, timeout: timeout))
      end

      # id_type is REQUIRED for enhanced document verification (spec section 6.3).
      def verify_enhanced(id_type:, selfie_image:, liveness_images:, document:, consent:, country:,
                          user_details:, document_back: nil, callback_url: nil,
                          partner_params: nil, metadata: nil, user_id: nil, timeout: nil)
        if id_type.to_s.empty?
          raise Errors::ValidationError.new('id_type is required for enhanced document verification')
        end

        form = document_form(
          selfie_image: selfie_image, liveness_images: liveness_images, document: document,
          document_back: document_back, consent: consent, country: country, id_type: id_type,
          user_details: user_details, callback_url: callback_url,
          partner_params: partner_params, metadata: metadata
        )
        accepted(@client.call(:enhanced_document_verification, form: form,
                                                               user_id_header: user_id, timeout: timeout))
      end

      private

      def document_form(selfie_image:, liveness_images:, document:, document_back:, consent:,
                        country:, id_type:, user_details:, callback_url:, partner_params:, metadata:)
        {
          'country' => country,
          'id_type' => id_type,
          'selfie_image' => selfie_image,
          'liveness_images' => liveness_images,
          'document' => document,
          'document_back' => document_back,
          'user_details' => coerce_user_details(user_details),
          'consent' => coerce_consent(consent),
          'callback_url' => resolve_callback(callback_url),
          'partner_params' => partner_params,
          'metadata' => metadata
        }.compact
      end
    end

    # POST /v3/biometric_kyc
    class BiometricKyc < Base
      def verify(selfie_image:, liveness_images:, consent:, country:, id_type:, id_number:,
                 user_details:, callback_url: nil, sandbox_result: nil,
                 partner_params: nil, metadata: nil, user_id: nil, timeout: nil)
        form = {
          'country' => country,
          'id_type' => id_type,
          'id_number' => id_number,
          'selfie_image' => selfie_image,
          'liveness_images' => liveness_images,
          'user_details' => coerce_user_details(user_details),
          'consent' => coerce_consent(consent),
          'callback_url' => resolve_callback(callback_url),
          'sandbox_result' => sandbox_result,
          'partner_params' => partner_params,
          'metadata' => metadata
        }.compact
        accepted(@client.call(:biometric_kyc, form: form, user_id_header: user_id, timeout: timeout))
      end
    end

    # POST /v3/registration, /v3/authentication, /v3/compare
    class Biometric < Base
      def enroll(selfie_image:, liveness_images:, consent:, user_details:,
                 allow_new_enroll: nil, callback_url: nil, sandbox_result: nil,
                 partner_params: nil, metadata: nil, user_id: nil, timeout: nil)
        form = {
          'selfie_image' => selfie_image,
          'liveness_images' => liveness_images,
          'user_details' => coerce_user_details(user_details),
          'consent' => coerce_consent(consent),
          'allow_new_enroll' => allow_new_enroll,
          'callback_url' => resolve_callback(callback_url),
          'sandbox_result' => sandbox_result,
          'partner_params' => partner_params,
          'metadata' => metadata
        }.compact
        accepted(@client.call(:registration, form: form, user_id_header: user_id, timeout: timeout))
      end

      # user_id goes in the BODY here (required), not the User-ID header.
      def authenticate(user_id:, consent:, user_details:, selfie_image: nil, liveness_images: nil,
                       use_enrolled_image: nil, callback_url: nil, sandbox_result: nil,
                       partner_params: nil, metadata: nil, timeout: nil)
        require_images!(use_enrolled_image, selfie_image, liveness_images)
        form = {
          'user_id' => user_id,
          'selfie_image' => selfie_image,
          'liveness_images' => liveness_images,
          'user_details' => coerce_user_details(user_details),
          'consent' => coerce_consent(consent),
          'use_enrolled_image' => use_enrolled_image,
          'callback_url' => resolve_callback(callback_url),
          'sandbox_result' => sandbox_result,
          'partner_params' => partner_params,
          'metadata' => metadata
        }.compact
        accepted(@client.call(:authentication, form: form, timeout: timeout))
      end

      # user_id is optional here, and goes in the BODY when present.
      def compare(selfie_image:, comparison_image:, comparison_image_type:, consent:, user_details:,
                  liveness_images: nil, allow_new_enroll: nil, user_id: nil, callback_url: nil,
                  sandbox_result: nil, partner_params: nil, metadata: nil, timeout: nil)
        form = {
          'selfie_image' => selfie_image,
          'comparison_image' => comparison_image,
          'comparison_image_type' => comparison_image_type,
          'liveness_images' => liveness_images,
          'user_details' => coerce_user_details(user_details),
          'consent' => coerce_consent(consent),
          'allow_new_enroll' => allow_new_enroll,
          'user_id' => user_id,
          'callback_url' => resolve_callback(callback_url),
          'sandbox_result' => sandbox_result,
          'partner_params' => partner_params,
          'metadata' => metadata
        }.compact
        accepted(@client.call(:compare, form: form, timeout: timeout))
      end

      private

      def require_images!(use_enrolled_image, selfie_image, liveness_images)
        return if use_enrolled_image == true
        return unless selfie_image.nil? || liveness_images.nil? || Array(liveness_images).empty?

        raise Errors::ValidationError.new(
          'selfie_image and liveness_images are required unless use_enrolled_image is true'
        )
      end
    end

    # GET /v3/status, POST /v3/replay, plus the wait_until_complete poll helper.
    class Verifications < Base
      def retrieve(job_id, timeout: nil)
        response = @client.call(:status, path_params: { 'job_id' => job_id }, timeout: timeout)
        Generated::Models::JobStatus.from(response.json)
      end

      def wait_until_complete(job_id, interval: 2, timeout: 60, treat_not_found_as_pending: true)
        deadline = monotonic + timeout
        loop do
          status = retrieve(job_id)
          return status if status.complete?
          return status if status.not_found? && !treat_not_found_as_pending

          if monotonic >= deadline
            raise Errors::TimeoutError.new(
              "wait_until_complete timed out after #{timeout}s waiting for #{job_id}"
            )
          end
          sleep_interval(interval)
        end
      end

      def replay(job_id, callback_url: nil, timeout: nil)
        json = callback_url ? { 'callback_url' => callback_url } : nil
        response = @client.call(:replay, path_params: { 'job_id' => job_id },
                                         json: json, timeout: timeout)
        Generated::Models::AcceptedStatusResponse.from(response.json)
      end

      private

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def sleep_interval(interval)
        sleep(interval)
      end
    end

    # POST /v3/users/{user_id}/report_fraud, plus flag/clear convenience wrappers.
    class Users < Base
      REASONS = %w[
        FIRST_PARTY_FRAUD SECOND_PARTY_FRAUD THIRD_PARTY_FRAUD SYNTHETIC_IDENTITY
        ACCOUNT_TAKEOVER DOCUMENT_FORGERY IDENTITY_FARMING MULE_ACCOUNT OTHER
      ].freeze

      def report_fraud(user_id, is_fraud:, reported_by:, reason: nil, notes: nil, timeout: nil)
        validate_fraud!(is_fraud, reason, notes)
        form = {
          'is_fraud' => is_fraud,
          'reported_by' => reported_by,
          'reason' => reason,
          'notes' => notes
        }.compact
        response = @client.call(:report_fraud, path_params: { 'user_id' => user_id },
                                               form: form, timeout: timeout)
        Generated::Models::AcceptedStatusResponse.from(response.json)
      end

      def flag_fraud(user_id, reason:, reported_by:, notes: nil, timeout: nil)
        report_fraud(user_id, is_fraud: true, reason: reason, notes: notes,
                              reported_by: reported_by, timeout: timeout)
      end

      def clear_fraud(user_id, notes:, reported_by:, timeout: nil)
        report_fraud(user_id, is_fraud: false, notes: notes, reported_by: reported_by, timeout: timeout)
      end

      private

      def validate_fraud!(is_fraud, reason, notes)
        if is_fraud
          raise Errors::ValidationError.new('reason is required when is_fraud is true') if reason.to_s.empty?
          unless REASONS.include?(reason.to_s)
            raise Errors::ValidationError.new("reason must be one of #{REASONS.join(', ')}")
          end
          if reason.to_s == 'OTHER' && notes.to_s.empty?
            raise Errors::ValidationError.new('notes is required when reason is OTHER')
          end
        elsif notes.to_s.empty?
          raise Errors::ValidationError.new('notes is required when is_fraud is false')
        end
      end
    end

    # GET /v3/services/*
    class Services < Base
      def bank_codes(country: nil, timeout: nil)
        response = @client.call(:bank_codes, query: { 'country' => country }.compact, timeout: timeout)
        Generated::Models::BankCodesResponse.from(response.json)
      end

      def supported_id_types(country: nil, timeout: nil)
        response = @client.call(:supported_id_types, query: { 'country' => country }.compact,
                                                     timeout: timeout)
        Generated::Models::SupportedIdTypesResponse.from(response.json)
      end

      def supported_documents(continent: nil, country_code: nil, locale: nil, timeout: nil)
        query = { 'continent' => continent, 'country_code' => country_code, 'locale' => locale }.compact
        response = @client.call(:supported_documents, query: query, timeout: timeout)
        Generated::Models::SupportedDocumentsResponse.from(response.json)
      end

      def id_status(country:, id_type:, timeout: nil)
        query = { 'country' => country, 'id_type' => id_type }
        response = @client.call(:id_status, query: query, timeout: timeout)
        Generated::Models::IdStatusResponse.from(response.json)
      end
    end
  end
end
