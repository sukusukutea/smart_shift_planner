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

ActiveRecord::Schema[8.1].define(version: 2025_12_10_065802) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "occupations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_organizations_on_name", unique: true
  end

  create_table "staffs", force: :cascade do |t|
    t.boolean "can_cook", default: false, null: false
    t.boolean "can_day", default: false, null: false
    t.boolean "can_drive", default: false, null: false
    t.boolean "can_early", default: false, null: false
    t.boolean "can_late", default: false, null: false
    t.boolean "can_night", default: false, null: false
    t.boolean "can_visit", default: false, null: false
    t.datetime "created_at", null: false
    t.string "first_name", null: false
    t.string "first_name_kana", null: false
    t.string "last_name", null: false
    t.string "last_name_kana", null: false
    t.bigint "occupation_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["occupation_id"], name: "index_staffs_on_occupation_id"
    t.index ["user_id"], name: "index_staffs_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name", null: false
    t.integer "organization_id", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["organization_id"], name: "index_users_on_organization_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "staffs", "occupations"
  add_foreign_key "staffs", "users"
  add_foreign_key "users", "organizations"
end
