class Inspection < ApplicationRecord
  STATUSES = %w[draft submitted].freeze

  belongs_to :store
  belongs_to :user
  has_many :inspection_responses, dependent: :destroy
  has_many :inspection_photos, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :submitted, -> { where(status: "submitted") }

  def draft?
    status == "draft"
  end

  def recalculate_score!
    responses = inspection_responses.includes(:checklist_item)
    total_weight = responses.sum { |response| response.checklist_item.weight }
    weighted_score = responses.sum { |response| response.score.to_i * response.checklist_item.weight }
    update!(score: total_weight.positive? ? (weighted_score.to_f / total_weight).round(2) : 0)
  end

  def submit!(final_comment: nil)
    transaction do
      recalculate_score!
      update!(status: "submitted", submitted_at: Time.current, comment: final_comment.presence || comment)
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
      inspector: user.as_api_json
    }
    payload[:responses] = inspection_responses.includes(:checklist_item, :inspection_photos).map(&:as_api_json) if include_detail
    payload
  end
end
