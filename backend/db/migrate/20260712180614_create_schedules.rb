# Phase 11 (requirement.md §3.8): "Schedule items (talks) linked to a speaker, with start/end
# time and details." `session_id` optional — "linked to an Event and optionally a Session
# (track/room)" per the checklist: a talk can be a room-less plenary/keynote item, or sit inside
# one of the event's breakout Sessions.
class CreateSchedules < ActiveRecord::Migration[8.0]
  def change
    create_table :schedules, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true
      t.references :speaker, null: false, type: :uuid, foreign_key: true
      t.references :session, null: true, type: :uuid, foreign_key: true

      t.string :title, null: false
      t.text :details
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :schedules)
  end
end
