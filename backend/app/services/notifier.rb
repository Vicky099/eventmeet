# Phase 13 — Communications (requirement.md §3.10, §5.10). The single entry point every mailer
# call site in this app routes through — "reused by every mailer already built in earlier phases"
# is the phase's own checklist wording, not just the new WhatsApp send. Deliberately does NOT lean
# on ActionMailer's own `.deliver_later` for the tracked, async part of the work: `.deliver_later`
# re-invokes the *entire* mailer action inside its own job, with no way to thread a Notification
# id through that boundary and update it afterward. Instead, NotificationDeliveryJob is itself the
# one and only async unit — it calls `.deliver_now` synchronously *inside* itself (already running
# async via Sidekiq, so nothing is lost) and updates the same row it was handed.
class Notifier
  # account: explicit, not inferred as `notifiable.account` — that works for Event/Participant
  # (both belong_to :account via TenantScoped) but not for AccountMailer#welcome, whose notifiable
  # *is* the Account itself (which has no #account method of its own). Every call site already
  # knows which tenant it's acting for, so there's no real cost to asking for it explicitly rather
  # than duck-typing around that one exception.
  #
  # mailer_args must be ActiveJob-serializable (GlobalID handles plain AR records automatically,
  # same as any other `perform_later` argument elsewhere in this app).
  def self.email(mailer_class:, mailer_method:, mailer_args:, notifiable:, to:, account: notifiable.account, subject: nil)
    notification = Notification.create!(
      account: account, notifiable: notifiable, channel: :email, to: to, subject: subject, status: :pending
    )
    NotificationDeliveryJob.perform_later(notification.id, mailer_class: mailer_class.name, mailer_method: mailer_method.to_s, mailer_args: mailer_args)
    notification
  end

  # requirement.md §8: "sent via Gupshup... to the recipient User's own contact_num field." A
  # blank `to` (no contact_num on file for this recipient) still creates the row — Notification's
  # own `to` presence validation means a placeholder string, not a literal blank, so the gap is
  # visible in the notification's own history/status — but skips enqueueing a job that could only
  # ever fail — GupshupClient itself would raise DeliveryError for that exact case anyway, so this
  # is the same outcome one step earlier, without spending a Sidekiq attempt on it.
  def self.whatsapp(notifiable:, to:, body:, account: notifiable.account)
    notification = Notification.create!(
      account: account, notifiable: notifiable, channel: :whatsapp, to: to.presence || "(no contact number on file)", body: body,
      status: to.present? ? :pending : :failed, error_message: to.present? ? nil : "recipient has no contact number on file"
    )
    NotificationDeliveryJob.perform_later(notification.id) if to.present?
    notification
  end
end
