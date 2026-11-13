# frozen_string_literal: true

module SmileID
  module Generated
    # Wire response models (spec section 5.2). Field names mirror the wire
    # verbatim. These live under generated/ because a generator would own them
    # later; the hand-written client and helpers must survive regeneration.
    module Models
      # Response from the seven entry endpoints (HTTP 202). The `status` value
      # differs by endpoint ("Accepted" or "accepted"); use #accepted? rather
      # than branching on raw casing.
      class AcceptedResponse
        attr_reader :status, :message, :job_id, :user_id, :created_at, :raw

        def initialize(status:, message: nil, job_id: nil, user_id: nil, created_at: nil, raw: nil)
          @status = status
          @message = message
          @job_id = job_id
          @user_id = user_id
          @created_at = created_at
          @raw = raw
        end

        # Normalized accessor — true when status is "accepted" in any casing.
        def accepted?
          status.to_s.downcase == 'accepted'
        end

        def self.from(hash)
          new(
            status: hash['status'],
            message: hash['message'],
            job_id: hash['job_id'],
            user_id: hash['user_id'],
            created_at: hash['created_at'],
            raw: hash
          )
        end
      end

      # Response from GET /v3/status (spec section 5.2, 6.8). `status` is
      # `processing` while the job runs, `not_found` for a job the API does not
      # know, and otherwise the terminal decision itself: `clear`, `block`,
      # `attention` or `error`. `message` carries no sub-state.
      class JobStatus
        attr_reader :status, :job_id, :user_id, :message, :raw

        def initialize(status:, job_id: nil, user_id: nil, message: nil, raw: nil)
          @status = status
          @job_id = job_id
          @user_id = user_id
          @message = message
          @raw = raw
        end

        # Terminal when the job is neither still running nor unknown — the
        # status is then the decision (clear/block/attention/error).
        def complete?
          return false if status.to_s.empty?

          !processing? && !not_found?
        end

        def processing?
          status.to_s == 'processing'
        end

        def not_found?
          status.to_s == 'not_found'
        end

        def self.from(hash)
          new(
            status: hash['status'],
            job_id: hash['job_id'],
            user_id: hash['user_id'],
            message: hash['message'],
            raw: hash
          )
        end
      end

      # Wraps the accepted-shaped responses from replay and report_fraud.
      class AcceptedStatusResponse
        attr_reader :status, :message, :job_id, :user_id, :raw

        def initialize(status:, message: nil, job_id: nil, user_id: nil, raw: nil)
          @status = status
          @message = message
          @job_id = job_id
          @user_id = user_id
          @raw = raw
        end

        def accepted?
          status.to_s.downcase == 'accepted'
        end

        def self.from(hash)
          new(
            status: hash['status'],
            message: hash['message'],
            job_id: hash['job_id'],
            user_id: hash['user_id'],
            raw: hash
          )
        end
      end

      # Result of a One-Time AML screening: the body of POST /v3/aml/sync, which
      # is the payload the async callback would have delivered. `status` is
      # `clear`, `block`, `attention` or `error`. The response headers are kept
      # alongside the body: the job and user ids, and the signature and
      # timestamp that webhook verification code can check unchanged.
      class OneTimeAmlResult
        attr_reader :status, :message, :reason, :created_at, :completed_at, :product,
                    :partner_params, :kyc_receipt, :strict_match, :no_of_persons_found,
                    :people, :user_provided_info, :consent, :antifraud, :device_signals,
                    :job_id, :user_id, :response_signature, :response_timestamp, :raw

        def initialize(hash, headers = {})
          @status = hash['status']
          @message = hash['message']
          @reason = hash['reason']
          @created_at = hash['created_at']
          @completed_at = hash['completed_at']
          @product = hash['product']
          @partner_params = hash['partner_params']
          @kyc_receipt = hash['kyc_receipt']
          @strict_match = hash['strict_match']
          @no_of_persons_found = hash['no_of_persons_found']
          @people = hash['people'] || []
          @user_provided_info = hash['user_provided_info']
          @consent = hash['consent']
          @antifraud = hash['antifraud']
          @device_signals = hash['device_signals']
          @job_id = headers['smileid-job-id']
          @user_id = headers['user-id']
          @response_signature = headers['response-signature']
          @response_timestamp = headers['response-timestamp']
          @raw = hash
        end

        def self.from(hash, headers = {})
          new(hash, headers)
        end
      end

      # One article in an AML Monitoring news response.
      class AmlMonitoringNewsItem
        attr_reader :body, :published_date, :publisher, :publisher_country_code,
                    :title, :url, :raw

        def initialize(hash)
          @body = hash['body']
          @published_date = hash['published_date']
          @publisher = hash['publisher']
          @publisher_country_code = hash['publisher_country_code']
          @title = hash['title']
          @url = hash['url']
          @raw = hash
        end

        def self.from(hash)
          new(hash)
        end
      end

      # Response from GET /v3/aml/monitoring/{job_id}/news/{reference}. `meta`
      # is a plain hash with string keys (`current_page`, `limit`,
      # `total_count`); `news` holds AmlMonitoringNewsItem objects.
      class AmlMonitoringNewsResponse
        attr_reader :job_id, :product, :user_id, :meta, :news, :raw

        def initialize(hash)
          @job_id = hash['job_id']
          @product = hash['product']
          @user_id = hash['user_id']
          @meta = hash['meta']
          @news = (hash['news'] || []).map { |item| AmlMonitoringNewsItem.from(item) }
          @raw = hash
        end

        def self.from(hash)
          new(hash)
        end
      end

      # Service responses (spec section 5.2). Nested collections are exposed as
      # plain hashes with string keys, exactly as they arrive on the wire.
      class BankCodesResponse
        attr_reader :bank_codes, :raw

        def initialize(bank_codes:, raw: nil)
          @bank_codes = bank_codes
          @raw = raw
        end

        def self.from(hash)
          new(bank_codes: hash['bank_codes'] || [], raw: hash)
        end
      end

      class SupportedIdTypesResponse
        attr_reader :id_types, :raw

        def initialize(id_types:, raw: nil)
          @id_types = id_types
          @raw = raw
        end

        def self.from(hash)
          new(id_types: hash['id_types'] || [], raw: hash)
        end
      end

      class SupportedDocumentsResponse
        attr_reader :valid_documents, :raw

        def initialize(valid_documents:, raw: nil)
          @valid_documents = valid_documents
          @raw = raw
        end

        def self.from(hash)
          new(valid_documents: hash['valid_documents'] || [], raw: hash)
        end
      end

      class IdStatusResponse
        attr_reader :last_checked, :last_check_status, :last_hour_success_rate,
                    :last_known_status, :last_check_success_rate, :raw

        def initialize(hash)
          @last_checked = hash['last_checked']
          @last_check_status = hash['last_check_status']
          @last_hour_success_rate = hash['last_hour_success_rate']
          @last_known_status = hash['last_known_status']
          @last_check_success_rate = hash['last_check_success_rate']
          @raw = hash
        end

        def self.from(hash)
          new(hash)
        end
      end
    end
  end
end
