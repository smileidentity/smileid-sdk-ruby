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
      # Per-request callback URLs must be https (fleet standard); validated
      # before any request is made. The default was validated at construction.
      def resolve_callback(callback_url)
        Config.validate_callback_url!(callback_url) if callback_url
        callback_url || @client.config.default_callback_url
      end

      def require_images!(selfie_image, liveness_images, condition = nil)
        return unless selfie_image.nil? || liveness_images.nil? || Array(liveness_images).empty?

        message = ['selfie_image and liveness_images are required', condition].compact.join(' ')
        raise Errors::ValidationError.new(message)
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

    # POST /v3/document_verification, /v3/enhanced_document_verification and
    # /v3/residency_document_verification
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

      # POST /v3/residency_document_verification. The document is a passport
      # and the visa endorsed in it is read as well, so id_type defaults to, and must be, PASSPORT.
      def verify_residency(selfie_image:, liveness_images:, document:, visa:, consent:,
                           country:, user_details:, id_type: 'PASSPORT', document_back: nil,
                           callback_url: nil, partner_params: nil, metadata: nil, user_id: nil, timeout: nil)
        id_type = 'PASSPORT' if id_type.to_s.empty?
        unless id_type.to_s == 'PASSPORT'
          raise Errors::ValidationError.new('id_type must be PASSPORT for residency document verification')
        end
        if visa.nil? || (visa.respond_to?(:empty?) && visa.empty?)
          raise Errors::ValidationError.new('visa is required for residency document verification')
        end

        form = document_form(
          selfie_image: selfie_image, liveness_images: liveness_images, document: document,
          document_back: document_back, consent: consent, country: country, id_type: id_type,
          user_details: user_details, callback_url: callback_url,
          partner_params: partner_params, metadata: metadata
        ).merge('visa' => visa)
        accepted(@client.call(:residency_document_verification, form: form,
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
      # With use_enrolled_image: true the job verifies against user_id's enrolled
      # selfie, so the images may be omitted. The grant is bound into this job's
      # token, never sent in the body.
      def verify(consent:, country:, id_type:, id_number:, user_details:,
                 selfie_image: nil, liveness_images: nil, use_enrolled_image: false,
                 callback_url: nil, sandbox_result: nil,
                 partner_params: nil, metadata: nil, user_id: nil, timeout: nil)
        unless [true, false].include?(use_enrolled_image)
          raise Errors::ValidationError.new('use_enrolled_image must be true or false')
        end

        if use_enrolled_image
          if user_id.to_s.strip.empty?
            raise Errors::ValidationError.new('user_id is required when use_enrolled_image is true')
          end
        else
          require_images!(selfie_image, liveness_images, 'unless use_enrolled_image is true')
        end
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
        accepted(@client.call(:biometric_kyc, form: form, user_id_header: user_id, timeout: timeout,
                                              use_enrolled_image: use_enrolled_image))
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
      def authenticate(user_id:, consent:, user_details:, selfie_image:, liveness_images:,
                       callback_url: nil, sandbox_result: nil,
                       partner_params: nil, metadata: nil, timeout: nil)
        require_images!(selfie_image, liveness_images)
        form = {
          'user_id' => user_id,
          'selfie_image' => selfie_image,
          'liveness_images' => liveness_images,
          'user_details' => coerce_user_details(user_details),
          'consent' => coerce_consent(consent),
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
    end

    # POST /v3/aml and /v3/aml/sync
    class Aml < Base
      # Queues a One-Time AML screening. The result arrives on callback_url.
      def submit(countries:, full_name:, user_details:, consent:, birth_year: nil,
                 strict_match: nil, aliases: nil, search_existing_user: nil,
                 callback_url: nil, partner_params: nil, metadata: nil, user_id: nil, timeout: nil)
        form = aml_form(
          countries: countries, full_name: full_name, user_details: user_details,
          consent: consent, birth_year: birth_year, strict_match: strict_match,
          aliases: aliases, search_existing_user: search_existing_user,
          callback_url: resolve_callback(callback_url), partner_params: partner_params,
          metadata: metadata, user_id: user_id
        )
        accepted(@client.call(:one_time_aml, form: form, user_id_header: user_id, timeout: timeout))
      end

      # Runs the same screening and returns the terminal result in the response.
      # callback_url is optional: no callback is sent, but a given one is kept
      # for replay. Send the same idempotency_key on a retry to get the original
      # result instead of a second, billed screening. A provider timeout raises
      # SmileIDError with status_code 408; nothing is billed.
      def submit_sync(countries:, full_name:, user_details:, consent:, birth_year: nil,
                      strict_match: nil, aliases: nil, search_existing_user: nil,
                      callback_url: nil, partner_params: nil, metadata: nil, user_id: nil,
                      idempotency_key: nil, timeout: nil)
        Config.validate_callback_url!(callback_url) if callback_url
        form = aml_form(
          countries: countries, full_name: full_name, user_details: user_details,
          consent: consent, birth_year: birth_year, strict_match: strict_match,
          aliases: aliases, search_existing_user: search_existing_user,
          callback_url: callback_url, partner_params: partner_params,
          metadata: metadata, user_id: user_id
        )
        extra_headers = idempotency_key ? { 'SmileID-Idempotency-Key' => idempotency_key } : nil
        response = @client.call(:one_time_aml_sync, form: form, user_id_header: user_id,
                                                    timeout: timeout, extra_headers: extra_headers)
        Generated::Models::OneTimeAmlResult.from(response.json, response.headers)
      end

      private

      def aml_form(countries:, full_name:, user_details:, consent:, birth_year:, strict_match:,
                   aliases:, search_existing_user:, callback_url:, partner_params:, metadata:, user_id:)
        {
          'countries' => countries,
          'full_name' => full_name,
          'birth_year' => birth_year,
          'strict_match' => strict_match,
          'aliases' => aliases,
          'search_existing_user' => search_existing_user,
          'user_id' => user_id,
          'user_details' => coerce_user_details(user_details),
          'consent' => coerce_consent(consent),
          'callback_url' => callback_url,
          'partner_params' => partner_params,
          'metadata' => metadata
        }.compact
      end
    end

    # POST /v3/aml/monitoring and GET /v3/aml/monitoring/{job_id}/news/{reference}
    class AmlMonitoring < Base
      NEWS_CATEGORIES = %w[
        arms_trafficking credit_update environmental_crime financial_crime
        human_rights_violation leadership_change legal_risk location_change narcotics
        other other_crime ownership_change product_change regulatory sexual_crime
        technology_event terrorism violent_crime
      ].freeze

      # full_name is required unless search_existing_user is true, which takes
      # the name from the user's earlier KYC record and needs user_id.
      def submit(countries:, user_details:, consent:, full_name: nil, birth_year: nil,
                 strict_match: nil, aliases: nil, search_existing_user: nil,
                 callback_url: nil, partner_params: nil, metadata: nil, user_id: nil, timeout: nil)
        form = {
          'countries' => countries,
          'full_name' => full_name,
          'birth_year' => birth_year,
          'strict_match' => strict_match,
          'aliases' => aliases,
          'search_existing_user' => search_existing_user,
          'user_id' => user_id,
          'user_details' => coerce_user_details(user_details),
          'consent' => coerce_consent(consent),
          'callback_url' => resolve_callback(callback_url),
          'partner_params' => partner_params,
          'metadata' => metadata
        }.compact
        accepted(@client.call(:aml_monitoring, form: form, user_id_header: user_id, timeout: timeout))
      end

      def news(job_id, reference, news_category:, page: nil, limit: nil, timeout: nil)
        unless NEWS_CATEGORIES.include?(news_category.to_s)
          raise Errors::ValidationError.new("news_category must be one of #{NEWS_CATEGORIES.join(', ')}")
        end

        query = { 'news_category' => news_category, 'page' => page, 'limit' => limit }.compact
        response = @client.call(:aml_monitoring_news,
                                path_params: { 'job_id' => job_id, 'reference' => reference },
                                query: query, timeout: timeout)
        Generated::Models::AmlMonitoringNewsResponse.from(response.json)
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

      # The optional callback_url override goes in a multipart body (any other
      # content type gets a 415 from the backend); no override, no body.
      def replay(job_id, callback_url: nil, timeout: nil)
        Config.validate_callback_url!(callback_url) if callback_url
        form = callback_url ? { 'callback_url' => callback_url } : nil
        response = @client.call(:replay, path_params: { 'job_id' => job_id },
                                         form: form, timeout: timeout)
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
