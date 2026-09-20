class ApiToken < ApplicationRecord
  TTL = ENV.fetch("API_TOKEN_TTL_DAYS", 30).to_i.days
  MAX_PER_USER = 10
  # Avoid a database write on every request.
  TOUCH_INTERVAL = 1.hour

  belongs_to :user

  scope :active, -> { where("expires_at > ?", Time.current) }

  # Returns [record, plaintext]. The plaintext is only ever returned here.
  def self.issue!(user)
    plaintext = SecureRandom.hex(32)
    record = user.api_tokens.create!(token_digest: digest(plaintext), expires_at: TTL.from_now)
    prune!(user)
    [ record, plaintext ]
  end

  def self.authenticate(plaintext)
    return nil if plaintext.blank?

    token = active.includes(:user).find_by(token_digest: digest(plaintext))
    token&.touch_last_used!
    token
  end

  def self.digest(plaintext)
    Digest::SHA256.hexdigest(plaintext.to_s)
  end

  # Drops expired tokens and the oldest ones beyond MAX_PER_USER.
  def self.prune!(user)
    user.api_tokens.where("expires_at <= ?", Time.current).delete_all
    stale_ids = user.api_tokens.order(created_at: :desc, id: :desc).offset(MAX_PER_USER).pluck(:id)
    where(id: stale_ids).delete_all if stale_ids.any?
  end

  def touch_last_used!
    return if last_used_at && last_used_at > TOUCH_INTERVAL.ago

    update_columns(last_used_at: Time.current)
  end
end
