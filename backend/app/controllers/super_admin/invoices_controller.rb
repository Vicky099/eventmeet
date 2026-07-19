module SuperAdmin
  # Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6, confirmed with the
  # user): invoices are no longer manually raised here — InvoiceGenerationJob auto-creates a
  # `draft` Invoice the day after an event ends. This controller is what's left of the Super
  # Admin's side: review the draft and #deliver it, then #verify or #reject whatever payment proof
  # the tenant submits. Plain `resources :invoices` (no nesting under Event — a stray "raise it
  # manually" surface doesn't exist anymore).
  #
  # Fixed-hierarchy pivot (requirement.md revisit): also the Super Admin's side of an `annual`
  # agency's one upfront contract Invoice (Invoice#agency present, #event/#account both nil) —
  # same #deliver/#verify/#reject actions. Invoices moved to the Agency Console entirely
  # (requirement.md revisit: "we will only charge agency ... per event / Per Year") — every
  # notification below goes to the agency's own staff now, for a per-event Invoice too, not just
  # an agency-contract one; the tenant has no invoice UI left to act on at all.
  #
  # Not named `#send` — that's Kernel#send, and ActionController itself dispatches actions via
  # `send(action_name)` internally, so a controller action literally named `send` is a real
  # foot-gun, not just a style nitpick.
  class InvoicesController < BaseController
    include InvoicesHelper

    before_action :set_invoice, only: [ :show, :download, :deliver, :verify, :reject ]

    # account: :agency (not a bare :account) — the index table now shows the owning Agency as its
    # own column even for a per-event invoice, read via invoice.account.agency; without eager
    # loading that association too, every per-event row would fire its own extra query for it.
    def index
      @invoices = Invoice.includes(:event, :agency, account: :agency).order(created_at: :desc)
    end

    def show
    end

    def download
      html = render_to_string(:pdf, formats: [ :html ], layout: false)
      pdf = InvoicePdfService.render(html: html)
      send_data pdf, filename: "invoice-#{@invoice.id[0..7].upcase}.pdf", type: "application/pdf", disposition: "attachment"
    end

    def deliver
      @invoice.send!
      notify_invoice_sent(@invoice)
      AuditLog.record!(actor: current_platform_staff, action: "invoice.deliver", target: @invoice,
        metadata: { amount: @invoice.amount, currency: @invoice.currency })
      redirect_to platform_invoice_path(@invoice), notice: "Invoice sent — #{invoice_recipient_label(@invoice)} notified."
    end

    def verify
      @invoice.verify!(by: current_platform_staff)
      AuditLog.record!(actor: current_platform_staff, action: "invoice.verify", target: @invoice,
        metadata: { amount: @invoice.amount, currency: @invoice.currency })
      redirect_to platform_invoice_path(@invoice), notice: "Payment verified — invoice marked paid."
    end

    def reject
      reason = params[:rejection_reason].to_s.strip

      if reason.blank?
        redirect_to platform_invoice_path(@invoice), alert: "A reason for rejecting the payment is required."
        return
      end

      @invoice.reject_payment!(reason: reason, by: current_platform_staff)
      notify_payment_rejected(@invoice)
      AuditLog.record!(actor: current_platform_staff, action: "invoice.reject", target: @invoice, metadata: { reason: reason })
      redirect_to platform_invoice_path(@invoice), notice: "Payment rejected — #{invoice_recipient_label(@invoice).downcase} notified."
    end

    private

    # Notifier.email/#whatsapp both create a Notification row, TenantScoped (belongs_to :account,
    # non-optional) — an agency-contract Invoice has no account to attribute one to, same reasoning
    # AgencyMailer's own class comment already established for why it bypasses Notifier entirely.
    # A per-event invoice keeps the exact same tracked-delivery + WhatsApp path as before (still
    # attributed to invoice.account for audit purposes via Notifier's own `account:
    # notifiable.account` default) — only the recipient list changed, from the tenant's own admins
    # to the agency's own staff (invoice.account.agency.users). An agency-contract invoice sends
    # the email directly, unchanged (no WhatsApp — Notifier.whatsapp has the same TenantScoped
    # blocker, and this is a rare enough event not to warrant a second, parallel untracked-WhatsApp
    # path just for it).
    def notify_invoice_sent(invoice)
      if invoice.account
        invoice.account.agency.users.each do |user|
          Notifier.email(
            mailer_class: BillingMailer, mailer_method: :invoice_sent, mailer_args: [ invoice, user.email ],
            notifiable: invoice, to: user.email, subject: "Invoice for #{invoice.event.name}"
          )
          Notifier.whatsapp(notifiable: invoice, to: user.contact_num,
            body: "An invoice for #{invoice.event.name} (#{invoice.amount}) is ready — sign in to review and submit payment proof.")
        end
      else
        invoice.agency.users.each { |user| BillingMailer.invoice_sent(invoice, user.email).deliver_later }
      end
    end

    def notify_payment_rejected(invoice)
      if invoice.account
        invoice.account.agency.users.each do |user|
          Notifier.email(
            mailer_class: BillingMailer, mailer_method: :payment_rejected, mailer_args: [ invoice, user.email ],
            notifiable: invoice, to: user.email, subject: "Payment proof rejected for #{invoice.event.name}"
          )
          Notifier.whatsapp(notifiable: invoice, to: user.contact_num,
            body: "Your payment submission for #{invoice.event.name} was rejected: #{invoice.rejection_reason}. Sign in to resubmit.")
        end
      else
        invoice.agency.users.each { |user| BillingMailer.payment_rejected(invoice, user.email).deliver_later }
      end
    end

    def set_invoice
      @invoice = Invoice.find(params[:id])
    end
  end
end
