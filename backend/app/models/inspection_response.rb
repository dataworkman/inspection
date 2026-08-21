class InspectionResponse < ApplicationRecord
  belongs_to :inspection
  belongs_to :inspection_question, optional: true

  has_many :inspection_photos, dependent: :nullify
  has_many :corrective_actions, dependent: :destroy

  validates :score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :inspection_question_id, uniqueness: { scope: :inspection_id }, allow_nil: true

  after_save :recalculate_inspection_score

  def weighted_score
    return 0 if not_applicable? || inspection_question.blank?

    score.to_f * inspection_question.weight.to_f * inspection_question.inspection_category.weight.to_f
  end

  def possible_weighted_score
    return 0 if not_applicable? || inspection_question.blank?

    inspection_question.max_score.to_f * inspection_question.weight.to_f * inspection_question.inspection_category.weight.to_f
  end

  def as_api_json
    question = inspection_question
    {
      id: id,
      inspection_question_id: inspection_question_id,
      category: question&.inspection_category&.name,
      category_position: question&.inspection_category&.position,
      title: question&.title,
      position: question&.position,
      max_score: question&.max_score,
      weight: question&.weight&.to_f,
      score: score,
      not_applicable: not_applicable,
      passed: passed,
      comment: comment,
      photos: inspection_photos.map(&:as_api_json)
    }
  end

  private

  def recalculate_inspection_score
    inspection.recalculate_score!
  end
end
