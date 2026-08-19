class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :role, null: false, default: "inspector"
      t.string :api_token

      t.timestamps
    end
    add_index :users, "lower(email)", unique: true, name: "index_users_on_lower_email"
    add_index :users, :api_token, unique: true
  end
end
