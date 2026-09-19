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

ActiveRecord::Schema[8.1].define(version: 2026_09_19_140000) do
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

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_used_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "corrective_actions", force: :cascade do |t|
    t.integer "assigned_to_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.date "due_date"
    t.integer "inspection_id", null: false
    t.integer "inspection_response_id", null: false
    t.integer "organization_id", null: false
    t.string "severity", default: "Medium", null: false
    t.string "status", default: "Open", null: false
    t.integer "store_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["assigned_to_id"], name: "index_corrective_actions_on_assigned_to_id"
    t.index ["inspection_id"], name: "index_corrective_actions_on_inspection_id"
    t.index ["inspection_response_id"], name: "index_corrective_actions_on_inspection_response_id"
    t.index ["organization_id"], name: "index_corrective_actions_on_organization_id"
    t.index ["store_id"], name: "index_corrective_actions_on_store_id"
  end

  create_table "inspection_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "inspection_template_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.decimal "weight", precision: 6, scale: 2, default: "1.0", null: false
    t.index ["inspection_template_id"], name: "index_inspection_categories_on_inspection_template_id"
  end

  create_table "inspection_photos", force: :cascade do |t|
    t.text "annotation_data"
    t.text "comment"
    t.datetime "created_at", null: false
    t.integer "inspection_id", null: false
    t.integer "inspection_response_id"
    t.datetime "updated_at", null: false
    t.index ["inspection_id"], name: "index_inspection_photos_on_inspection_id"
    t.index ["inspection_response_id"], name: "index_inspection_photos_on_inspection_response_id"
  end

  create_table "inspection_questions", force: :cascade do |t|
    t.boolean "comment_required", default: false, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "inspection_category_id", null: false
    t.integer "max_score", default: 5, null: false
    t.boolean "photo_required", default: false, null: false
    t.integer "position", default: 0, null: false
    t.boolean "required", default: true, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.decimal "weight", precision: 6, scale: 2, default: "1.0", null: false
    t.index ["inspection_category_id"], name: "index_inspection_questions_on_inspection_category_id"
  end

  create_table "inspection_responses", force: :cascade do |t|
    t.text "comment"
    t.datetime "created_at", null: false
    t.integer "inspection_id", null: false
    t.integer "inspection_question_id"
    t.boolean "not_applicable", default: false, null: false
    t.boolean "passed"
    t.integer "score", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["inspection_id", "inspection_question_id"], name: "index_responses_on_inspection_and_question", unique: true
    t.index ["inspection_id"], name: "index_inspection_responses_on_inspection_id"
    t.index ["inspection_question_id"], name: "index_inspection_responses_on_inspection_question_id"
  end

  create_table "inspection_templates", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "organization_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["organization_id"], name: "index_inspection_templates_on_organization_id"
  end

  create_table "inspections", force: :cascade do |t|
    t.text "comment"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "general_comment"
    t.integer "inspection_template_id"
    t.integer "inspector_id"
    t.integer "organization_id", null: false
    t.decimal "score", precision: 5, scale: 2
    t.datetime "started_at"
    t.string "status", default: "draft", null: false
    t.integer "store_id", null: false
    t.datetime "submitted_at"
    t.decimal "total_score", precision: 6, scale: 2
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["inspection_template_id"], name: "index_inspections_on_inspection_template_id"
    t.index ["inspector_id"], name: "index_inspections_on_inspector_id"
    t.index ["organization_id"], name: "index_inspections_on_organization_id"
    t.index ["status"], name: "index_inspections_on_status"
    t.index ["store_id", "created_at"], name: "index_inspections_on_store_id_and_created_at"
    t.index ["store_id"], name: "index_inspections_on_store_id"
    t.index ["user_id", "created_at"], name: "index_inspections_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_inspections_on_user_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "stores", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "address"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "organization_id", null: false
    t.string "phone"
    t.string "store_code", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "store_code"], name: "index_stores_on_organization_id_and_store_code", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.integer "organization_id", null: false
    t.string "password_digest", null: false
    t.string "role", default: "inspector", null: false
    t.datetime "updated_at", null: false
    t.index "lower(email)", name: "index_users_on_lower_email", unique: true
    t.index ["organization_id"], name: "index_users_on_organization_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "corrective_actions", "inspection_responses"
  add_foreign_key "corrective_actions", "inspections"
  add_foreign_key "corrective_actions", "organizations"
  add_foreign_key "corrective_actions", "stores"
  add_foreign_key "corrective_actions", "users", column: "assigned_to_id"
  add_foreign_key "inspection_categories", "inspection_templates"
  add_foreign_key "inspection_photos", "inspection_responses"
  add_foreign_key "inspection_photos", "inspections"
  add_foreign_key "inspection_questions", "inspection_categories"
  add_foreign_key "inspection_responses", "inspection_questions"
  add_foreign_key "inspection_responses", "inspections"
  add_foreign_key "inspection_templates", "organizations"
  add_foreign_key "inspections", "inspection_templates"
  add_foreign_key "inspections", "organizations"
  add_foreign_key "inspections", "stores"
  add_foreign_key "inspections", "users"
  add_foreign_key "inspections", "users", column: "inspector_id"
  add_foreign_key "stores", "organizations"
  add_foreign_key "users", "organizations"
end
