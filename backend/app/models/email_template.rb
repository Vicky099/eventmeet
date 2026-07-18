# Phase 13 — Communications, revisited (requirement.md §3.10, §5.10): per-event customizable
# email, mirroring BadgeTemplate/HasBadgeMapping's own "reusable content with $TOKEN$ placeholders"
# shape (app/models/badge_template.rb, app/models/concerns/has_badge_mapping.rb) rather than
# inventing a second templating convention. Scoped to Event (belongs_to :event below), not the
# tenant as a whole — confirmed with the user: a tenant running several events wants a different
# registration email per event, not one shared template across all of them, so this is Badge's own
# "per-event instantiation, account_id still carried directly for TenantScoped" shape, not
# BadgeTemplate's "one freeform library" shape. This is one row per `kind` per event — `kind` names
# *which* triggered email is being customized, not an arbitrary template name, so a second row for
# the same kind on the same event would just be ambiguous (the unique index below enforces that).
# `active` lets an admin flip back to the built-in default without losing their drafted HTML — the
# row itself is only ever deleted via the "Reset to Default" action
# (Admin::EmailTemplatesController#destroy).
#
# :participant_registration fires automatically (ParticipantMailer#confirmation, at registration
# time); :quick_send (added below) never fires on its own — it's the freeform "send any email to
# the participants" kind, triggered on demand from the "Quick Email Send" button/modal on this
# index page (Admin::EmailTemplatesController#quick_send, QuickEmailSendJob) rather than any
# lifecycle event. Both go through the same EmailTemplateRenderer/ParticipantMailer machinery —
# the enum/KIND_* maps below are what make adding a *third* kind later (event-rejection,
# resend-invitation, another on-demand one, ...) a new enum value + a mailer branch, not a schema
# change or a new admin UI; #index already iterates EmailTemplate.kinds.keys generically.
class EmailTemplate < ApplicationRecord
  include TenantScoped

  belongs_to :event

  enum :kind, { participant_registration: 0, quick_send: 1 }

  validates :kind, presence: true, uniqueness: { scope: :event_id }
  validates :subject, presence: true, length: { maximum: 255 }
  validates :html_body, presence: true

  KIND_LABELS = {
    "participant_registration" => "Participant Registration Confirmation",
    "quick_send" => "Quick Email"
  }.freeze

  # "Quick Email Send" modal (Admin::EmailTemplatesController#index/#quick_send) — which kinds are
  # offered *without* first needing a configured, active EmailTemplate row. :participant_registration
  # always has real content to broadcast even with no row at all (the built-in confirmation view,
  # ParticipantMailer#confirmation's own default branch) — a bulk "resend the registration email to
  # everyone" is meaningful whether or not the tenant ever customized it. Every other kind (starting
  # with :quick_send) has no such built-in fallback — its default seed is just placeholder copy
  # ("Write your message here") — so it only becomes sendable once an admin has actually configured
  # and activated one; see #index's own @sendable_kinds.
  ALWAYS_SENDABLE_KINDS = %w[participant_registration].freeze

  # Every kind currently understands the exact same token set — EmailTemplateRenderer's
  # TOKEN_PATTERN isn't actually scoped per kind, this is purely "which of those are meaningful
  # here" documentation for the editor's placeholder cheat-sheet (Admin::EmailTemplatesController
  # #edit). Shared as one constant rather than duplicated per kind now that a second kind needs the
  # identical list; a future kind with a genuinely different set would just get its own array here.
  GENERIC_PLACEHOLDERS = %w[
    PARTICIPANT_NAME FIRST_NAME LAST_NAME PARTICIPANT_EMAIL ORG_ID
    EVENT_NAME EVENT_START EVENT_END EVENT_ADDRESS EVENT_MEETING_LINK
    TENANT_NAME LOGO QRCODE
  ].freeze

  KIND_PLACEHOLDERS = {
    "participant_registration" => GENERIC_PLACEHOLDERS,
    "quick_send" => GENERIC_PLACEHOLDERS
  }.freeze

  # A tasteful starting point (see app/views/participant_mailer/confirmation.html.erb for the
  # visual language this echoes) — prefilled into the editor the first time an admin opens a kind
  # that has no row yet (Admin::EmailTemplatesController#set_email_template), so "customize this
  # email" starts from something that already looks good, not a blank textarea.
  DEFAULT_TEMPLATES = {
    "participant_registration" => {
      subject: "You're registered for $EVENT_NAME$",
      html_body: <<~HTML
        <!DOCTYPE html>
        <html>
          <head><meta http-equiv="Content-Type" content="text/html; charset=utf-8"></head>
          <body style="margin:0;padding:0;background:#f4f5f7;font-family:Helvetica,Arial,sans-serif;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f5f7;padding:32px 0;">
              <tr>
                <td align="center">
                  <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:8px;overflow:hidden;">
                    <tr>
                      <td style="background:#1f58c7;padding:28px 32px;text-align:center;">
                        <img src="$LOGO$" alt="$TENANT_NAME$" style="max-height:48px;">
                      </td>
                    </tr>
                    <tr>
                      <td style="padding:32px;">
                        <h1 style="margin:0 0 16px;font-size:22px;color:#1a1a1a;">You're registered for $EVENT_NAME$</h1>
                        <p style="margin:0 0 24px;font-size:15px;color:#4a4a4a;">Hi $FIRST_NAME$, your registration is confirmed. Here are the details:</p>
                        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f5f7;border-radius:6px;">
                          <tr><td style="padding:20px 24px;font-size:14px;color:#333;line-height:1.8;">
                            <strong>When:</strong> $EVENT_START$ &ndash; $EVENT_END$<br>
                            <strong>Where:</strong> $EVENT_ADDRESS$<br>
                            <strong>Meeting link:</strong> $EVENT_MEETING_LINK$<br>
                            <strong>Your registration ID:</strong> $ORG_ID$
                          </td></tr>
                        </table>
                        <p style="margin:24px 0 0;font-size:15px;color:#4a4a4a;">See you there!</p>
                      </td>
                    </tr>
                    <tr>
                      <td style="padding:24px 0;text-align:center;border-top:1px solid #eeeeee;">
                        <p style="font-size:13px;color:#8a8a8a;margin:0 0 12px;">Show this QR code at check-in</p>
                        <img src="$QRCODE$" alt="QR code" style="width:160px;height:160px;">
                      </td>
                    </tr>
                    <tr>
                      <td style="padding:16px 32px;background:#f4f5f7;text-align:center;font-size:12px;color:#8a8a8a;">
                        Sent by $TENANT_NAME$
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>
            </table>
          </body>
        </html>
      HTML
    },
    # Deliberately generic — this kind isn't about any one lifecycle moment, so the starting point
    # is just the same branded shell with an editable placeholder paragraph, not registration-
    # specific copy like the details table/QR section above.
    "quick_send" => {
      subject: "A message from $TENANT_NAME$",
      html_body: <<~HTML
        <!DOCTYPE html>
        <html>
          <head><meta http-equiv="Content-Type" content="text/html; charset=utf-8"></head>
          <body style="margin:0;padding:0;background:#f4f5f7;font-family:Helvetica,Arial,sans-serif;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f5f7;padding:32px 0;">
              <tr>
                <td align="center">
                  <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:8px;overflow:hidden;">
                    <tr>
                      <td style="background:#1f58c7;padding:28px 32px;text-align:center;">
                        <img src="$LOGO$" alt="$TENANT_NAME$" style="max-height:48px;">
                      </td>
                    </tr>
                    <tr>
                      <td style="padding:32px;">
                        <h1 style="margin:0 0 16px;font-size:22px;color:#1a1a1a;">A message about $EVENT_NAME$</h1>
                        <p style="margin:0 0 24px;font-size:15px;color:#4a4a4a;">Hi $FIRST_NAME$,</p>
                        <p style="margin:0 0 24px;font-size:15px;color:#4a4a4a;">Write your message here.</p>
                      </td>
                    </tr>
                    <tr>
                      <td style="padding:16px 32px;background:#f4f5f7;text-align:center;font-size:12px;color:#8a8a8a;">
                        Sent by $TENANT_NAME$
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>
            </table>
          </body>
        </html>
      HTML
    }
  }.freeze

  def label
    KIND_LABELS.fetch(kind)
  end

  def placeholders
    KIND_PLACEHOLDERS.fetch(kind, [])
  end
end
