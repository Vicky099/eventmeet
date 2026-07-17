# Phase 13 — Communications (requirement.md §3.10, §5.10). The one job that actually performs a
# tracked send, for either channel — see Notifier's own comment for why this replaces
# ActionMailer's `.deliver_later` entirely for tracked mail rather than wrapping it.
#
# mailer_class/mailer_method/mailer_args are only present for channel: email — re-invokes the
# mailer action exactly the way `SomeMailer.method(*args).deliver_now` would, just wrapped so the
# Notification row gets updated either way.
#
# Deliberately swallows the error after marking `failed` rather than re-raising into Sidekiq's own
# retry/Dead-set — requirement.md's own "one failing doesn't block the other" is about one
# recipient/channel's failure never blocking a *different* recipient/channel's send (already true:
# each is its own independent Notifier call/job), not about auto-retrying a WhatsApp send whose
# most common failure mode in this app (no Gupshup credential configured, or a recipient with no
# contact_num on file) is permanent, not transient. The Notification row itself — pending/sent/
# failed, with error_message — is the durable, inspectable record either way.
class NotificationDeliveryJob < ApplicationJob
  queue_as :default

  def perform(notification_id, mailer_class: nil, mailer_method: nil, mailer_args: nil)
    notification = Notification.unscoped_across_tenants { Notification.find(notification_id) }
    Current.account = notification.account

    case notification.channel
    when "email"
      mailer_class.constantize.public_send(mailer_method, *mailer_args).deliver_now
    when "whatsapp"
      GupshupClient.new.send_message(to: notification.to, body: notification.body)
    end

    notification.mark_sent!
  rescue StandardError => e
    Rails.logger.error("[NotificationDeliveryJob] #{notification.channel} ##{notification.id} failed: #{e.class}: #{e.message}")
    notification.mark_failed!(e)
  end
end
