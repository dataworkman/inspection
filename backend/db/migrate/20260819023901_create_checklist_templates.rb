class CreateChecklistTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_templates do |t|
      t.string :title, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end
