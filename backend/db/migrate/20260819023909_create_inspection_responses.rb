class CreateInspectionResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :inspection_responses do |t|
      t.references :inspection, null: false, foreign_key: true
      t.integer :score, null: false, default: 0
      t.boolean :passed
      t.text :comment

      t.timestamps
    end
  end
end
