# requirement.md revisit: "client also create event but event created by client requires a
# agency approval. post that client will proceed with event management (registration, checkin
# and all)." Fixed-hierarchy pivot already removed the *old* Super Admin content-review gate
# (admin/events/index.html.erb's own comment: "no more quotation-picker modal, no per-event Super
# Admin approval round trip") — this is a different, new gate, one tier down: the Agency (not the
# Platform) reviewing whatever its own Client's admins create, distinct from an event an agency
# admin creates directly while switched into that same client's console (Event#approval_status
# only ever becomes "pending" for the former — see Account#creator_requires_approval?).
#
# Same shape Invoice's own submitted_by/verified_by/rejection_reason columns already take
# (db/migrate/20260718110200_simplify_invoices.rb) — mirrored here as approved_by/approved_at/
# rejection_reason (one column pair covers both the approve and reject outcome, same as Invoice's
# verified_by/verified_at doing double duty for both verify! and reject_payment!).
class AddApprovalToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :approval_status, :integer, null: false, default: 0
    add_reference :events, :approved_by, type: :uuid, foreign_key: { to_table: :users }
    add_column :events, :approved_at, :datetime
    add_column :events, :rejection_reason, :text
  end
end
