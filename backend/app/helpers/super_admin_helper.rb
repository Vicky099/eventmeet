module SuperAdminHelper
  # Feeds shared/_console_shell's sidebar. Real routes replace the "#" placeholders as each
  # module ships (Tenants: Phase 2, Event Approvals: Phase 5, Billing: Phase 15, Live Pulse: Phase 9).
  def super_admin_nav_items
    [
      { path: platform_staff_root_path, icon: "bx-home-alt", label: "Dashboard" },
      { path: platform_accounts_path, icon: "bx-buildings", label: "Tenants" },
      { path: platform_event_reviews_path, icon: "bx-check-shield", label: "Event Approvals" },
      # Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6, confirmed with the
      # user): "for super admin lets have below Sidebar - Quotations - Invoice" — two plain
      # top-level items, laid out for layman understanding rather than folded under one "Billing"
      # entry.
      { path: platform_quotations_path, icon: "bx-receipt", label: "Quotations" },
      { path: platform_invoices_path, icon: "bx-credit-card", label: "Invoice" },
      { path: "#", icon: "bx-pulse", label: "Live Pulse" }
    ]
  end
end
