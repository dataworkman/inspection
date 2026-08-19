class InspectionTemplate < ApplicationRecord
  belongs_to :organization
  has_many :inspection_categories, -> { order(:position, :id) }, dependent: :destroy
  has_many :inspection_questions, through: :inspection_categories

  validates :name, presence: true

  scope :active, -> { where(active: true) }

  def as_api_json(include_questions: false)
    payload = {
      id: id,
      organization_id: organization_id,
      name: name,
      description: description,
      version: version,
      active: active
    }
    payload[:categories] = inspection_categories.map { |category| category.as_api_json(include_questions: true) } if include_questions
    payload
  end
end
