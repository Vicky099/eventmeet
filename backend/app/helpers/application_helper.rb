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
end
