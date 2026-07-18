module Admin
  # Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6, confirmed with the
  # user): the tenant's own view of what's been invoiced against their events, plus the "Mark as
  # Paid" flow — folded directly onto Invoice (no separate PaymentSubmission model/controller in
  # the simplified design; #submit_payment is this controller's own member action, driven by a
  # modal from #index, exactly as specified: "the button will open the modal to add UTR and show
  # the platform config bank account details ... attach the transaction image/pdf ... mark as paid
  # will submit the invoice for verification to super admin.")
  class InvoicesController < BaseController
    before_action :set_invoice, only: [ :show, :submit_payment ]

    # Invoice belongs_to :account (TenantScoped) but has no Account#has_many :invoices — it
    # cascades transitively through Account#has_many :events instead (same reasoning Notification
    # already established: a plain query relies on TenantScoped's own default_scope for isolation,
    # no extra association needed just to reach it).
    #
    # Excludes `draft` — a draft is only the Super Admin's own working copy (auto-created by
    # InvoiceGenerationJob or the manual "Create Invoice" action) before they've reviewed and
    # `#send!`d it; the tenant has no business seeing an invoice that hasn't actually been sent to
    # them yet.
    def index
      authorize Invoice
      @invoices = Invoice.includes(:event).where.not(status: :draft).order(created_at: :desc)
    end

    def show
      authorize @invoice

      redirect_to admin_invoices_path, alert: "That invoice hasn't been sent yet." if @invoice.draft?
    end

    def submit_payment
      authorize @invoice, :update?
      utr_reference = params[:utr_reference].to_s.strip

      if utr_reference.blank?
        redirect_to admin_invoices_path, alert: "Enter the UTR/reference number from your bank transfer."
        return
      end

      @invoice.submit_payment!(utr_reference: utr_reference, receipt: params[:receipt], by: current_user)
      redirect_to admin_invoices_path, notice: "Payment submitted for \"#{@invoice.event.name}\" — a Super Admin will verify it shortly."
    end

    private

    def set_invoice
      @invoice = Invoice.find(params[:id])
    end
  end
end
