# Phase 13 — Communications, revisited: the token-substitution engine for EmailTemplate, same
# shape as BadgeReformService (app/services/badge_reform_service.rb) — pure text substitution
# against a `$TOKEN$` pattern, not HTML construction; the admin's own pasted HTML already puts
# each token wherever they want it (e.g. `<img src="$LOGO$">`), this only ever replaces the token
# string itself.
#
# Used identically by the real send (ParticipantMailer#confirmation) and the admin's live preview
# (Admin::EmailTemplatesController#preview) — one rendering path, so "what you previewed" and
# "what got sent" can never diverge. participant/event/account are duck-typed: a preview passes
# unsaved, in-memory sample records (Admin::EmailTemplatesController#sample_participant/
# #sample_event) built the same way Admin::BadgesController's own sample_participant is; a real
# send passes the persisted rows.
class EmailTemplateRenderer
  TOKEN_PATTERN = /\$(PARTICIPANT_NAME|FIRST_NAME|LAST_NAME|PARTICIPANT_EMAIL|ORG_ID|
                      EVENT_NAME|EVENT_START|EVENT_END|EVENT_MEETING_LINK|EVENT_ADDRESS|
                      TENANT_NAME|LOGO|QRCODE)\$/x

  def self.render_email(subject:, html_body:, participant:, event:, account:)
    renderer = new(participant: participant, event: event, account: account)
    { subject: renderer.render(subject), html: renderer.render(html_body) }
  end

  def initialize(participant:, event:, account:)
    @participant = participant
    @event = event
    @account = account
  end

  # Unrecognized tokens are left as-is (not blanked) — a typo'd $TOKEN$ stays visibly wrong in the
  # rendered output/preview rather than silently disappearing.
  def render(text)
    text.to_s.gsub(TOKEN_PATTERN) { substitute(Regexp.last_match(1)) }
  end

  private

  attr_reader :participant, :event, :account

  def substitute(token)
    case token
    when "PARTICIPANT_NAME" then text(participant.name)
    when "FIRST_NAME" then text(participant.first_name)
    when "LAST_NAME" then text(participant.last_name)
    when "PARTICIPANT_EMAIL" then text(participant.email)
    when "ORG_ID" then text(participant.client_participant_id)
    when "EVENT_NAME" then text(event.name)
    when "EVENT_START" then text(event.starts_at&.strftime("%B %-d, %Y %H:%M"))
    when "EVENT_END" then text(event.ends_at&.strftime("%B %-d, %Y %H:%M"))
    when "EVENT_ADDRESS" then text(event.address)
    when "EVENT_MEETING_LINK" then text(event.meeting_link)
    when "TENANT_NAME" then text(account.name)
    when "LOGO" then logo_url
    # Participant#qr_code_data_uri — the deliberate exception to #logo_url's "real URL, not a
    # data: URI" reasoning below. Confirmed with the user: never upload/attach the QR anywhere (no
    # ActiveStorage blob, no Cloudinary round-trip) — it's per-participant, per-send, so persisting
    # one for every participant of every event would only ever accumulate storage for an image
    # that's cheap to regenerate and never reused past that one email. The tradeoff (some mail
    # clients block/strip inline `data:` images) is accepted deliberately, same call already made
    # for RegistrationPdfService's own PDF rendering.
    when "QRCODE" then participant.qr_code_data_uri
    end
  end

  def text(value)
    ERB::Util.html_escape(value.to_s)
  end

  # A real URL, not a base64 data: URI (BadgeReformService's own $LOGO$/$PHOTO$ substitute to
  # data URIs, but that's for a PDF render with no network access — plain HTML email has no such
  # constraint, and a real URL keeps the message small and plays better with spam filters). Blank
  # when unattached, not a broken-image placeholder — the admin's own `<img src="$LOGO$">` degrades
  # to a zero-byte src, which most email clients just render as nothing.
  def logo_url
    account.logo.attached? ? account.logo.url : ""
  end
end
