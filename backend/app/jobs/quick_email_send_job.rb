# Phase 13 — Communications, revisited: "Quick Email Send" — clicking the modal's "Send" button
# (Admin::EmailTemplatesController#quick_send) enqueues this rather than looping over participants
# inline in the request, the way Admin::ParticipantsController#send_to_pending does for the
# (much smaller, status-filtered) pending list — a whole event's participant list can be large
# enough that doing this synchronously in a web request risks a timeout, and "enqueue" was the
# explicit ask.
#
# Takes `event_id`/`kind`, not an EmailTemplate id — "Participant Registration Confirmation needed
# in the quick send" (EmailTemplate::ALWAYS_SENDABLE_KINDS) means :participant_registration must be
# sendable even with *no* EmailTemplate row (the built-in confirmation view), so there isn't always
# a single row id to key off of the way the original :quick_send-only version of this job did.
#
# Each individual send is still its own independent Notifier.email call/NotificationDeliveryJob
# underneath (Participant#deliver_confirmation_email / #deliver_quick_email!) — this job's only job
# is the fan-out, not the delivery itself, so one participant's bad email address failing delivery
# can never block the rest of the send.
class QuickEmailSendJob < ApplicationJob
  queue_as :default

  def perform(event_id, kind)
    event = Event.unscoped_across_tenants { Event.find(event_id) }
    Current.account = event.account

    event.participants.find_each { |participant| deliver(participant, event, kind) }
  end

  private

  # :participant_registration reuses the exact same send a real registration/#resend triggers —
  # custom template if one's configured, the built-in view otherwise, PDF+QR attachment included
  # either way — so "resend the registration email to everyone" looks identical to what each
  # participant already got (or would get) at registration time. Every other kind has no built-in
  # fallback (ALWAYS_SENDABLE_KINDS), so it's skipped here if it's since been deactivated/removed
  # out from under an already-enqueued job — Admin::EmailTemplatesController#quick_send already
  # checked it was configured at enqueue time, but a job can run some time later.
  def deliver(participant, event, kind)
    if kind == "participant_registration"
      participant.deliver_confirmation_email
    else
      email_template = event.email_templates.find_by(kind: kind, active: true)
      participant.deliver_quick_email!(email_template) if email_template
    end
  end
end
