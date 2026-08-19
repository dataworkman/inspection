class Inspection < ApplicationRecord
  STATUSES = %w[draft in_progress completed submitted].freeze

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

  def draft?
    status == "draft"
  end

  def recalculate_score!
    responses = inspection_responses.includes(inspection_question: :inspection_category).reject(&:not_applicable?)
    possible = responses.sum { |response| response.possible_weighted_score }
    actual = responses.sum { |response| response.weighted_score }
    calculated = possible.positive? ? ((actual / possible) * 100).round(2) : 0
    update!(score: calculated, total_score: calculated)
  end

  def submit!(final_comment: nil)
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
    payload[:responses] = inspection_responses.includes(:checklist_item, :inspection_photos).map(&:as_api_json) if include_detail
    payload
  end

  def grade
    return nil if total_score.blank?
    return "Excellent" if total_score >= 90
    return "Good" if total_score >= 80
    return "Needs Improvement" if total_score >= 70

    "Critical"
  end
end
