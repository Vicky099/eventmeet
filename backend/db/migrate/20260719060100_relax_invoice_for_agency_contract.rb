# Fixed-hierarchy pivot (requirement.md revisit): reuses Invoice for the new agency-level "one
# upfront contract payment" flow (`Invoice.generate_for_agency_contract`) instead of building a
# second, near-identical draft/awaiting_payment/under_review/paid + UTR/receipt model from scratch.
# An agency contract invoice has neither an Event nor a tenant Account — both foreign keys become
# nullable, `agency_id` is the new third option, and the model's own validation (not the DB) is
# what actually enforces "exactly one of event/agency" per row.
#
# TenantRowLevelSecurity.disable! — Invoice drops `include TenantScoped` in this same pivot (an
# agency-level row has no Current.account to scope against at all), so the RLS policy checking
# `account_id = current_setting(...)` is no longer backed by the model-layer contract it exists to
# backstop; leaving it enabled would silently hide every legitimately-NULL-account_id agency
# invoice row instead of just doing nothing (same "second, independent layer" reasoning as every
# other TenantScoped table, just in reverse here).
class RelaxInvoiceForAgencyContract < ActiveRecord::Migration[8.0]
  def change
    change_column_null :invoices, :event_id, true
    change_column_null :invoices, :account_id, true

    add_reference :invoices, :agency, type: :uuid, foreign_key: true

    TenantRowLevelSecurity.disable!(self, :invoices)
  end
end
