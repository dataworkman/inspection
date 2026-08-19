class InspectionPhoto < ApplicationRecord
  belongs_to :inspection
  belongs_to :inspection_response, optional: true
  has_one_attached :image

  validates :image, presence: true

  def as_api_json
    {
      id: id,
      inspection_response_id: inspection_response_id,
      annotation_json: annotation_json,
      comment: comment,
      image_url: image.attached? ? Rails.application.routes.url_helpers.rails_blob_path(image, only_path: true) : nil
    }
  end
end
