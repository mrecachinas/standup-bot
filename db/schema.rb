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

ActiveRecord::Schema[8.1].define(version: 2026_04_27_150800) do
  create_table "audit_logs", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "action", null: false
    t.string "actor_email"
    t.bigint "actor_id"
    t.string "actor_label"
    t.string "actor_role"
    t.bigint "auditable_id", null: false
    t.string "auditable_type", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.json "metadata"
    t.string "request_id"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_id"], name: "index_audit_logs_on_actor_id"
    t.index ["auditable_type", "auditable_id"], name: "index_audit_logs_on_auditable_type_and_auditable_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
  end

  create_table "report_configurations", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "delivery_channel", null: false
    t.string "detail_level", default: "detailed", null: false
    t.json "recipients"
    t.string "report_format", default: "slack", null: false
    t.bigint "standup_id", null: false
    t.datetime "updated_at", null: false
    t.index ["standup_id"], name: "index_report_configurations_on_standup_id", unique: true
  end

  create_table "report_generations", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "actor_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "delivery_channel", null: false
    t.string "detail_level", null: false
    t.text "error_message"
    t.json "metadata"
    t.json "recipients"
    t.bigint "report_configuration_id"
    t.string "report_format", null: false
    t.datetime "requested_at", null: false
    t.date "standup_date", null: false
    t.bigint "standup_id", null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_report_generations_on_actor_id"
    t.index ["report_configuration_id"], name: "index_report_generations_on_report_configuration_id"
    t.index ["standup_id", "requested_at"], name: "index_report_generations_on_standup_id_and_requested_at"
    t.index ["standup_id"], name: "index_report_generations_on_standup_id"
    t.index ["status", "requested_at"], name: "index_report_generations_on_status_and_requested_at"
  end

  create_table "standup_ownerships", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "role", default: "manager", null: false
    t.bigint "standup_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["standup_id", "user_id"], name: "index_standup_ownerships_on_standup_id_and_user_id", unique: true
    t.index ["standup_id"], name: "index_standup_ownerships_on_standup_id"
    t.index ["user_id", "standup_id"], name: "index_standup_ownerships_on_user_id_and_standup_id"
    t.index ["user_id"], name: "index_standup_ownerships_on_user_id"
  end

  create_table "standup_participants", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "cached_timezone"
    t.datetime "cached_timezone_updated_at"
    t.datetime "created_at", null: false
    t.string "slack_id", null: false
    t.string "slack_name", null: false
    t.bigint "standup_id", null: false
    t.datetime "updated_at", null: false
    t.date "vacation_until"
    t.index ["standup_id", "slack_id"], name: "index_standup_participants_on_standup_id_and_slack_id", unique: true
    t.index ["standup_id"], name: "index_standup_participants_on_standup_id"
  end

  create_table "standup_responses", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.json "answers"
    t.datetime "created_at", null: false
    t.datetime "last_reminder_at"
    t.integer "reminder_count", default: 0, null: false
    t.string "slack_channel"
    t.string "slack_id", null: false
    t.string "slack_message_ts"
    t.date "standup_date"
    t.bigint "standup_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["slack_id", "status"], name: "index_standup_responses_on_slack_id_and_status"
    t.index ["standup_id", "slack_id", "standup_date"], name: "idx_standup_responses_on_standup_user_date", unique: true
    t.index ["standup_id"], name: "index_standup_responses_on_standup_id"
  end

  create_table "standup_schedule_exceptions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "exception_type", null: false
    t.date "original_date", null: false
    t.text "reason"
    t.date "rescheduled_date"
    t.integer "rescheduled_hour"
    t.integer "rescheduled_minute"
    t.string "rescheduled_timezone"
    t.bigint "standup_id", null: false
    t.datetime "updated_at", null: false
    t.index ["exception_type", "original_date"], name: "idx_standup_schedule_exceptions_on_type_date"
    t.index ["standup_id", "original_date"], name: "idx_standup_schedule_exceptions_on_standup_date", unique: true
    t.index ["standup_id"], name: "index_standup_schedule_exceptions_on_standup_id"
  end

  create_table "standups", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "default_hour", default: 9, null: false
    t.integer "default_minute", default: 0, null: false
    t.text "intro"
    t.integer "max_reminders", default: 1, null: false
    t.string "name", null: false
    t.text "outro"
    t.json "questions"
    t.integer "reminder_after_minutes", default: 120, null: false
    t.boolean "reminder_enabled", default: true, null: false
    t.boolean "respect_timezone", default: true, null: false
    t.json "schedule_days"
    t.string "schedule_type", default: "daily", null: false
    t.string "slack_channel", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "access_token_digest", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "last_signed_in_at"
    t.string "name", null: false
    t.string "role", default: "user", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "audit_logs", "users", column: "actor_id"
  add_foreign_key "report_configurations", "standups"
  add_foreign_key "report_generations", "report_configurations"
  add_foreign_key "report_generations", "standups"
  add_foreign_key "report_generations", "users", column: "actor_id"
  add_foreign_key "standup_ownerships", "standups"
  add_foreign_key "standup_ownerships", "users"
  add_foreign_key "standup_participants", "standups"
  add_foreign_key "standup_schedule_exceptions", "standups"
end
