# Event Basic Info gap-fill: "Allow to send email on Attendee registration?" — a per-event toggle
# (Event#send_registration_email), checked by Participant#send_registration_confirmation! before
# this ever gets called. Mirrors EventMailer's own shape exactly (@tenant_account for the
# tenant-subdomain URL host, deliver_later via Sidekiq) — a plain confirmation, not the broader
# templated-notification system Phase 13 (Communications) still owns.
class ParticipantMailer < ApplicationMailer
  def confirmation(participant)
    @participant = participant
    @event = participant.event
    @tenant_account = @event.account

    mail(to: @participant.email, subject: "You're registered for #{@event.name}")
  end
end
