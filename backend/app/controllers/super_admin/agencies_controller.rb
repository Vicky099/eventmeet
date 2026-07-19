module SuperAdmin
  # Agency layer (requirement.md revisit): mirrors SuperAdmin::AccountsController closely —
  # provisioning here is the only way an Agency comes into existence, same "no self-serve" shape
  # every other Platform Console resource takes. Every action is already gated to platform_staff by
  # BaseController — no Pundit check needed, same reasoning AccountsController's own comment gives.
  class AgenciesController < BaseController
    before_action :set_agency, only: [ :show, :edit, :update, :suspend, :reinstate, :grant_events ]

    def index
      @status_filter = params[:status].to_s.presence_in(Agency.statuses.keys)
      @query = params[:q].to_s.strip

      @agencies = Agency.order(created_at: :desc)
      @agencies = @agencies.where(status: @status_filter) if @status_filter
      @agencies = @agencies.where("name ILIKE :q", q: "%#{@query}%") if @query.present?
    end

    # requirement.md revisit: "design this in proper way. show all necessary details and agency
    # level performance analytics, his tenants and his events and how much participants was there
    # in the event ... so that super admin will get to know what is happening in the platform."
    # Read-only rollup throughout — no new billing/analytics schema, just the same association
    # traversal an ordinary `@agency.accounts.includes(events: :invoice)` view already gave for
    # free (requirement.md revisit: "keep invoicing per-event," this is only ever a view into
    # that, not a second copy of it). No .unscoped_across_tenants anywhere here, unlike the
    # equivalent Agency Console dashboard query — this runs under Current.platform_request (the
    # Platform Console's own apex-domain context), which TenantScoped's default_scope already
    # opens up to `all` on its own.
    def show
      # includes(:users) — Phase 23's own tenant_modal "Impersonate" roster (per-account users, via
      # account_memberships) would otherwise fire once per account/modal in the loop below.
      @accounts = @agency.accounts.includes(:users).order(created_at: :desc)
      account_ids = @accounts.map(&:id)

      @events = Event.where(account_id: account_ids).includes(:account, :invoice).order(starts_at: :desc)
      @events_by_account = @events.group_by(&:account_id)
      @participant_counts_by_event = Participant.where(account_id: account_ids).group(:event_id).count

      @agency_memberships = @agency.agency_memberships.includes(:user).order(created_at: :desc)

      # Total Paid/Outstanding — Invoice.for_agency(@agency) never spans more than this one
      # agency's own currency (that method's own comment has the full reasoning), so a single
      # money(amount, @agency.currency) is always correct here, no per-currency grouping needed
      # (unlike the Platform Console's own multi-agency dashboard).
      agency_invoices = Invoice.for_agency(@agency)
      @total_paid = agency_invoices.paid.sum(:amount)
      @outstanding = agency_invoices.where(status: [ :awaiting_payment, :under_review ]).sum(:amount)

      # requirement.md revisit: "if event has used the whatsApp messages for invitation then show
      # the messages sent via whatsApp count ... overall how much messages used by agency." The
      # only WhatsApp sends this app ever makes are Super-Admin-to-agency invoice notifications
      # (SuperAdmin::InvoicesController#notify_invoice_sent/#notify_payment_rejected —
      # requirement.md §497 scopes Gupshup to operational/transactional sends only, never
      # attendee-facing), and only ever for a per-event Invoice, never the agency's own annual
      # contract one (that controller's own comment on why). So "an event's own WhatsApp usage" is
      # exactly its own Invoice's `sent` whatsapp Notifications — `status: :sent`, not merely
      # created, since a `failed` row (no Gupshup credential, no contact_num on file) never actually
      # reached Gupshup and was never billed for.
      invoice_ids = @events.filter_map { |event| event.invoice&.id }
      whatsapp_counts_by_invoice = Notification.where(notifiable_type: "Invoice", notifiable_id: invoice_ids, channel: :whatsapp, status: :sent).group(:notifiable_id).count
      # Keyed by event.id (not the Event object itself, unlike Enumerable#index_with) — matches
      # @participant_counts_by_event's own shape above, since the view looks both up the same way,
      # `some_hash.fetch(event.id, 0)`.
      @whatsapp_counts_by_event = @events.each_with_object({}) { |event, hash| hash[event.id] = whatsapp_counts_by_invoice.fetch(event.invoice&.id, 0) }
      @whatsapp_message_count = @whatsapp_counts_by_event.values.sum
    end

    def new
      @agency = Agency.new
    end

    def create
      result = AgencyProvisioning.call(agency_attributes: agency_params.except(:admin_email), admin_email: agency_params[:admin_email])

      if result.success?
        AuditLog.record!(actor: current_platform_staff, action: "agency.create", target: result.agency,
          metadata: { name: result.agency.name, billing_cycle: result.agency.billing_cycle, admin_email: result.admin_user.email })
        redirect_to platform_agency_path(result.agency),
          notice: "#{result.agency.name} provisioned — welcome email sent to #{result.admin_user.email}."
      else
        @agency = result.agency
        @admin_email = result.admin_user.email
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @agency.update(agency_params.except(:admin_email))
        AuditLog.record!(actor: current_platform_staff, action: "agency.update", target: @agency,
          metadata: { changes: @agency.saved_changes.except("updated_at").transform_values(&:last) })
        redirect_to platform_agency_path(@agency), notice: "#{@agency.name} updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def suspend
      @agency.suspended!
      AuditLog.record!(actor: current_platform_staff, action: "agency.suspend", target: @agency)
      redirect_to platform_agency_path(@agency), notice: "#{@agency.name} suspended."
    end

    def reinstate
      @agency.active!
      AuditLog.record!(actor: current_platform_staff, action: "agency.reinstate", target: @agency)
      redirect_to platform_agency_path(@agency), notice: "#{@agency.name} reinstated."
    end

    def grant_events
      count = params[:count].to_i

      if count <= 0
        redirect_to platform_agency_path(@agency), alert: "Enter a positive number of events to grant."
        return
      end

      @agency.grant_more!(count)
      AuditLog.record!(actor: current_platform_staff, action: "agency.grant_events", target: @agency,
        metadata: { count: count, events_remaining: @agency.events_remaining })
      redirect_to platform_agency_path(@agency), notice: "Granted #{count} more event#{"s" if count != 1} to #{@agency.name} — #{@agency.events_remaining} now remaining."
    end

    private

    def set_agency
      @agency = Agency.find(params[:id])
    end

    def agency_params
      params.require(:agency).permit(
        :name, :admin_email, :subdomain_slug, :contact_email, :contact_num,
        :billing_cycle, :price_per_event, :annual_price, :currency, :events_granted
      )
    end
  end
end
