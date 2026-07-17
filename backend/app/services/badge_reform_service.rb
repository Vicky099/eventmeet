require "rqrcode"
require "barby"
require "barby/barcode/code_128"
require "barby/outputter/png_outputter"
require "chunky_png"

# Phase 8 — Badge Design & Printing (requirement.md §3.6): "token-based badge templating engine
# that substitutes placeholders with live participant data, QR/barcodes, and images (base64-inlined
# for PDF rendering)." Pure text substitution, not HTML construction — the GrapesJS canvas is what
# puts a token inside real markup in the first place (e.g. `<img src="$PHOTO$">`), so this only
# ever needs to replace the token string itself with either escaped text or a `data:` URI, never
# build a new element. That keeps this service trivially testable against any `content` string,
# independent of whatever the editor actually generated around it.
#
# Two independent scannable-code slots (requirement.md §3.6: "an internal ID code and a separate
# government-ID code"): $QRCODE$ always encodes the participant's own `hex_id` (globally unique,
# what a check-in scanner looks up directly — see Participant); $BARCODE$ encodes their
# `govt_id`, falling back to `client_participant_id` when no govt ID was collected. Both stay
# exactly as-is (existing badges/check-in scanning depend on this) — the $QRCODE_GOVT_ID$/
# $QRCODE_ORG_ID$/$BARCODE_GOVT_ID$/$BARCODE_ORG_ID$ variants below are additive, for a badge
# that wants a code encoding one specific field rather than the generic scan-anywhere hex_id.
class BadgeReformService
  TOKEN_PATTERN = /\$(NAME|TITLE|FIRST_NAME|LAST_NAME|DESIGNATION|ORG_ID|GOVT_ID|PHOTO|LOGO|
                      QRCODE_GOVT_ID|QRCODE_ORG_ID|QRCODE|BARCODE_GOVT_ID|BARCODE_ORG_ID|BARCODE|
                      OTHER1|OTHER2|OTHER3)\$/x

  # A 1x1 transparent PNG — what $PHOTO$/$LOGO$ substitute to when nothing is attached, so the
  # badge still renders a valid (empty) image instead of a broken-image icon.
  #
  # **Found and fixed via the badge-preview modal (admin/badges/_badges_table.html.erb)**: the
  # base64 string here decoded to a fully *opaque black* pixel (r=0 g=0 b=0 a=255, confirmed with
  # ChunkyPNG — already a dependency, via barby/rqrcode), not a transparent one — every real
  # participant printed without a photo attached has been getting a solid black square on their
  # badge, not a blank one, since Phase 8. The spec covering this (badge_reform_service_spec.rb)
  # only ever asserted the first 8 bytes matched the generic PNG file-signature magic number
  # (`137,80,78,71,13,10,26,10` — true of *any* valid PNG, transparent or not), never the actual
  # pixel color/alpha, so a genuinely opaque "blank" pixel passed it undetected the whole time —
  # nothing before this feature ever rendered $PHOTO$'s fallback somewhere a human would actually
  # look at it (prior coverage checked PDF *byte content*, never a rendered/visually-inspected
  # image). Regenerated with `ChunkyPNG::Image.new(1, 1, ChunkyPNG::Color::TRANSPARENT).to_blob`
  # and confirmed via the same ChunkyPNG round-trip that this one actually decodes to a=0.
  BLANK_PIXEL_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNiYAAAAAkAAxkR2eQAAAAASUVORK5CYII="
  )

  # Admin::BadgesController#preview's `sample:` flag (below) substitutes these instead of
  # BLANK_PIXEL_PNG for $PHOTO$/unattached $LOGO$ — a synthetic preview participant never has a
  # real photo (nothing ever attaches one; see that controller's own comment), and most badges
  # never get a real logo attached either now that Badge#logo has no organizer-facing upload field
  # of its own (app/views/admin/shared/_badge_editor.html.erb — kept for a future tenant-level
  # logo). Rendering both as blank/transparent in the *preview* made a badge that actually uses
  # either token look broken or empty at a glance, even though a real print (sample: false, the
  # default — unaffected by any of this) correctly still shows nothing for a genuinely-unset field.
  # Drawn with ChunkyPNG (already a dependency, via barby/rqrcode) rather than rasterizing the
  # design canvas's own SVG placeholders (badge_editor_controller.js's TOKEN_PLACEHOLDER_SVGS) —
  # no SVG-to-PNG path exists server-side, and the same simple shapes are trivial to redraw
  # directly; both are deliberately styled to match those SVGs (same #e9ecef/#adb5bd palette) so
  # the design canvas and this preview don't visually disagree about what an empty slot looks like.
  SAMPLE_PHOTO_PNG = begin
    canvas = ChunkyPNG::Canvas.new(100, 100, ChunkyPNG::Color.from_hex("#e9ecef"))
    canvas.circle(32, 30, 11, ChunkyPNG::Color::TRANSPARENT, ChunkyPNG::Color.from_hex("#adb5bd"))
    # Flat x,y pairs, not an array of [x, y] pairs — ChunkyPNG::Vector's own `multiple_from_array`
    # (1.4.0) only branches correctly on a flat numeric array or a string; handed an array of
    # 2-element arrays it falls through to a `=~` call on an Array, which raises NoMethodError.
    canvas.polygon([ 8, 82, 38, 48, 58, 68, 74, 52, 92, 82 ], ChunkyPNG::Color::TRANSPARENT, ChunkyPNG::Color.from_hex("#adb5bd"))
    canvas.to_blob
  end.freeze

  SAMPLE_LOGO_PNG = begin
    canvas = ChunkyPNG::Canvas.new(100, 100, ChunkyPNG::Color.from_hex("#e9ecef"))
    canvas.circle(50, 42, 20, ChunkyPNG::Color.from_hex("#adb5bd"), ChunkyPNG::Color::TRANSPARENT)
    canvas.to_blob
  end.freeze

  # `sample:` only ever changes what an *unattached* $PHOTO$/$LOGO$ substitutes to — a real
  # photo/logo, when one is attached, always wins regardless of this flag; see #photo_data_uri/
  # #logo_data_uri. Admin::BadgesController#preview is the only caller that ever passes true.
  def self.render(badge:, participant:, sample: false)
    new(badge: badge, participant: participant, sample: sample).render
  end

  def initialize(badge:, participant:, sample: false)
    @badge = badge
    @participant = participant
    @sample = sample
  end

  def render
    badge.content.to_s.gsub(TOKEN_PATTERN) { substitute(Regexp.last_match(1)) }
  end

  private

  attr_reader :badge, :participant, :sample

  def substitute(token)
    case token
    when "NAME" then text(participant.name)
    when "TITLE" then text(participant.title)
    when "FIRST_NAME" then text(participant.first_name)
    when "LAST_NAME" then text(participant.last_name)
    when "DESIGNATION" then text(participant.position)
    when "ORG_ID" then text(participant.client_participant_id)
    when "GOVT_ID" then text(participant.govt_id)
    when "PHOTO" then photo_data_uri
    when "LOGO" then logo_data_uri
    when "QRCODE" then data_uri(qr_png(participant.hex_id.to_s), "image/png")
    when "QRCODE_GOVT_ID" then data_uri(qr_png(participant.govt_id.to_s), "image/png")
    when "QRCODE_ORG_ID" then data_uri(qr_png(participant.client_participant_id.to_s), "image/png")
    when "BARCODE" then data_uri(barcode_png(barcode_value), "image/png")
    when "BARCODE_GOVT_ID" then data_uri(barcode_png(participant.govt_id.to_s), "image/png")
    when "BARCODE_ORG_ID" then data_uri(barcode_png(participant.client_participant_id.to_s), "image/png")
    when "OTHER1", "OTHER2", "OTHER3" then other_field_value(token)
    end
  end

  def text(value)
    ERB::Util.html_escape(value.to_s)
  end

  def other_field_value(token)
    field = badge.mapping[token]
    return "" if field.blank? || !HasBadgeMapping::MAPPABLE_FIELDS.include?(field)

    text(participant.public_send(field))
  end

  def barcode_value
    participant.govt_id.presence || participant.client_participant_id.to_s
  end

  def photo_data_uri
    return data_uri(participant.photo.download, participant.photo.blob.content_type) if participant.photo.attached?
    return data_uri(SAMPLE_PHOTO_PNG, "image/png") if sample

    data_uri(BLANK_PIXEL_PNG, "image/png")
  end

  # badge.logo (uploaded via the badge editor's own non-canvas file field, app/views/admin/shared/
  # _badge_editor.html.erb) — was captured and stored since Phase 8 but never actually rendered
  # anywhere until now; $LOGO$ is what makes it a real, positionable/resizable canvas token, the
  # same shape $PHOTO$ already has.
  def logo_data_uri
    return data_uri(badge.logo.download, badge.logo.blob.content_type) if badge.logo.attached?
    return data_uri(SAMPLE_LOGO_PNG, "image/png") if sample

    data_uri(BLANK_PIXEL_PNG, "image/png")
  end

  def qr_png(data)
    RQRCode::QRCode.new(data.presence || " ").as_png(size: 240).to_s
  end

  def barcode_png(data)
    Barby::Code128B.new(data.presence || " ").to_png(xdim: 2, height: 60)
  end

  def data_uri(binary, content_type)
    "data:#{content_type};base64,#{Base64.strict_encode64(binary)}"
  end
end
