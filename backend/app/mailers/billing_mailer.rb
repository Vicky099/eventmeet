# Phase 15 — Platform Billing & Invoicing (requirement.md §4.6, §8): "the organizer is notified"
# recurs a third time here (event rejection, Phase 5; registration confirmation, Phase 13) — same
# @tenant_account convention every tenant-scoped mailer in this app already follows
# (ApplicationMailer#default_url_options needs it for the tenant-subdomain URL host), same
# Notifier/NotificationDeliveryJob tracked-delivery routing (never .deliver_later directly).
class BillingMailer < ApplicationMailer
  def quotation_amount_sent(quotation, to)
    @quotation = quotation
    @tenant_account = quotation.account

    mail(to: to, subject: "Quotation ready for \"#{quotation.event_name}\"")
  end

  def invoice_sent(invoice, to)
    @invoice = invoice
    @event = invoice.event
    @tenant_account = invoice.account

    mail(to: to, subject: "Invoice for #{@event.name}")
  end

  # Phase 15, revisited: PaymentSubmission is gone (folded onto Invoice itself) — takes the
  # Invoice directly, same as #invoice_sent, reading the rejection off `invoice.rejection_reason`.
  def payment_rejected(invoice, to)
    @invoice = invoice
    @tenant_account = invoice.account

    mail(to: to, subject: "Payment proof rejected for #{@invoice.event.name}")
  end
end
