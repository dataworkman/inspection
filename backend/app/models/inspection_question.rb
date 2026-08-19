class InspectionQuestion < ApplicationRecord
  belongs_to :inspection_category
  has_many :inspection_responses, dependent: :restrict_with_exception

  validates :title, presence: true
  validates :max_score, numericality: { greater_than: 0 }
  validates :weight, numericality: { greater_than: 0 }

  def as_api_json
    {
      id: id,
      inspection_category_id: inspection_category_id,
      category: inspection_category.name,
      category_weight: inspection_category.weight.to_f,
      title: title,
      description: description,
      max_score: max_score,
      weight: weight.to_f,
      required: required,
      photo_required: photo_required,
      comment_required: comment_required,
      position: position
    }
  end
end
