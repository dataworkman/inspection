class User < ApplicationRecord
  has_secure_password

  belongs_to :organization
  belongs_to :store, optional: true
  has_many :inspections, dependent: :restrict_with_exception
  has_many :api_tokens, dependent: :delete_all

  before_validation :normalize_email

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :role, inclusion: { in: %w[admin inspector store_manager] }
  # Only when a manager is created or their store/role changes, so an old
  # account without a store can still be deactivated.
  validate :store_manager_has_a_store, if: -> { new_record? || will_save_change_to_store_id? || will_save_change_to_role? }
  validate :store_in_same_organization

  def admin?
    role == "admin"
  end

  def inspector?
    role == "inspector"
  end

  def store_manager?
    role == "store_manager"
  end

  def as_api_json
    { id: id, organization_id: organization_id, store_id: store_id, name: name, email: email, role: role, active: active }
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def store_manager_has_a_store
    errors.add(:store, "must be set for a store manager") if store_manager? && store_id.nil?
  end

  def store_in_same_organization
    return if store.nil? || store.organization_id == organization_id

    errors.add(:store, "must belong to the same organization")
  end
end
