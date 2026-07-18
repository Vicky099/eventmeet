module SuperAdmin
  # Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6, confirmed with the
  # user): invoices are no longer manually raised here — InvoiceGenerationJob auto-creates a
  # `draft` Invoice the day after an event ends. This controller is what's left of the Super
  # Admin's side: review the draft and #deliver it, then #verify or #reject whatever payment proof
  # the tenant submits. Plain `resources :invoices` (no nesting under Event — a stray "raise it
  # manually" surface doesn't exist anymore).
  #
  # Not named `#send` — that's Kernel#send, and ActionController itself dispatches actions via
  # `send(action_name)` internally, so a controller action literally named `send` is a real
  # foot-gun, not just a style nitpick.
  class InvoicesController < BaseController
    before_action :set_invoice, only: [ :show, :download, :deliver, :verify, :reject ]

    def index
      @invoices = Invoice.includes(:event, :account).order(created_at: :desc)
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
      redirect_to platform_invoice_path(@invoice), notice: "Invoice sent — #{@invoice.account.name} notified by email and WhatsApp."
    end

    def verify
      @invoice.verify!(by: current_platform_staff)
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
      redirect_to platform_invoice_path(@invoice), notice: "Payment rejected — tenant notified."
    end

    private

    def notify_invoice_sent(invoice)
      invoice.account.owner_users.each do |owner|
        Notifier.email(
          mailer_class: BillingMailer, mailer_method: :invoice_sent, mailer_args: [ invoice, owner.email ],
          notifiable: invoice, to: owner.email, subject: "Invoice for #{invoice.event.name}"
        )
        Notifier.whatsapp(notifiable: invoice, to: owner.contact_num,
          body: "An invoice for #{invoice.event.name} (#{invoice.amount}) is ready — sign in to review and submit payment proof.")
      end
    end

    def notify_payment_rejected(invoice)
      invoice.account.owner_users.each do |owner|
        Notifier.email(
          mailer_class: BillingMailer, mailer_method: :payment_rejected, mailer_args: [ invoice, owner.email ],
          notifiable: invoice, to: owner.email, subject: "Payment proof rejected for #{invoice.event.name}"
        )
        Notifier.whatsapp(notifiable: invoice, to: owner.contact_num,
          body: "Your payment submission for #{invoice.event.name} was rejected: #{invoice.rejection_reason}. Sign in to resubmit.")
      end
    end

    def set_invoice
      @invoice = Invoice.find(params[:id])
    end
  end
end
