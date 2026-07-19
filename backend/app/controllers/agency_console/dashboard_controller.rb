module AgencyConsole
  # The Agency Console's authenticated landing page (fixed-hierarchy pivot, requirement.md
  # revisit) — its own tenants + contract/pool status, the tenant-list half of
  # SuperAdmin::AgenciesController#show reused here, scoped to Current.agency instead of a
  # params[:id] lookup (a Super Admin can look at any agency; an agency admin only ever sees
  # their own, enforced one layer down by TenantResolvable/AgencyConsole::BaseController already).
  #
  # requirement.md revisit: "design the agency analytics dashboard" — mirrors
  # SuperAdmin::DashboardController's own shape one tier down: an at-a-glance stat row, a real
  # payment action queue (not just a count), and a live pulse — scoped to just this one agency's
  # own tenants throughout, never the whole platform.
  class DashboardController < BaseController
    def index
      @agency = Current.agency
      @accounts = @agency.accounts.order(created_at: :desc)

      # requirement.md revisit: "show only latest 10 tenants and top right corner of tenant will
      # have view all link" — @accounts itself stays the full set (the stat row's own Tenants
      # count, and the events/participants rollups below, both need every tenant, not just the
      # newest 10); only the Tenants card's own table reads @recent_accounts, capped separately.
      @recent_accounts = @accounts.first(10)

      # TenantScoped's default_scope only recognizes two contexts (Current.account,
      # Current.platform_request) — an agency subdomain request is neither, so listing `events`/
      # `participants` across this agency's own multiple tenant Accounts needs the same
      # .unscoped_across_tenants escape hatch a background job would use. Still narrow, not a real
      # cross-agency leak: the explicit account_id filter below matches only the Accounts already
      # loaded onto @accounts.
      #
      # Built as plain Hashes (not left as scoped associations) deliberately — the view must read
      # these via @events_by_account/@participant_counts_by_account, never `account.events`, since
      # calling the association method itself re-evaluates the default_scope at
      # CollectionProxy-build time and would raise again, even for an already-preloaded target.
      account_ids = @accounts.map(&:id)
      @events_by_account, @participant_counts_by_account, @live_event_count = Event.unscoped_across_tenants do
        events_by_account = Event.where(account_id: account_ids).includes(:invoice).group_by(&:account_id)
        participant_counts = Participant.where(account_id: account_ids).group(:account_id).count
        live_count = Event.live.where(account_id: account_ids).count
        [ events_by_account, participant_counts, live_count ]
      end
      @event_count = @events_by_account.values.sum(&:size)
      @participant_count = @participant_counts_by_account.values.sum

      @live_pulse = LiveDashboard.agency_pulse(@agency)

      # requirement.md revisit: "earning and all" one tier down — from the agency's own point of
      # view this is money *paid out* to the platform, not collected, so it's framed as Paid/
      # Outstanding rather than reusing SuperAdmin::DashboardController's "Revenue" language.
      # Invoice.for_agency(@agency) never spans more than this one agency's own currency (that
      # method's own comment has the full reasoning), so — unlike the Platform Console's
      # multi-agency dashboard — a single money(amount, @agency.currency) is always correct here,
      # no per-currency grouping needed.
      agency_invoices = Invoice.for_agency(@agency)
      @total_paid = agency_invoices.paid.sum(:amount)
      @outstanding = agency_invoices.where(status: [ :awaiting_payment, :under_review ]).sum(:amount)

      # "Due invoices need actions" one tier down — this agency's own payment queue. Only
      # `awaiting_payment`: a `draft` hasn't been sent yet (nothing to act on), `under_review` was
      # already submitted (nothing left for the agency to do, waiting on the Super Admin now) —
      # same "only show what THIS audience can actually act on" split
      # SuperAdmin::DashboardController#index's own comment already established, one tier down.
      @invoices_needing_payment = Event.unscoped_across_tenants do
        agency_invoices.awaiting_payment.includes(:event, :account).order(created_at: :desc).limit(10).to_a
      end
    end
  end
end
