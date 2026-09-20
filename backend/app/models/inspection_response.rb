class InspectionResponse < ApplicationRecord
  belongs_to :inspection
  belongs_to :inspection_question, optional: true

  has_many :inspection_photos, dependent: :nullify
  has_many :corrective_actions, dependent: :destroy

  validates :score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :inspection_question_id, uniqueness: { scope: :inspection_id }, allow_nil: true
  validate :score_within_question_max
  validate :question_belongs_to_inspection_template, if: :inspection_question_id_changed?

  after_save :recalculate_inspection_score, if: :affects_score?

  # A score of 0 means "not answered yet" (the scale starts at 1). Unanswered
  # items are left out of the score instead of counting as failures.
  def answered?
    not_applicable? || score.to_i.positive?
  end

  def scored?
    !not_applicable? && score.to_i.positive? && inspection_question.present?
  end

  # An item passes when it earns at least this share of its points (the same
  # bar as a "Needs Improvement" inspection grade).
  PASS_RATIO = 0.7

  # true / false for a scored item; nil when it is unanswered or N/A.
  def passed
    return nil unless scored?

    score.to_f / inspection_question.max_score >= PASS_RATIO
  end

  # Question-level weight only. Category weights are applied per category in
  # Inspection#calculate_total_score so they act as shares of the total.
  def weighted_score
    return 0 unless scored?

    score.to_f * inspection_question.weight.to_f
  end

  def possible_weighted_score
    return 0 unless scored?

    inspection_question.max_score.to_f * inspection_question.weight.to_f
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
      required: question&.required,
      photo_required: question&.photo_required,
      comment_required: question&.comment_required,
      score: score,
      not_applicable: not_applicable,
      passed: passed,
      comment: comment,
      photos: inspection_photos.map(&:as_api_json)
    }
  end

  private

  def score_within_question_max
    return if inspection_question.blank? || score.blank?
    return if score <= inspection_question.max_score

    errors.add(:score, "must be at most #{inspection_question.max_score}")
  end

  def question_belongs_to_inspection_template
    template_id = inspection&.inspection_template_id
    return if inspection_question.blank? || template_id.blank?
    return if inspection_question.inspection_category.inspection_template_id == template_id

    errors.add(:inspection_question, "does not belong to this inspection's template")
  end

  def affects_score?
    saved_change_to_score? || saved_change_to_not_applicable? || saved_change_to_inspection_question_id?
  end

  def recalculate_inspection_score
    inspection.recalculate_score!
  end
end
