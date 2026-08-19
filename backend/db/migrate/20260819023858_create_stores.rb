class CreateStores < ActiveRecord::Migration[8.1]
  def change
    create_table :stores do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.string :address
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :stores, :code, unique: true
  end
end
