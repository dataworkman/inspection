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

  scope :open_status, -> { where.not(status: [ "Resolved", "Verified" ]) }
  scope :critical, -> { where(severity: "Critical") }

  def as_api_json
    {
      id: id,
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
end
