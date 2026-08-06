# frozen_string_literal: true

module SmileID
  module Generated
    # Per-operation descriptors (spec section 6). One entry per HTTP operation.
    # A generator would own this table later; the hand-written transport reads it
    # to route auth, headers, body kind, and retry behaviour.
    module Operations
      Operation = Struct.new(
        :http_method,     # :get / :post
        :path,            # path template, e.g. "/v3/status/{job_id}"
        :authenticated,   # attach SmileID-Token?
        :partner_id_header, # attach SmileID-Partner-ID?
        :body_kind,       # :multipart / :json / nil
        :idempotent,      # safe to auto-retry? (GETs + token only)
        :success_statuses, # statuses treated as success (not raised)
        keyword_init: true
      )

      OPS = {
        enhanced_kyc: Operation.new(
          http_method: :post, path: '/v3/enhanced_kyc', authenticated: true,
          partner_id_header: false, body_kind: :multipart, idempotent: false,
          success_statuses: [202]
        ),
        document_verification: Operation.new(
          http_method: :post, path: '/v3/document_verification', authenticated: true,
          partner_id_header: true, body_kind: :multipart, idempotent: false,
          success_statuses: [202]
        ),
        enhanced_document_verification: Operation.new(
          http_method: :post, path: '/v3/enhanced_document_verification', authenticated: true,
          partner_id_header: true, body_kind: :multipart, idempotent: false,
          success_statuses: [202]
        ),
        biometric_kyc: Operation.new(
          http_method: :post, path: '/v3/biometric_kyc', authenticated: true,
          partner_id_header: true, body_kind: :multipart, idempotent: false,
          success_statuses: [202]
        ),
        registration: Operation.new(
          http_method: :post, path: '/v3/registration', authenticated: true,
          partner_id_header: false, body_kind: :multipart, idempotent: false,
          success_statuses: [202]
        ),
        authentication: Operation.new(
          http_method: :post, path: '/v3/authentication', authenticated: true,
          partner_id_header: false, body_kind: :multipart, idempotent: false,
          success_statuses: [202]
        ),
        compare: Operation.new(
          http_method: :post, path: '/v3/compare', authenticated: true,
          partner_id_header: false, body_kind: :multipart, idempotent: false,
          success_statuses: [202]
        ),
        status: Operation.new(
          http_method: :get, path: '/v3/status/{job_id}', authenticated: true,
          partner_id_header: false, body_kind: nil, idempotent: true,
          success_statuses: [200, 202, 404]
        ),
        replay: Operation.new(
          http_method: :post, path: '/v3/replay/{job_id}', authenticated: true,
          partner_id_header: false, body_kind: :multipart, idempotent: false,
          success_statuses: [202]
        ),
        report_fraud: Operation.new(
          http_method: :post, path: '/v3/users/{user_id}/report_fraud', authenticated: true,
          partner_id_header: false, body_kind: :multipart, idempotent: false,
          success_statuses: [202]
        ),
        bank_codes: Operation.new(
          http_method: :get, path: '/v3/services/bank_codes', authenticated: false,
          partner_id_header: false, body_kind: nil, idempotent: true,
          success_statuses: [200]
        ),
        supported_id_types: Operation.new(
          http_method: :get, path: '/v3/services/supported_id_types', authenticated: false,
          partner_id_header: false, body_kind: nil, idempotent: true,
          success_statuses: [200]
        ),
        supported_documents: Operation.new(
          http_method: :get, path: '/v3/services/supported_documents', authenticated: false,
          partner_id_header: false, body_kind: nil, idempotent: true,
          success_statuses: [200]
        ),
        id_status: Operation.new(
          http_method: :get, path: '/v3/services/id_status', authenticated: true,
          partner_id_header: false, body_kind: nil, idempotent: true,
          success_statuses: [200]
        )
      }.freeze

      def self.fetch(name)
        OPS.fetch(name)
      end
    end
  end
end
