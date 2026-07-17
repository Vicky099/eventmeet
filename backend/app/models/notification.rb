# Phase 13 — Communications (requirement.md §3.10, §5.10, §8). One row per actual delivery
# attempt, on either channel — see this table's own migration for the full "why polymorphic
# notifiable + plain `to` string" rationale. Created and progressed exclusively through
# Notifier/NotificationDeliveryJob (app/services/notifier.rb, app/jobs/notification_delivery_job.rb)
# — never construct/update one directly from a controller or mailer.
class Notification < ApplicationRecord
  include TenantScoped

  belongs_to :notifiable, polymorphic: true

  enum :channel, { email: 0, whatsapp: 1 }
  enum :status, { pending: 0, sent: 1, failed: 2 }

  validates :to, presence: true

  def mark_sent!
    update!(status: :sent, sent_at: Time.current, error_message: nil)
  end

  def mark_failed!(error)
    update!(status: :failed, error_message: error.message.to_s.truncate(1000))
  end
end
