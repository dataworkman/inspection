class InspectionCategory < ApplicationRecord
  belongs_to :inspection_template
  has_many :inspection_questions, -> { order(:position, :id) }, dependent: :destroy

  validates :name, presence: true
  validates :weight, numericality: { greater_than: 0 }

  def as_api_json(include_questions: false)
    payload = { id: id, name: name, weight: weight.to_f, position: position }
    payload[:questions] = inspection_questions.map(&:as_api_json) if include_questions
    payload
  end
end
