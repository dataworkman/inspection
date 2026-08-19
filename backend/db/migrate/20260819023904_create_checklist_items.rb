class CreateChecklistItems < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_items do |t|
      t.references :checklist_template, null: false, foreign_key: true
      t.string :category, null: false
      t.string :title, null: false
      t.integer :weight, null: false, default: 1
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    add_index :checklist_items, [ :checklist_template_id, :position ]
  end
end
