module AdminHelper
  # Feeds shared/_console_shell's sidebar. Real routes replace the "#" placeholders as each
  # module ships (Events: Phase 4, Participants: Phase 7, Badges: Phase 8, Check-in: Phase 9,
  # Sponsors: Phase 12, Reports: Phase 14, Settings: various).
  def admin_nav_items
    [
      { path: user_root_path, icon: "bx-home-alt", label: "Dashboard" },
      { path: "#", icon: "bx-calendar-event", label: "Events" },
      { path: "#", icon: "bx-group", label: "Participants" },
      { path: "#", icon: "bx-id-card", label: "Badges" },
      { path: "#", icon: "bx-barcode", label: "Check-in" },
      { path: "#", icon: "bx-store", label: "Sponsors" },
      { path: "#", icon: "bx-bar-chart-alt-2", label: "Reports" },
      { path: "#", icon: "bx-cog", label: "Settings" }
    ]
  end
end
