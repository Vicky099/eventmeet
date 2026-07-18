module AdminHelper
  # Account-level sidebar (requirement.md §5.14 v12) — shown whenever the admin isn't inside a
  # specific event's own workspace (layouts/admin.html.erb switches to #event_nav_items instead
  # once @event is a real, persisted record — see that file's own comment). Exactly the five items
  # specified: Dashboard/Events/Reports/Settings/Profile — Participants/Check-in moved entirely
  # onto the event-scoped nav below (they were only ever reachable here via a "jump to the
  # most-recently-created event" guess anyway); Badges (the account-wide Badge Template library,
  # distinct from any one event's own badge design), Sponsors, and Email Templates (Phase 13
  # revisited — confirmed per-event, not per-tenant, so its nav entry lives on #event_nav_items
  # below instead) all lost/never got nav entries here, by deliberate choice — the template
  # library still exists and works, just isn't linked from any sidebar for now (reachable by
  # direct URL) until it gets a real home, e.g. under Settings once that's built. Reports/Settings/
  # Profile stay "#" stubs, same convention Sponsors used before it was dropped.
  def admin_nav_items
    [
      { path: user_root_path, icon: "bx-home-alt", label: "Dashboard" },
      { path: admin_events_path, icon: "bx-calendar-event", label: "Events" },
      # Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6, confirmed with the
      # user): "for Admin lets have below Sidebar - Quotations - Invoices" — two plain top-level
      # items, laid out for layman understanding rather than folded under one "Billing" entry.
      { path: admin_quotations_path, icon: "bx-receipt", label: "Quotations" },
      { path: admin_invoices_path, icon: "bx-credit-card", label: "Invoices" },
      { path: "#", icon: "bx-bar-chart-alt-2", label: "Reports" },
      { path: "#", icon: "bx-cog", label: "Settings" },
      { path: "#", icon: "bx-user-circle", label: "Profile" }
    ]
  end

  # Event-workspace sidebar (requirement.md §5.14 v12) — rendered instead of #admin_nav_items
  # whenever @event is a real, persisted event (layouts/admin.html.erb). Every link carries the
  # real event_id directly now — replacing the account-level nav's old "jump to the
  # most-recently-created event" guess (participants_nav_path/checkin_nav_path, both retired) now
  # that "which event" is unambiguous once you're actually inside one.
  def event_nav_items(event)
    [
      # Phase 14 — Reporting, Import/Export & Analytics (requirement.md §5.11): "there is no
      # reporting UI at all." This landing page already *was* the event's real-time/analytics
      # home (live KPIs, funnels, arrivals) even before this phase — Phase 14 just filled in the
      # remaining views (registrations-over-time, session popularity, a deeper engagement funnel)
      # on the same page rather than splitting a second one off, so the nav label now says what
      # the page has always actually been.
      { path: admin_event_path(event), icon: "bx-line-chart", label: "Analytics" },
      { path: admin_event_registration_forms_path(event), icon: "bx-list-check", label: "Design Registration Form" },
      # Phase 13 — Communications, revisited (requirement.md §3.10): "Custom email will be new
      # sidebar menu" — confirmed per-event, so it lives in this event-workspace nav, alongside the
      # other registration-experience configuration entries, not the account-level nav above.
      { path: admin_event_email_templates_path(event), icon: "bx-envelope", label: "Email Templates" },
      { path: admin_event_participants_path(event), icon: "bx-group", label: "Participants" },
      # requirement.md revisit: "Export sidebar button will provide a UI where admin can select
      # the fields which he wants to export" — Admin::ExportFilesController#new is now that
      # standalone field-picker page (previously this linked to the Participants index itself,
      # back when the only "Export" trigger was a plain button embedded there).
      { path: new_admin_event_export_file_path(event), icon: "bx-download", label: "Export" },
      { path: new_admin_event_import_file_path(event), icon: "bx-upload", label: "Import" },
      # requirement.md revisit: "in upload we should have a separate sample xlsx file to upload
      # the govtID" — its own upload flow, its own nav entry, same as Import/Export above.
      { path: new_admin_event_govt_id_import_file_path(event), icon: "bx-id-card", label: "Govt IDs" },
      { path: admin_event_scan_events_path(event), icon: "bx-barcode", label: "Check In" }
    ]
  end
end
