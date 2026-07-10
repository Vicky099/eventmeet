module SuperAdminHelper
  # Feeds shared/_console_shell's sidebar. Real routes replace the "#" placeholders as each
  # module ships (Tenants: Phase 2, Event Approvals: Phase 5, Billing: Phase 15, Live Pulse: Phase 9).
  def super_admin_nav_items
    [
      { path: platform_staff_root_path, icon: "bx-home-alt", label: "Dashboard" },
      { path: "#", icon: "bx-buildings", label: "Tenants" },
      { path: "#", icon: "bx-check-shield", label: "Event Approvals" },
      { path: "#", icon: "bx-receipt", label: "Billing" },
      { path: "#", icon: "bx-pulse", label: "Live Pulse" }
    ]
  end
end
