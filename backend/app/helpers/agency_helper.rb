module AgencyHelper
  # Fixed-hierarchy pivot (requirement.md revisit): the Agency Console's own sidebar. Tenant
  # creation is still the whole point of this console; event-building itself still happens on the
  # tenant's own subdomain (Admin::EventsController, unchanged) via the same event_admin
  # AccountMembership every tenant creation already auto-grants.
  #
  # Invoices moved here entirely (requirement.md revisit, "we will only charge agency ... per
  # event / Per Year" — the agency is who's actually billed, so it's who manages every invoice,
  # not each individual tenant) — Invoice.for_agency covers both this agency's own single
  # annual-contract Invoice and every per-event Invoice across all of its own tenants at once.
  def agency_nav_items
    [
      { path: agency_root_path, icon: "bx-home-alt", label: "Dashboard" },
      # requirement.md revisit: "a sidebar which will have all the tenants with pagination" — the
      # full list, distinct from the dashboard's own "latest 10" preview card.
      { path: agency_accounts_path, icon: "bx-buildings", label: "Tenants" },
      { path: new_agency_account_path, icon: "bx-plus-circle", label: "New Tenant" },
      { path: agency_invoices_path, icon: "bx-credit-card", label: "Invoices" }
    ]
  end
end
