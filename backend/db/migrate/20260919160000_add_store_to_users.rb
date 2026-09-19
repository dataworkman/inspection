# A store manager works for one store. The reference is optional at the database
# level (admins and inspectors are not tied to a store); the model requires it
# for the store_manager role.
class AddStoreToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :store, foreign_key: true, null: true
  end
end
