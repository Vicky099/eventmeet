# Phase 8 — Badge Design & Printing (requirement.md §3.6, §5.5). Account-scoped library entry —
# "reusable/sharable templates across events within a tenant." Only ever a starting point: creating
# a Badge "from" one copies content/mapping/size in rather than referencing this row live, so
# editing a template later never silently changes badges already built from it.
class BadgeTemplate < ApplicationRecord
  include TenantScoped
  include TenantScopedAttachment
  include HasBadgeMapping

  has_one_attached :background_image
  has_one_attached :logo

  def attach_background_image(uploaded_file)
    attach_tenant_scoped(:background_image, uploaded_file, "badge_templates", "background_image")
  end

  def attach_logo(uploaded_file)
    attach_tenant_scoped(:logo, uploaded_file, "badge_templates", "logo")
  end
end
