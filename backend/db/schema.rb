# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_19_023911) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "checklist_items", force: :cascade do |t|
    t.string "category", null: false
    t.integer "checklist_template_id", null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "weight", default: 1, null: false
    t.index ["checklist_template_id", "position"], name: "index_checklist_items_on_checklist_template_id_and_position"
    t.index ["checklist_template_id"], name: "index_checklist_items_on_checklist_template_id"
  end

  create_table "checklist_templates", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
  end

  create_table "inspection_photos", force: :cascade do |t|
    t.text "annotation_json"
    t.text "comment"
    t.datetime "created_at", null: false
    t.integer "inspection_id", null: false
    t.integer "inspection_response_id"
    t.datetime "updated_at", null: false
    t.index ["inspection_id"], name: "index_inspection_photos_on_inspection_id"
    t.index ["inspection_response_id"], name: "index_inspection_photos_on_inspection_response_id"
  end

  create_table "inspection_responses", force: :cascade do |t|
    t.integer "checklist_item_id", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.integer "inspection_id", null: false
    t.boolean "passed"
    t.integer "score", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["checklist_item_id"], name: "index_inspection_responses_on_checklist_item_id"
    t.index ["inspection_id", "checklist_item_id"], name: "index_responses_on_inspection_and_item", unique: true
    t.index ["inspection_id"], name: "index_inspection_responses_on_inspection_id"
  end

  create_table "inspections", force: :cascade do |t|
    t.text "comment"
    t.datetime "created_at", null: false
    t.decimal "score", precision: 5, scale: 2
    t.string "status", default: "draft", null: false
    t.integer "store_id", null: false
    t.datetime "submitted_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["status"], name: "index_inspections_on_status"
    t.index ["store_id", "created_at"], name: "index_inspections_on_store_id_and_created_at"
    t.index ["store_id"], name: "index_inspections_on_store_id"
    t.index ["user_id", "created_at"], name: "index_inspections_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_inspections_on_user_id"
  end

  create_table "stores", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "address"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_stores_on_code", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "api_token"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.string "role", default: "inspector", null: false
    t.datetime "updated_at", null: false
    t.index "lower(email)", name: "index_users_on_lower_email", unique: true
    t.index ["api_token"], name: "index_users_on_api_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "checklist_items", "checklist_templates"
  add_foreign_key "inspection_photos", "inspection_responses"
  add_foreign_key "inspection_photos", "inspections"
  add_foreign_key "inspection_responses", "checklist_items"
  add_foreign_key "inspection_responses", "inspections"
  add_foreign_key "inspections", "stores"
  add_foreign_key "inspections", "users"
end
