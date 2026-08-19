class InspectionPhoto < ApplicationRecord
  belongs_to :inspection
  belongs_to :inspection_response, optional: true
  has_one_attached :original_image
  has_one_attached :annotated_image

  validates :original_image, presence: true

  def as_api_json
    {
      id: id,
      inspection_response_id: inspection_response_id,
      annotation_data: annotation_data,
      comment: comment,
      original_image_url: original_image.attached? ? Rails.application.routes.url_helpers.rails_blob_path(original_image, only_path: true) : nil,
      annotated_image_url: annotated_image.attached? ? Rails.application.routes.url_helpers.rails_blob_path(annotated_image, only_path: true) : nil
    }
  end
end
