# Phase 15 — Platform Billing & Invoicing (requirement.md §4.6, §8): "the organizer is notified"
# recurs a third time here (event rejection, Phase 5; registration confirmation, Phase 13) — same
# Notifier/NotificationDeliveryJob tracked-delivery routing (never .deliver_later directly).
#
# Fixed-hierarchy pivot (requirement.md revisit): #quotation_amount_sent is gone (no more per-event
# pricing negotiation) — #invoice_sent/#payment_rejected fire for both a per-event Invoice and an
# agency's own upfront annual-contract Invoice (Invoice#event.nil?, Invoice#agency present
# instead). Invoices moved to the Agency Console entirely (requirement.md revisit) — @tenant_agency
# is always what sets the URL host now (ApplicationMailer#default_url_options), for *either* invoice
# shape: agency_invoice_url is only ever reachable on the agency's own subdomain, never a tenant's,
# so @tenant_account would build a link that 404s/bounces even for a per-event invoice.
class BillingMailer < ApplicationMailer
  def invoice_sent(invoice, to)
    @invoice = invoice
    set_tenant_context(invoice)

    mail(to: to, subject: invoice.event ? "Invoice for #{invoice.event.name}" : "Invoice for your annual contract")
  end

  # Phase 15, revisited: PaymentSubmission is gone (folded onto Invoice itself) — takes the
  # Invoice directly, same as #invoice_sent, reading the rejection off `invoice.rejection_reason`.
  def payment_rejected(invoice, to)
    @invoice = invoice
    set_tenant_context(invoice)

    mail(to: to, subject: invoice.event ? "Payment proof rejected for #{invoice.event.name}" : "Payment proof rejected for your annual contract")
  end

  private

  def set_tenant_context(invoice)
    @tenant_agency = invoice.account&.agency || invoice.agency
  end
end
