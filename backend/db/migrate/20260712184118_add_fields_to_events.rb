# Event Basic Info gap-fill against the reference event_management system's field list —
# "Event Type" is confirmed to already be the existing `mode` column (on-site/virtual/hybrid),
# no separate field needed for it.
class AddFieldsToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :description, :text
    # Data flag only — requirement.md explicitly excludes a payment gateway/paid ticketing from
    # this app's scope (Phase 6 is capacity-only, no price field); this records organizer intent,
    # nothing more.
    add_column :events, :is_paid, :boolean, null: false, default: false
    # Wired for real — Participant#send_registration_confirmation! (after_create_commit) checks
    # this before enqueuing ParticipantMailer#confirmation.
    add_column :events, :send_registration_email, :boolean, null: false, default: false
  end
end
