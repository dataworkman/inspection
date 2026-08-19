class CreateInspections < ActiveRecord::Migration[8.1]
  def change
    create_table :inspections do |t|
      t.references :store, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "draft"
      t.decimal :score, precision: 5, scale: 2
      t.datetime :submitted_at
      t.text :comment

      t.timestamps
    end
    add_index :inspections, [ :store_id, :created_at ]
    add_index :inspections, [ :user_id, :created_at ]
    add_index :inspections, :status
  end
end
