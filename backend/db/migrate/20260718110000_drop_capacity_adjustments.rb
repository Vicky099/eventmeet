# Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6, confirmed with the
# user): "we don't have plans. we have only business plan where we customize the amount based on
# the event size and need." No Basic/Pro tiers means no participant cap, no soft-cap overage, and
# so no CapacityAdjustment at all — every event is now priced once, up front, via its Quotation.
# Dropped rather than left dormant since nothing references it anymore once Event#plan (next
# migration) is gone too.
class DropCapacityAdjustments < ActiveRecord::Migration[8.0]
  def up
    TenantRowLevelSecurity.disable!(self, :capacity_adjustments)
    drop_table :capacity_adjustments
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
