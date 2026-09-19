class CorrectiveAction < ApplicationRecord
  SEVERITIES = [ "Low", "Medium", "High", "Critical" ].freeze
  STATUSES = [ "Open", "In Progress", "Resolved", "Verified" ].freeze

  belongs_to :organization
  belongs_to :store
  belongs_to :inspection
  belongs_to :inspection_response
  belongs_to :assigned_to, class_name: "User", optional: true

  validates :title, presence: true
  validates :severity, inclusion: { in: SEVERITIES }
  validates :status, inclusion: { in: STATUSES }
  validate :assignee_in_same_organization

  before_save :track_completion, if: :will_save_change_to_status?

  scope :open_status, -> { where.not(status: [ "Resolved", "Verified" ]) }
  scope :critical, -> { where(severity: "Critical") }

  def as_api_json
    {
      id: id,
      inspection_id: inspection_id,
      inspection_response_id: inspection_response_id,
      title: title,
      description: description,
      severity: severity,
      status: status,
      due_date: due_date,
      completed_at: completed_at,
      store: store.as_api_json,
      assigned_to: assigned_to&.as_api_json
    }
  end

  CLOSED_STATUSES = [ "Resolved", "Verified" ].freeze

  private

  # Stamp when an action gets closed and clear it when it is reopened, unless the
  # client sent its own completed_at.
  def track_completion
    return if will_save_change_to_completed_at?

    self.completed_at = CLOSED_STATUSES.include?(status) ? (completed_at || Time.current) : nil
  end

  def assignee_in_same_organization
    return if assigned_to.blank? || assigned_to.organization_id == organization_id

    errors.add(:assigned_to, "must belong to the same organization")
  end
end
