class CreateInspectionPhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :inspection_photos do |t|
      t.references :inspection, null: false, foreign_key: true
      t.references :inspection_response, null: true, foreign_key: true
      t.text :annotation_json
      t.text :comment

      t.timestamps
    end
  end
end
