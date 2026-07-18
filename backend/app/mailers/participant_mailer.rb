# Event Basic Info gap-fill: "Allow to send email on Attendee registration?" — a per-event toggle
# (Event#send_registration_email), checked by Participant#send_registration_confirmation! before
# this ever gets called. Mirrors EventMailer's own shape exactly (@tenant_account for the
# tenant-subdomain URL host, deliver_later via Sidekiq).
#
# Phase 13 — Communications, revisited: "admin ask to have a customized email template for
# participant registration," confirmed scoped per event, not shared across a tenant's events. When
# this event has an active EmailTemplate for this kind, its subject/html_body (with $TOKEN$s filled
# in by EmailTemplateRenderer) fully replace the built-in view below — `layout: false` because the
# admin pastes a *complete* HTML document, not a fragment to drop into layouts/mailer.html.erb. No
# plain-text alternative is generated for a custom template (the admin only ever supplies HTML) —
# the default branch below keeps its own confirmation.text.erb.
#
# Further revisited: "each email we send the attachment as well ... in PDF show same email
# template + QRcode for scanning purpose" — every send now also carries a PDF (RegistrationPdfService)
# built from whichever HTML is actually going out as the body (custom or default), so the
# attachment always matches what the recipient sees. The QR itself (Participant#qr_code_data_uri)
# lives inside that HTML now — the built-in view renders it directly, and a custom EmailTemplate
# gets it via the `$QRCODE$` placeholder (EmailTemplateRenderer) — so the PDF picks it up for free
# with no QR-specific logic of its own.
class ParticipantMailer < ApplicationMailer
  def confirmation(participant)
    @participant = participant
    @event = participant.event
    @tenant_account = @event.account
    @email_template = @event.email_templates.find_by(kind: :participant_registration, active: true)

    if @email_template
      rendered = EmailTemplateRenderer.render_email(
        subject: @email_template.subject, html_body: @email_template.html_body,
        participant: @participant, event: @event, account: @tenant_account
      )
      attach_registration_pdf(rendered[:html])

      mail(to: @participant.email, subject: rendered[:subject]) do |format|
        format.html { render html: rendered[:html].html_safe, layout: false }
      end
    else
      # Attachments must be declared before `mail` is called (they're collected into the message
      # as `mail` builds it, not appendable after — confirmed live: adding one post hoc directly to
      # the Mail::Message `mail` returns silently discards the original body instead of promoting
      # it to multipart) — so the built-in view is rendered here, once, purely to get the HTML the
      # PDF needs; `mail(...)` below still renders confirmation.html.erb/.text.erb itself the
      # normal, implicit way to actually build the outgoing message. Rendering the view twice per
      # send is a deliberate, cheap trade for not restructuring the default branch's own multipart
      # rendering.
      #
      # Both `ActiveStorage::Current.url_options` and `Time.use_zone` below mirror exactly what
      # ApplicationMailer#mail itself applies once `mail(...)` runs — needed here too since this
      # pre-render happens before that. `Time.use_zone` isn't just cosmetic for the PDF: starts_at/
      # ends_at are time_zone_aware_attributes, cast and *cached* on first read under whatever
      # Time.zone is ambient at that moment (this file's own "renders the event schedule in the
      # account's own timezone" spec, below) — reading them here under the wrong (default) zone,
      # unguarded, would poison that cached value for the *real* email body too, rendered moments
      # later by mail()'s own Time.use_zone block, showing the wrong time to the recipient.
      ActiveStorage::Current.url_options = default_url_options
      html_for_pdf = Time.use_zone(@tenant_account.time_zone) { render_to_string(:confirmation, formats: [ :html ]) }
      attach_registration_pdf(html_for_pdf)

      mail(to: @participant.email, subject: "You're registered for #{@event.name}")
    end
  end

  # Phase 13 — Communications, revisited: "Quick Email Send" — a broadcast, kind-agnostic send.
  # `email_template` is whichever row the admin picked in the modal (Admin::
  # EmailTemplatesController#quick_send) — could be :quick_send or, deliberately (confirmed with
  # the user), :participant_registration itself, re-blasted to everyone rather than resent one
  # participant at a time. Same custom-template rendering shape #confirmation's own custom branch
  # uses (EmailTemplateRenderer, single-part HTML, layout: false), but with no PDF attachment — a
  # broadcast announcement isn't a check-in credential the way the registration email is.
  def quick_email(participant, email_template)
    @participant = participant
    @event = participant.event
    @tenant_account = @event.account
    @email_template = email_template

    rendered = EmailTemplateRenderer.render_email(
      subject: email_template.subject, html_body: email_template.html_body,
      participant: @participant, event: @event, account: @tenant_account
    )

    mail(to: @participant.email, subject: rendered[:subject]) do |format|
      format.html { render html: rendered[:html].html_safe, layout: false }
    end
  end

  private

  def attach_registration_pdf(html)
    attachments["registration-#{@participant.hex_id}.pdf"] = {
      mime_type: "application/pdf",
      content: RegistrationPdfService.render(html: html)
    }
  end
end
