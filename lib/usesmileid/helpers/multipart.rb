# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'faraday'
require 'faraday/multipart'

module SmileID
  module Helpers
    # Hand-assembles multipart/form-data bodies to guarantee the exact wire shape
    # required by spec section 5.3:
    #   - repeated `liveness_images` parts (one per image, never CSV/indexed),
    #   - object/array fields as JSON parts with Content-Type: application/json,
    #   - single binary parts with a filename and content type,
    #   - scalar fields as plain text parts.
    #
    # Faraday's multipart middleware indexes array parts as `liveness_images[0]`,
    # so the body is built here rather than delegated to it (spec section 5.3
    # item 4, the OpenAPI-Generator bug to avoid).
    module Multipart
      # Fields serialized as JSON parts.
      JSON_PART_FIELDS = %w[consent user_details partner_params metadata].freeze
      # Single binary fields.
      BINARY_FIELDS = %w[selfie_image document document_back comparison_image].freeze
      # Repeated binary fields.
      BINARY_ARRAY_FIELDS = %w[liveness_images].freeze

      DEFAULT_CONTENT_TYPES = {
        'selfie_image' => 'image/jpeg',
        'document' => 'image/jpeg',
        'document_back' => 'image/jpeg',
        'comparison_image' => 'image/jpeg',
        'liveness_images' => 'image/jpeg'
      }.freeze

      # Only document and document_back may be PNG (spec section 5.3 rule 3);
      # selfie, liveness and comparison images are always image/jpeg.
      PNG_CAPABLE_FIELDS = %w[document document_back].freeze
      PNG_MAGIC = "\x89PNG".b.freeze

      # RFC 6838 type/subtype tokens — anything else is rejected before send.
      MEDIA_TYPE = %r{\A[A-Za-z0-9!\#$&^_.+-]+/[A-Za-z0-9!\#$&^_.+-]+\z}

      DEFAULT_FILENAMES = {
        'selfie_image' => 'selfie.jpg',
        'document' => 'document.jpg',
        'document_back' => 'document_back.jpg',
        'comparison_image' => 'comparison.jpg'
      }.freeze

      CRLF = "\r\n"

      module_function

      # Build a multipart body from an ordered field hash.
      #
      # @return [Array(String, String)] content-type header value and body bytes.
      def build(form, boundary: default_boundary)
        body = +''.b
        form.each do |name, value|
          next if value.nil?

          field = name.to_s
          append_field(body, field, value, boundary)
        end
        body << "--#{boundary}--#{CRLF}".b
        ["multipart/form-data; boundary=#{boundary}", body]
      end

      def default_boundary
        "----smileid#{SecureRandom.hex(16)}"
      end

      def append_field(body, field, value, boundary)
        if BINARY_ARRAY_FIELDS.include?(field)
          Array(value).each_with_index do |img, index|
            body << binary_part(field, img, boundary, index: index)
          end
        elsif BINARY_FIELDS.include?(field)
          body << binary_part(field, value, boundary)
        elsif JSON_PART_FIELDS.include?(field)
          body << json_part(field, value, boundary)
        else
          body << text_part(field, scalar_string(value), boundary)
        end
      end

      def text_part(name, value, boundary)
        part = "--#{boundary}#{CRLF}"
        part << "Content-Disposition: form-data; name=\"#{name}\"#{CRLF}#{CRLF}"
        part << value.to_s
        part << CRLF
        part.b
      end

      def json_part(name, value, boundary)
        part = "--#{boundary}#{CRLF}"
        part << "Content-Disposition: form-data; name=\"#{name}\"#{CRLF}"
        part << "Content-Type: application/json#{CRLF}#{CRLF}"
        part << JSON.generate(value)
        part << CRLF
        part.b
      end

      def binary_part(name, input, boundary, index: nil)
        upload = coerce_binary(name, input, index: index)
        # Sanitization runs here so it covers EVERY input path — FilePart,
        # hash, path, raw bytes, IO — including explicit content types.
        filename = sanitize_filename(upload[:filename])
        content_type = validate_content_type!(upload[:content_type])
        header = "--#{boundary}#{CRLF}"
        header << 'Content-Disposition: form-data; ' \
                  "name=\"#{name}\"; filename=\"#{filename}\"#{CRLF}"
        header << "Content-Type: #{content_type}#{CRLF}#{CRLF}"
        (header.b + upload[:bytes].b + CRLF.b)
      end

      # Strip header-injection vectors from filenames: CR, LF and other
      # control characters are removed; double quotes are percent-encoded so
      # they cannot terminate the quoted filename attribute.
      def sanitize_filename(filename)
        filename.to_s.gsub(/[\x00-\x1f\x7f]/, '').gsub('"', '%22')
      end

      # Content types must be a plain media type token pair; anything else
      # (including CR/LF injection) fails validation before send.
      def validate_content_type!(content_type)
        value = content_type.to_s
        return value if value.match?(MEDIA_TYPE)

        raise Errors::ValidationError.new('content_type must be a valid media type')
      end

      # Coerce a binary input (path, bytes, IO, Hash, or Faraday FilePart) into
      # { bytes:, filename:, content_type: }. An explicitly provided content
      # type wins; otherwise the field's default applies, with PNG detection
      # for the document fields only.
      def coerce_binary(field, input, index: nil)
        default_fn = filename_for(field, index)

        upload =
          case input
          when Faraday::Multipart::FilePart
            from_file_part(input, default_fn)
          when Hash
            from_hash(input, default_fn)
          when String
            from_string(input, default_fn)
          else
            unless input.respond_to?(:read)
              raise Errors::ValidationError.new("#{field} must be a file path, bytes, IO, or FilePart")
            end

            from_io(input, default_fn)
          end

        resolve_content_type(field, upload)
      end

      def resolve_content_type(field, upload)
        return upload if upload[:content_type]

        default = DEFAULT_CONTENT_TYPES[field] || 'application/octet-stream'
        if PNG_CAPABLE_FIELDS.include?(field) && png?(upload)
          upload[:content_type] = 'image/png'
          if upload[:filename] == DEFAULT_FILENAMES[field]
            upload[:filename] = upload[:filename].sub(/\.jpg\z/, '.png')
          end
        else
          upload[:content_type] = default
        end
        upload
      end

      def png?(upload)
        upload[:filename].to_s.downcase.end_with?('.png') ||
          upload[:bytes].to_s.b.start_with?(PNG_MAGIC)
      end

      def filename_for(field, index)
        return DEFAULT_FILENAMES[field] if DEFAULT_FILENAMES.key?(field)

        "#{field}_#{(index || 0) + 1}.jpg"
      end

      def from_file_part(part, default_fn)
        io = part.instance_variable_get(:@io)
        local_path = part.instance_variable_get(:@local_path)
        bytes = io ? read_all(io) : File.binread(local_path)
        {
          bytes: bytes,
          filename: part.original_filename || default_fn,
          content_type: part.content_type
        }
      end

      def from_hash(hash, default_fn)
        h = hash.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
        bytes =
          if h[:bytes]
            h[:bytes]
          elsif h[:path]
            File.binread(h[:path])
          elsif h[:io]
            read_all(h[:io])
          else
            raise Errors::ValidationError.new('binary hash needs one of :bytes, :path, or :io')
          end
        {
          bytes: bytes,
          filename: h[:filename] || (h[:path] ? File.basename(h[:path]) : default_fn),
          content_type: h[:content_type]
        }
      end

      def from_string(str, default_fn)
        if plausible_path?(str) && File.exist?(str)
          { bytes: File.binread(str), filename: File.basename(str), content_type: nil }
        else
          { bytes: str, filename: default_fn, content_type: nil }
        end
      end

      # Raw image bytes routinely contain null bytes or invalid UTF-8, which
      # File.exist? rejects with ArgumentError. Only probe the filesystem for
      # strings that could plausibly be paths.
      def plausible_path?(str)
        str.length < 4096 && str.valid_encoding? && !str.include?("\0")
      end

      def from_io(io, default_fn)
        filename = io.respond_to?(:path) && io.path ? File.basename(io.path) : default_fn
        { bytes: read_all(io), filename: filename, content_type: nil }
      end

      def read_all(io)
        io.rewind if io.respond_to?(:rewind)
        io.read
      end

      def scalar_string(value)
        case value
        when true then 'true'
        when false then 'false'
        else value.to_s
        end
      end
    end
  end
end
