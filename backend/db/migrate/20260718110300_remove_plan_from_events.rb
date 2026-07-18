# Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6, confirmed with the
# user): "we don't have plans. we have only business plan" — the Basic/Pro/Business enum is gone;
# every event is now the same single kind, priced via its Quotation. `quotation_id` itself is
# deliberately left nullable at the DB level (unlike a typical "make it required" migration) —
# there's real pre-existing dev data with no quotation from before this redesign, and the actual
# business rule ("every new event must have one") is enforced at the Rails layer instead
# (`belongs_to :quotation` with no `optional: true` — presence-validates by default) rather than
# forcing a backfill/cleanup of historical rows that predate this rule. The unique index from
# `20260718100200_add_plan_and_quotation_to_events.rb` already guarantees one event per quotation.
class RemovePlanFromEvents < ActiveRecord::Migration[8.0]
  def change
    remove_column :events, :plan, :integer, null: false, default: 0
  end
end
