class InspectionPhoto < ApplicationRecord
  ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/gif image/webp image/heic image/heif].freeze
  MAX_ANNOTATION_BYTES = 200.kilobytes
  HEIC_BRANDS = %w[heic heix hevc hevx heim heis mif1 msf1].freeze

  belongs_to :inspection
  belongs_to :inspection_response, optional: true
  has_one_attached :original_image
  has_one_attached :annotated_image

  validates :original_image, presence: true
  validate :images_are_acceptable
  validate :annotation_data_is_a_json_object

  def self.max_image_bytes
    ENV.fetch("PHOTO_MAX_MB", 15).to_f.megabytes.to_i
  end

  # Image links are signed and stop working after this long; every response
  # carries fresh ones.
  def self.url_ttl
    ENV.fetch("PHOTO_URL_TTL_MINUTES", 60).to_i.minutes
  end

  # Checks the first bytes of the data instead of trusting the file name or the
  # declared type, so text or markup cannot pass as a picture.
  def self.image_signature?(io)
    head = io.read(16).to_s.b
    io.rewind
    head.start_with?("\xFF\xD8\xFF".b, "\x89PNG\r\n\x1A\n".b, "GIF87a".b, "GIF89a".b) ||
      (head.start_with?("RIFF".b) && head[8, 4] == "WEBP".b) ||
      (head[4, 4] == "ftyp".b && HEIC_BRANDS.include?(head[8, 4].to_s))
  end

  def as_api_json
    {
      id: id,
      inspection_response_id: inspection_response_id,
      annotation_data: annotation_data,
      comment: comment,
      original_image_url: signed_path(original_image),
      annotated_image_url: signed_path(annotated_image)
    }
  end

  private

  def signed_path(attachment)
    return nil unless attachment.attached?

    blob = attachment.blob
    Rails.application.routes.url_helpers.rails_service_blob_path(blob.signed_id(expires_in: self.class.url_ttl), blob.filename)
  end

  def images_are_acceptable
    { original_image: original_image, annotated_image: annotated_image }.each do |name, attachment|
      change = attachment_changes[name.to_s]
      next unless change && attachment.attached?

      blob = attachment.blob
      attachable = change.attachable
      if !ALLOWED_CONTENT_TYPES.include?(blob.content_type) || (attachable.respond_to?(:read) && !self.class.image_signature?(attachable))
        errors.add(name, "must be a JPEG, PNG, GIF, WebP or HEIC image")
      elsif blob.byte_size > self.class.max_image_bytes
        errors.add(name, "is too large (maximum #{ActiveSupport::NumberHelper.number_to_human_size(self.class.max_image_bytes)})")
      end
    end
  end

  def annotation_data_is_a_json_object
    return if annotation_data.blank?

    if annotation_data.bytesize > MAX_ANNOTATION_BYTES
      errors.add(:annotation_data, "is too large")
    elsif !JSON.parse(annotation_data).is_a?(Hash)
      errors.add(:annotation_data, "must be a JSON object")
    end
  rescue JSON::ParserError
    errors.add(:annotation_data, "must be valid JSON")
  end
end
