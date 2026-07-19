module ApplicationHelper
  include Pagy::Frontend

  # Brand mark assets (logo-main: full wordmark, logo-circle: collapsed/square mark, favicon:
  # browser tab icon) — uploaded once to this app's own Cloudinary account (branding/* public
  # IDs) and referenced by their permanent secure_url here, not a runtime image_tag/cl_image_tag
  # call: these are fixed brand assets, not user-generated content, so there's no per-request
  # transform/upload to drive through the Cloudinary helper pipeline. Every call site uses
  # `tag.img src: ...`, not `image_tag` — config/cloudinary.yml's `enhance_image_tag: true`
  # globally monkey-patches `image_tag` to route every source through Cloudinary unconditionally
  # (see app/views/checkin/_participant_avatar.html.erb's own comment on the same caveat), which
  # 500s on an already-absolute URL like these.
  BRAND_LOGO_MAIN_URL = "https://res.cloudinary.com/ddbkhb3vl/image/upload/v1784479925/branding/logo-main.png"
  BRAND_LOGO_CIRCLE_URL = "https://res.cloudinary.com/ddbkhb3vl/image/upload/v1784479926/branding/logo-circle.png"
  BRAND_FAVICON_URL = "https://res.cloudinary.com/ddbkhb3vl/image/upload/v1784479927/branding/favicon.png"
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

  # Inline per-field validation errors (red text directly below the field, not just the form's
  # own top-of-page summary list) — Bootstrap's standard `is-invalid`/`invalid-feedback` pair:
  # `field_error_class` goes on the input itself, `field_error_feedback` renders the message
  # right after it. `d-block` on the feedback div, not relying on Bootstrap's own
  # `.is-invalid ~ .invalid-feedback` CSS auto-show — this only ever renders the div at all when
  # there's a real error, so nothing depends on the sibling-selector/DOM-order details of
  # wherever a field's other help text (`<small>`, etc.) happens to sit.
  def field_error_class(record, field, base: "form-control")
    record.errors[field].any? ? "#{base} is-invalid" : base
  end

  def field_error_feedback(record, field)
    return if record.errors[field].none?

    content_tag(:div, record.errors[field].join(", "), class: "invalid-feedback d-block")
  end

  # Agency/Invoice amounts (requirement.md §4.6) are no longer implicitly USD — every call site
  # that used to reach for the bare `number_to_currency` on one of those records goes through here
  # instead, so the record's own stored `currency` (Currency::SYMBOLS) always drives the symbol.
  def money(amount, currency)
    number_to_currency(amount, unit: Currency.symbol_for(currency), format: "%u%n")
  end
end
