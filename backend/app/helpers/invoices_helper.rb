module InvoicesHelper
  # Always the agency now (requirement.md revisit: invoices moved to the Agency Console entirely
  # — "we will only charge agency ... per event / Per Year") — a per-event Invoice still carries
  # the tenant's own account (for the amount/blob-key/audit trail), but the tenant is never who's
  # notified or who pays it. Shared between SuperAdmin::InvoicesController (its own flash
  # messages, hence `include`d there rather than left as a view-only helper) and both
  # super_admin/invoices/* and super_admin/dashboard/index views (Rails' own "every app/helpers
  # module is available in every view" default covers those without any include of their own).
  def invoice_recipient_label(invoice)
    (invoice.account&.agency || invoice.agency).name
  end
end
