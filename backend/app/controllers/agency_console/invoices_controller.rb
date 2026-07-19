module AgencyConsole
  # Invoices moved to the Agency Console entirely (requirement.md revisit) — the agency's own view
  # of every Invoice it's responsible for: its one upfront annual-contract Invoice
  # (Agency#invoice, Invoice.generate_for_agency_contract) for an `annual` agency, or every
  # per-event Invoice across all of its own tenants for a `per_event` one (Invoice.for_agency
  # covers both shapes at once — that model method's own comment has the full reasoning). Plus the
  # "Mark as Paid" flow — mirrors what used to be Admin::InvoicesController's own #show/
  # #submit_payment almost exactly, just scoped to Current.agency instead of a tenant's Account.
  class InvoicesController < BaseController
    before_action :set_invoice, only: [ :show, :submit_payment, :download ]

    # Excludes `draft` — same reasoning the tenant-side controller this replaced already had: a
    # draft is only the Super Admin's own working copy before they've #send!'d it.
    #
    # Event.unscoped_across_tenants — TenantScoped's default_scope only recognizes Current.account
    # and Current.platform_request; an agency subdomain request is neither (Current.agency is set
    # instead), so eager-loading :event across more than one of this agency's own tenant Accounts
    # hits the exact same gap AgencyConsole::DashboardController#index already hit and fixed —
    # narrow, not a real cross-agency leak, since Invoice.for_agency already scoped the invoices
    # themselves to this agency alone; `.load` forces the preload to run inside the block, before
    # Current.platform_request reverts on return, so the view's later @invoice.event/.each reads
    # (already-cached, no new query) never re-trigger the guard.
    def index
      @invoices = Event.unscoped_across_tenants do
        Invoice.for_agency(Current.agency).where.not(status: :draft).includes(:event, :account).order(created_at: :desc).load
      end
    end

    def show
      redirect_to agency_invoices_path, alert: "That invoice hasn't been sent yet." if @invoice.draft?
    end

    # Same shared/invoice_document partial + InvoicePdfService::Grover pipeline
    # SuperAdmin::InvoicesController#download already established — see that action's own
    # reasoning; kept identical here so the PDF this agency downloads is pixel-identical to the
    # one the Super Admin sees.
    def download
      html = render_to_string(:pdf, formats: [ :html ], layout: false)
      pdf = InvoicePdfService.render(html: html)
      send_data pdf, filename: "invoice-#{@invoice.id[0..7].upcase}.pdf", type: "application/pdf", disposition: "attachment"
    end

    def submit_payment
      utr_reference = params[:utr_reference].to_s.strip

      if utr_reference.blank?
        redirect_to agency_invoice_path(@invoice), alert: "Enter the UTR/reference number from your bank transfer."
        return
      end

      @invoice.submit_payment!(utr_reference: utr_reference, receipt: params[:receipt], by: current_user)
      redirect_to agency_invoices_path, notice: "Payment submitted — a Super Admin will verify it shortly."
    end

    private

    # Invoice.for_agency (not a bare Invoice.find) is the entire authorization boundary here —
    # an agency can only ever reach its own contract invoice or one of its own tenants' per-event
    # invoices, 404s otherwise. Event.unscoped_across_tenants — same reasoning #index's own
    # comment gives; #show reads @invoice.event, so it has to be eager-loaded here too.
    def set_invoice
      @invoice = Event.unscoped_across_tenants do
        Invoice.for_agency(Current.agency).includes(:event, :account).find(params[:id])
      end
    end
  end
end
