class Inspection < ApplicationRecord
  STATUSES = %w[draft in_progress completed submitted].freeze
  EDITABLE_STATUSES = %w[draft in_progress completed].freeze

  belongs_to :organization, optional: true
  belongs_to :store
  belongs_to :user
  belongs_to :inspector, class_name: "User", optional: true
  belongs_to :inspection_template, optional: true
  has_many :inspection_responses, dependent: :destroy
  has_many :inspection_photos, dependent: :destroy
  has_many :corrective_actions, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :submitted, -> { where(status: "submitted") }
  scope :with_ordered_detail, -> {
    includes(
      :store,
      :user,
      :inspector,
      :inspection_template,
      inspection_responses: [ :inspection_photos, { inspection_question: :inspection_category } ]
    )
  }

  def draft?
    status == "draft"
  end

  def editable?
    EDITABLE_STATUSES.include?(status)
  end

  def recalculate_score!
    calculated = calculate_total_score
    update!(score: calculated, total_score: calculated)
  end

  # Category weights are shares of the total: each category is scored as a
  # percentage of its own possible points, then averaged by category weight.
  # Categories with nothing scored (all N/A or unanswered) drop out.
  def calculate_total_score
    scored = inspection_responses.includes(inspection_question: :inspection_category).select(&:scored?)

    weighted_percentages = 0.0
    total_weight = 0.0
    scored.group_by { |response| response.inspection_question.inspection_category }.each do |category, responses|
      possible = responses.sum(&:possible_weighted_score)
      next unless possible.positive?

      weighted_percentages += category.weight.to_f * (responses.sum(&:weighted_score) / possible)
      total_weight += category.weight.to_f
    end

    total_weight.positive? ? (weighted_percentages / total_weight * 100).round(2) : 0
  end

  # Requirements defined on the template's questions, enforced at submission.
  # N/A items are exempt.
  def submission_problems
    responses = inspection_responses.includes(:inspection_question, :inspection_photos).to_a
    required = responses.select { |response| response.inspection_question.present? && !response.not_applicable? }

    problems = []
    unanswered = responses.select { |response| response.inspection_question&.required? && !response.answered? }
    missing_photo = required.select { |response| response.inspection_question.photo_required? && response.inspection_photos.empty? }
    missing_comment = required.select { |response| response.inspection_question.comment_required? && response.comment.blank? }

    problems << "Answer required items: #{summarize_titles(unanswered)}" if unanswered.any?
    problems << "Photo required for: #{summarize_titles(missing_photo)}" if missing_photo.any?
    problems << "Comment required for: #{summarize_titles(missing_comment)}" if missing_comment.any?
    problems
  end

  def submit!(final_comment: nil)
    problems = submission_problems
    if problems.any?
      problems.each { |problem| errors.add(:base, problem) }
      raise ActiveRecord::RecordInvalid, self
    end

    transaction do
      recalculate_score!
      update!(
        status: "submitted",
        submitted_at: Time.current,
        completed_at: Time.current,
        general_comment: final_comment.presence || general_comment,
        comment: final_comment.presence || comment
      )
    end
  end

  def as_api_json(include_detail: false)
    payload = {
      id: id,
      status: status,
      score: score&.to_f,
      comment: comment,
      submitted_at: submitted_at,
      created_at: created_at,
      store: store.as_api_json,
      template: inspection_template&.as_api_json,
      inspector: (inspector || user).as_api_json,
      grade: grade
    }
    payload[:responses] = ordered_responses.map(&:as_api_json) if include_detail
    payload
  end

  def grade
    return nil if total_score.blank?
    return "Excellent" if total_score >= 90
    return "Good" if total_score >= 80
    return "Needs Improvement" if total_score >= 70

    "Critical"
  end

  def ordered_responses
    inspection_responses
      .includes(inspection_question: :inspection_category)
      .sort_by do |response|
        question = response.inspection_question
        category = question&.inspection_category
        [
          category&.position || Float::INFINITY,
          category&.id || Float::INFINITY,
          question&.position || Float::INFINITY,
          question&.id || Float::INFINITY,
          response.id || Float::INFINITY
        ]
      end
  end

  private

  def summarize_titles(responses, limit: 5)
    titles = responses.map { |response| response.inspection_question.title }
    shown = titles.first(limit).join(", ")
    titles.size > limit ? "#{shown} and #{titles.size - limit} more" : shown
  end
end
