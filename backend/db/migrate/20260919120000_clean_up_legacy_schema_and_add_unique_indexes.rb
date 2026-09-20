# schema.rb had drifted from the migrations: it still carried the checklist
# tables (and inspection_responses.checklist_item_id) of an earlier design that
# no migration in this repo creates, so `db:schema:load` and `db:migrate` gave
# different databases. This migration removes those leftovers when present
# (no-op on a database built from the migrations) and adds the uniqueness
# guarantees the models already assume.
class CleanUpLegacySchemaAndAddUniqueIndexes < ActiveRecord::Migration[8.1]
  def up
    remove_legacy_checklist_schema
    ensure_no_duplicate_responses!

    add_index :inspection_responses, [ :inspection_id, :inspection_question_id ],
      unique: true, name: "index_responses_on_inspection_and_question"

    # Store codes are unique per organization (that is what the model
    # validates); the old global index blocked two organizations from sharing a
    # code. The composite index also covers lookups by organization_id.
    remove_index :stores, :store_code, if_exists: true
    remove_index :stores, :organization_id, if_exists: true
    add_index :stores, [ :organization_id, :store_code ],
      unique: true, name: "index_stores_on_organization_id_and_store_code"
  end

  # The legacy checklist tables are not restored: nothing in the app uses them.
  def down
    remove_index :stores, name: "index_stores_on_organization_id_and_store_code"
    add_index :stores, :organization_id
    add_index :stores, :store_code, unique: true

    remove_index :inspection_responses, name: "index_responses_on_inspection_and_question"
  end

  private

  def remove_legacy_checklist_schema
    remove_index :inspection_responses, name: "index_responses_on_inspection_and_item", if_exists: true

    if foreign_key_exists?(:inspection_responses, :checklist_items)
      remove_foreign_key :inspection_responses, :checklist_items
    end
    if column_exists?(:inspection_responses, :checklist_item_id)
      remove_index :inspection_responses, :checklist_item_id, if_exists: true
      remove_column :inspection_responses, :checklist_item_id
    end

    drop_table :checklist_items, if_exists: true
    drop_table :checklist_templates, if_exists: true
  end

  def ensure_no_duplicate_responses!
    duplicates = select_rows(<<~SQL.squish)
      SELECT inspection_id, inspection_question_id, COUNT(*)
      FROM inspection_responses
      WHERE inspection_question_id IS NOT NULL
      GROUP BY inspection_id, inspection_question_id
      HAVING COUNT(*) > 1
    SQL
    return if duplicates.empty?

    pairs = duplicates.first(10).map { |inspection_id, question_id, count| "inspection #{inspection_id} / question #{question_id} (#{count} rows)" }
    raise "Cannot add the unique index: duplicate inspection responses exist. Merge or delete them first: #{pairs.join('; ')}"
  end
end
