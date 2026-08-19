class User < ApplicationRecord
  has_secure_password

  has_many :inspections, dependent: :restrict_with_exception

  before_validation :normalize_email
  before_create :issue_api_token

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :role, inclusion: { in: %w[admin inspector] }

  def admin?
    role == "admin"
  end

  def as_api_json
    { id: id, name: name, email: email, role: role }
  end

  def rotate_api_token!
    update!(api_token: SecureRandom.hex(32))
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def issue_api_token
    self.api_token ||= SecureRandom.hex(32)
  end
end
