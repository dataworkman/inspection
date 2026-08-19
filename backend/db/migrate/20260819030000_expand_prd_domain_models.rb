class ExpandPrdDomainModels < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.timestamps
    end

    add_reference :users, :organization, foreign_key: true
    add_column :users, :active, :boolean, null: false, default: true

    add_reference :stores, :organization, foreign_key: true
    rename_column :stores, :code, :store_code
    add_column :stores, :phone, :string

    create_table :inspection_templates do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.boolean :active, null: false, default: true
      t.integer :version, null: false, default: 1
      t.timestamps
    end

    create_table :inspection_categories do |t|
      t.references :inspection_template, null: false, foreign_key: true
      t.string :name, null: false
      t.decimal :weight, precision: 6, scale: 2, null: false, default: 1
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :inspection_questions do |t|
      t.references :inspection_category, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.integer :max_score, null: false, default: 5
      t.decimal :weight, precision: 6, scale: 2, null: false, default: 1
      t.boolean :required, null: false, default: true
      t.boolean :photo_required, null: false, default: false
      t.boolean :comment_required, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_reference :inspections, :organization, foreign_key: true
    add_reference :inspections, :inspection_template, foreign_key: true
    add_reference :inspections, :inspector, foreign_key: { to_table: :users }
    add_column :inspections, :started_at, :datetime
    add_column :inspections, :completed_at, :datetime
    add_column :inspections, :total_score, :decimal, precision: 6, scale: 2
    add_column :inspections, :general_comment, :text

    add_reference :inspection_responses, :inspection_question, foreign_key: true
    add_column :inspection_responses, :not_applicable, :boolean, null: false, default: false
    change_column_null :inspection_responses, :checklist_item_id, true

    rename_column :inspection_photos, :annotation_json, :annotation_data

    create_table :corrective_actions do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :store, null: false, foreign_key: true
      t.references :inspection, null: false, foreign_key: true
      t.references :inspection_response, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.string :severity, null: false, default: "Medium"
      t.string :status, null: false, default: "Open"
      t.references :assigned_to, foreign_key: { to_table: :users }
      t.date :due_date
      t.datetime :completed_at
      t.timestamps
    end
  end
end
