module ApplicationHelper
  # shared/_page_header's "Dashboard" breadcrumb crumb needs the right console's own root — this
  # is the one thing genuinely shared between Admin:: and SuperAdmin:: views (unlike home_path,
  # which layouts/admin.html.erb and layouts/super_admin.html.erb pass into console_shell as a
  # local, not available to the page content itself: the action's view template renders fully
  # before the layout runs, so a layout-side local can't reach it — this re-derives it instead,
  # from whichever Warden scope is actually signed in).
  def console_home_path
    platform_staff_signed_in? ? platform_staff_root_path : user_root_path
  end

  # Event#meeting_link/#map_url are organizer-entered free text, not validated as real URLs
  # (requirement.md doesn't call for that) — rendered directly as an href, a crafted
  # `javascript:...` value would execute in whoever views it (the organizer's own Review step or
  # the Super Admin's review queue). Brakeman's LinkToHref check flagged exactly this on
  # app/views/super_admin/event_reviews/show.html.erb. Only linkify http(s) URLs; anything else
  # (including a bare "javascript:" scheme) renders as inert plain text instead.
  def external_link_to(text, url)
    if url.start_with?("http://", "https://")
      link_to text, url
    else
      content_tag(:span, text)
    end
  end

  # Shared between the wizard's top badge strip (edit.html.erb) and the Review step's own detail
  # row (_review_step.html.erb) — one mapping, not two copies to keep in sync as approval_status
  # grows states.
  APPROVAL_STATUS_BADGE_CLASSES = {
    "unsubmitted" => "bg-secondary-subtle text-secondary",
    "pending" => "bg-warning-subtle text-warning",
    "approved" => "bg-success-subtle text-success",
    "rejected" => "bg-danger-subtle text-danger"
  }.freeze

  def approval_status_badge_class(approval_status)
    APPROVAL_STATUS_BADGE_CLASSES.fetch(approval_status)
  end
end
