# Phase 15 — Platform Billing & Invoicing (requirement.md §4.6, §8): "`Plan` (Basic/Pro/Business
# definitions), assigned per event at creation time (not per Account)." A plain enum column, not a
# separate `Plan` reference table — there's nothing tenant-editable about the three tiers (caps/
# rates are fixed platform-wide business rules, `EventBilling`), same "fixed enum + class-level
# constants" shape this app already uses for e.g. Badge#output_type rather than a reference table
# nobody ever adds rows to. `Account#plan` (a placeholder string column since Phase 0, never an
# enum, requirement.md's own "billing is per-event, not per-Account" — confirmed here) stays
# untouched; this is the real, enforced plan assignment.
#
# `default: 0` (basic) — every existing Event row predates this column; NOT NULL with a real
# default backfills them for free rather than requiring every pre-Phase-15 factory/spec to start
# passing `plan:` explicitly.
#
# `quotation_id` nullable — only ever set for `plan: business` (Admin::EventsController#create
# consumes an approved, unused Quotation into it). Not `foreign_key: true` alone — also needs the
# reverse uniqueness (`Quotation has_one :event`, enforced by the unique index below) since exactly
# one Event can ever consume a given Quotation.
class AddPlanAndQuotationToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :plan, :integer, null: false, default: 0
    add_reference :events, :quotation, type: :uuid, foreign_key: true, index: { unique: true }
  end
end
