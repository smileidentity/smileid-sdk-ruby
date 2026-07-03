# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

# Matrix item 1: golden-fixture multipart serialization (spec section 5.3, 6).
RSpec.describe SmileID::Helpers::Multipart do
  let(:boundary) { '----B' }

  def build(form)
    _content_type, body = described_class.build(form, boundary: boundary)
    body.force_encoding('UTF-8')
  end

  it 'returns a content type carrying the boundary' do
    content_type, = described_class.build({ 'country' => 'NG' }, boundary: boundary)
    expect(content_type).to eq('multipart/form-data; boundary=----B')
  end

  it 'serializes scalar fields as plain text parts with no content type' do
    body = build('country' => 'NG')
    expect(body).to include("--#{boundary}\r\n")
    expect(body).to include("Content-Disposition: form-data; name=\"country\"\r\n\r\nNG\r\n")
    expect(body).not_to include('Content-Type: text/plain')
  end

  it 'serializes booleans as the strings true/false' do
    expect(build('is_fraud' => true)).to include("name=\"is_fraud\"\r\n\r\ntrue\r\n")
    expect(build('is_fraud' => false)).to include("name=\"is_fraud\"\r\n\r\nfalse\r\n")
  end

  it 'serializes object fields as JSON parts with application/json content type' do
    body = build('user_details' => { 'given_names' => 'John', 'last_name' => 'Doe' })
    expect(body).to include(
      "Content-Disposition: form-data; name=\"user_details\"\r\n" \
      "Content-Type: application/json\r\n\r\n" \
      "{\"given_names\":\"John\",\"last_name\":\"Doe\"}\r\n"
    )
  end

  it 'serializes consent as a JSON part' do
    body = build('consent' => SmileID::Consent.coerce(valid_consent))
    expect(body).to include("name=\"consent\"\r\nContent-Type: application/json\r\n")
    expect(body).to include('"granted":true')
  end

  it 'emits repeated liveness_images parts, never indexed or CSV-joined' do
    body = build('liveness_images' => %w[img-one img-two img-three])
    part_count = body.scan('name="liveness_images"').length
    expect(part_count).to eq(3)
    expect(body).not_to include('liveness_images[')
    expect(body).not_to include('liveness_images[0]')
    expect(body.scan('Content-Type: image/jpeg').length).to eq(3)
    expect(body).to include('filename="liveness_images_1.jpg"')
    expect(body).to include('filename="liveness_images_3.jpg"')
  end

  it 'serializes a single binary field with a filename and content type' do
    body = build('selfie_image' => 'selfie-bytes')
    expect(body).to include(
      "Content-Disposition: form-data; name=\"selfie_image\"; filename=\"selfie.jpg\"\r\n" \
      "Content-Type: image/jpeg\r\n\r\nselfie-bytes\r\n"
    )
  end

  it 'honours an explicit content type and filename for documents' do
    body = build('document' => { bytes: 'png-bytes', filename: 'front.png', content_type: 'image/png' })
    expect(body).to include('filename="front.png"')
    expect(body).to include('Content-Type: image/png')
  end

  it 'accepts raw binary bytes containing null bytes without probing the filesystem' do
    jpeg_bytes = "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01".b + Random.bytes(64)
    body = described_class.build({ 'selfie_image' => jpeg_bytes }, boundary: boundary)[1]
    expect(body.b).to include(jpeg_bytes)
    expect(body.b).to include('filename="selfie.jpg"'.b)
    expect(body.b).to include('Content-Type: image/jpeg'.b)
  end

  it 'detects PNG for document fields by magic bytes' do
    png_bytes = "\x89PNG\r\n\x1a\n".b + Random.bytes(32)
    body = described_class.build({ 'document' => png_bytes,
                                   'document_back' => png_bytes }, boundary: boundary)[1]
    expect(body.b.scan('Content-Type: image/png'.b).length).to eq(2)
    expect(body.b).to include('filename="document.png"'.b)
    expect(body.b).to include('filename="document_back.png"'.b)
  end

  it 'detects PNG for document fields by file extension' do
    Tempfile.create(['front', '.png']) do |file|
      file.binmode
      file.write("\x89PNG\r\n\x1a\nfake".b)
      file.flush
      body = build('document' => file.path)
      expect(body).to include('Content-Type: image/png')
      expect(body).to include("filename=\"#{File.basename(file.path)}\"")
    end
  end

  it 'never applies PNG detection to selfie, liveness or comparison images' do
    png_bytes = "\x89PNG\r\n\x1a\n".b + Random.bytes(32)
    body = described_class.build(
      { 'selfie_image' => png_bytes, 'comparison_image' => png_bytes,
        'liveness_images' => [png_bytes, png_bytes] },
      boundary: boundary
    )[1]
    expect(body.b.scan('Content-Type: image/jpeg'.b).length).to eq(4)
    expect(body.b).not_to include('Content-Type: image/png'.b)
  end

  it 'omits nil fields entirely' do
    body = build('country' => 'NG', 'id_type' => nil)
    expect(body).not_to include('id_type')
  end

  it 'closes the body with the final boundary' do
    body = build('country' => 'NG')
    expect(body).to end_with("--#{boundary}--\r\n")
  end

  it 'accepts a Faraday multipart FilePart and reads its bytes and metadata' do
    require 'faraday/multipart'
    part = Faraday::Multipart::FilePart.new(StringIO.new('doc-bytes'), 'image/png', 'scan.png')
    body = build('document' => part)
    expect(body).to include('filename="scan.png"')
    expect(body).to include('Content-Type: image/png')
    expect(body).to include('doc-bytes')
  end

  it 'rejects filenames that could inject multipart headers' do
    expect do
      build('document' => { bytes: 'doc', filename: "front.jpg\"\r\nX-Injected: yes" })
    end.to raise_error(SmileID::Errors::ValidationError, /filename/)
  end

  it 'rejects unsafe explicit content types' do
    expect do
      build('document' => { bytes: 'doc', filename: 'front.jpg', content_type: "image/jpeg\r\nX: y" })
    end.to raise_error(SmileID::Errors::ValidationError, /content_type/)
  end
end
