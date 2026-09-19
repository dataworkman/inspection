class User < ApplicationRecord
  has_secure_password

  belongs_to :organization
  has_many :inspections, dependent: :restrict_with_exception
  has_many :api_tokens, dependent: :delete_all

  before_validation :normalize_email

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :role, inclusion: { in: %w[admin inspector store_manager] }

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
    { id: id, organization_id: organization_id, name: name, email: email, role: role, active: active }
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
