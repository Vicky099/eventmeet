module SuperAdminHelper
  # Feeds shared/_console_shell's sidebar. Real routes replace the "#" placeholders as each
  # module ships (Billing: Phase 15).
  #
  # requirement.md revisit: "this page and sidebar link is not required as we have a agency to
  # handle the tenant accounts" — the standalone "Tenants" entry (Phase 2) is gone; each Agency's
  # own show page already lists its own tenants, with a details modal per row, so there's no
  # platform-wide flat list of every tenant across every agency needed here anymore.
  #
  # "Live Pulse" (Phase 9) removed too — it was always a dead "#" stub, never wired to its own
  # page; the real live-pulse data (live event count, registered/checked-in/occupancy, updated in
  # real time via Turbo Streams — LiveDashboard.platform_pulse/#broadcast_platform_pulse) already
  # renders as a widget directly on the Dashboard's own home page, so nothing was actually lost by
  # dropping the link that went nowhere.
  def super_admin_nav_items
    [
      { path: platform_staff_root_path, icon: "bx-home-alt", label: "Dashboard" },
      # Agency layer (requirement.md revisit): a distinct top-level entry — an Agency isn't a
      # tenant itself, it's the grouping/billing entity a tenant now belongs to.
      { path: platform_agencies_path, icon: "bx-briefcase", label: "Agencies" },
      # Fixed-hierarchy pivot (requirement.md revisit): "Event Approvals"/"Quotations" both removed
      # along with the per-event Super Admin review/pricing-negotiation workflow they linked to —
      # Invoice is the only billing item left.
      { path: platform_invoices_path, icon: "bx-credit-card", label: "Invoice" },
      # Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md).
      { path: platform_audit_log_entries_path, icon: "bx-history", label: "Audit Log" }
    ]
  end
end
