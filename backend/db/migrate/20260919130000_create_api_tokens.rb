# Sessions move out of users.api_token (a plaintext, never-expiring, one-per-user
# secret) into api_tokens: only a SHA-256 digest is stored, every token expires,
# and a user can be signed in on several devices at once.
class CreateApiTokens < ActiveRecord::Migration[8.1]
  EXISTING_SESSION_DAYS = 30

  def up
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :api_tokens, :token_digest, unique: true

    # Keep current sessions alive, but hashed and with an expiry.
    now = connection.quote(Time.current.utc.to_fs(:db))
    expires_at = connection.quote(EXISTING_SESSION_DAYS.days.from_now.utc.to_fs(:db))
    select_rows("SELECT id, api_token FROM users WHERE api_token IS NOT NULL").each do |user_id, token|
      digest = Digest::SHA256.hexdigest(token)
      execute <<~SQL.squish
        INSERT INTO api_tokens (user_id, token_digest, expires_at, created_at, updated_at)
        VALUES (#{user_id.to_i}, #{connection.quote(digest)}, #{expires_at}, #{now}, #{now})
      SQL
    end

    remove_index :users, :api_token
    remove_column :users, :api_token
  end

  # Hashed tokens cannot be turned back into plaintext, so rolling back signs
  # everyone out.
  def down
    add_column :users, :api_token, :string
    add_index :users, :api_token, unique: true
    drop_table :api_tokens
  end
end
