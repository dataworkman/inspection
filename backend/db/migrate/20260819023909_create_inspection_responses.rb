class CreateInspectionResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :inspection_responses do |t|
      t.references :inspection, null: false, foreign_key: true
      t.references :checklist_item, null: false, foreign_key: true
      t.integer :score, null: false, default: 0
      t.boolean :passed
      t.text :comment

      t.timestamps
    end
    add_index :inspection_responses, [ :inspection_id, :checklist_item_id ], unique: true, name: "index_responses_on_inspection_and_item"
  end
end
