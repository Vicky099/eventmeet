# Phase 8 — Badge Design & Printing (requirement.md §3.6): "rendered to PDF at correct DPI/page
# size" (the doc's own wording says `wicked_pdf`; requirement.md §4.10 supersedes that with
# Grover, confirmed — see that section's own note). Badge#width_cm/#height_cm feed straight into
# Grover's page-size options as physical units (Puppeteer/Chrome accept "cm" natively — no DPI
# math needed on this end), so the PDF page is always exactly the configured physical badge size,
# not a fixed A4/Letter page with the badge floating on it.
class BadgePdfService
  def self.render(badge:, participant:)
    new(badge: badge, participant: participant).render
  end

  def initialize(badge:, participant:)
    @badge = badge
    @participant = participant
  end

  def render
    html = BadgeReformService.render(badge: badge, participant: participant)
    Grover.new(
      wrap_html(html),
      width: "#{badge.width_cm}cm",
      height: "#{badge.height_cm}cm",
      margin: { top: "0", bottom: "0", left: "0", right: "0" },
      print_background: true
    ).to_pdf
  end

  private

  attr_reader :badge, :participant

  # The GrapesJS canvas exports a fragment (its own body content + a <style> block), not a full
  # document — Grover needs real HTML to load into a page.
  #
  # `position: relative` on body: every token block the badge editor offers is absolutely
  # positioned (badge_editor_controller.js — that's what makes "drop it in the middle, it stays
  # there" and resizing work at design time), which means every one of them needs a positioned
  # ancestor to anchor to. The editor sets that on its own in-canvas wrapper element for the live
  # preview, but that's a GrapesJS-internal element that isn't guaranteed to round-trip through
  # getHtml()/getCss() into the saved `content` string — this is the one guaranteed anchor,
  # applied fresh on every render regardless of what the saved content's own root element does.
  #
  # **Bug fix**: an explicit `width`/`height` on body, matching the badge's own physical size —
  # previously missing here, even though the `width`/`height` Grover options above already tell
  # Puppeteer the *paper* size to cut the PDF to. Those two are different things: paper size alone
  # doesn't constrain the *layout* viewport Puppeteer renders the page at beforehand, so
  # `background-size: cover` (below) was being computed against whatever Puppeteer's default
  # render viewport happens to be — some fixed, unrelated aspect ratio — not the real 8cm-by-10cm
  # (or whatever) badge shape, cropping the background into the wrong frame. Admin::
  # BadgesController#preview's own wrap_preview_html already sizes body this same explicit way,
  # which is exactly why that "what does this look like" preview always looked right while only
  # the actual downloaded PDF didn't — confirmed live: without this, a badge's background printed
  # visibly differently cropped than either the editor canvas or the preview modal.
  def wrap_html(fragment)
    <<~HTML
      <!DOCTYPE html>
      <html>
        <head><meta charset="utf-8"></head>
        <body style="margin:0;padding:0;position:relative;width:#{badge.width_cm}cm;height:#{badge.height_cm}cm;#{background_style}">#{fragment}</body>
      </html>
    HTML
  end

  # **Bug fix**: badge.background_image (uploaded via the badge editor's own non-canvas file
  # field) was captured and stored since Phase 8 but never applied anywhere — genuinely inert
  # until now. A full-bleed underlay on body, not a positioned/resizable canvas token like $LOGO$
  # — a background naturally covers the whole badge rather than being individually repositioned.
  # `background_size: cover` fills the exact badge dimensions regardless of the uploaded image's
  # own aspect ratio. `print_background: true` (already set on the Grover call above) is what
  # makes Chrome/Grover actually paint CSS backgrounds into the PDF at all — off by default.
  # #background_image_data_uri (HasBadgeMapping) is the same base64 `data:` URI the preview
  # modal (Admin::BadgesController#preview) now composites too — one place downloading/encoding
  # the blob, not two copies of the same logic drifting apart.
  def background_style
    data_uri = badge.background_image_data_uri
    return "" unless data_uri

    "background-image:url(#{data_uri});background-size:cover;background-position:center;"
  end
end
