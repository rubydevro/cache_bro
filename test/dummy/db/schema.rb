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

ActiveRecord::Schema[7.1].define(version: 2026_11_15_130000) do
  create_table "cache_bro_audit_events", force: :cascade do |t|
    t.string "event", null: false
    t.string "user_label"
    t.string "environment", null: false
    t.string "store", null: false
    t.text "target"
    t.integer "count"
    t.text "reason"
    t.json "details", null: false
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_cache_bro_audit_events_on_created_at"
    t.index ["event", "created_at"], name: "index_cache_bro_audit_events_on_event_and_created_at"
    t.index ["user_label", "created_at"], name: "index_cache_bro_audit_events_on_user_label_and_created_at"
  end
end
