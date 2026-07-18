module SuperAdmin
  # Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6, confirmed with the
  # user): the Super Admin's own half of the per-event pricing negotiation —
  # Admin::QuotationsController is the tenant's. #send_amount handles both the very first offer
  # and every revision after a rejection (Quotation#send_amount! doesn't distinguish either) — one
  # action, same as the tenant's #approve/#reject pairing.
  #
  # "All quotations with approved and awaiting" (sidebar spec) — #index lists every quotation, not
  # just the ones still needing action, most-recently-updated first — a negotiation (send/approve/
  # reject) touches `updated_at`, so this surfaces whatever just moved rather than whatever's
  # oldest by creation date.
  class QuotationsController < BaseController
    before_action :set_quotation, only: [ :show, :send_amount, :create_invoice ]

    def index
      @quotations = Quotation.order(updated_at: :desc)
    end

    def show
      # Real query, not the `has_one :event` association — same "don't trust `quotation.event`"
      # reasoning as Event's own `quotation_must_be_approved_and_available` comment (Rails'
      # `inverse_of` auto-detection can read back a stale in-memory assignment instead of what's
      # actually persisted); a fresh lookup by foreign key is the only reliable read here too.
      @event = Event.find_by(quotation_id: @quotation.id)
    end

    # Manual counterpart to InvoiceGenerationJob (app/jobs/invoice_generation_job.rb) — same
    # "check whether an Invoice already exists before creating one" guard that job's own
    # `.where.missing(:invoice)` scope applies, just triggered on demand by a Super Admin instead
    # of on a schedule (e.g. wanting to invoice a still-in-progress event instead of waiting for
    # the day-after-it-ends sweep — pricing is fixed via the Quotation, not participant count, so
    # there's no real computational reason to wait).
    def create_invoice
      event = Event.find_by(quotation_id: @quotation.id)

      if event.nil?
        redirect_to platform_quotation_path(@quotation), alert: "This quotation hasn't been used to create an event yet."
        return
      end

      if event.invoice.present?
        redirect_to platform_invoice_path(event.invoice), notice: "An invoice already exists for this event."
        return
      end

      invoice = Invoice.generate_for(event)
      redirect_to platform_invoice_path(invoice), notice: "Draft invoice created for \"#{event.name}\"."
    end

    def send_amount
      amount = params[:amount].to_s.strip
      currency = params[:currency].to_s.strip

      if amount.blank? || amount.to_d <= 0
        redirect_to platform_quotation_path(@quotation), alert: "Enter a valid amount."
        return
      end

      unless Currency::CODES.include?(currency)
        redirect_to platform_quotation_path(@quotation), alert: "Select a valid currency."
        return
      end

      @quotation.send_amount!(amount: amount.to_d, currency: currency)
      notify_amount_sent(@quotation)
      redirect_to platform_quotations_path, notice: "Amount sent to #{@quotation.account.name} for \"#{@quotation.event_name}\"."
    end

    private

    def set_quotation
      @quotation = Quotation.find(params[:id])
    end

    def notify_amount_sent(quotation)
      quotation.account.owner_users.each do |owner|
        Notifier.email(
          mailer_class: BillingMailer, mailer_method: :quotation_amount_sent, mailer_args: [ quotation, owner.email ],
          notifiable: quotation, to: owner.email, subject: "Quotation ready for \"#{quotation.event_name}\""
        )
        Notifier.whatsapp(notifiable: quotation, to: owner.contact_num,
          body: "A quotation for \"#{quotation.event_name}\" (#{Currency.symbol_for(quotation.currency)}#{quotation.current_amount}) is ready — sign in to review it.")
      end
    end
  end
end
