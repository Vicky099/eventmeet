module AgencyConsole
  # Fixed-hierarchy pivot (requirement.md revisit, confirmed with the user: "agency will create the
  # tenants") — the only place a new tenant Account comes into existence now.
  # AccountProvisioning (app/services/account_provisioning.rb, unchanged, already accepts an
  # agency: kwarg) does the actual work — Account + event_admin User + AccountMembership +
  # Doorkeeper::Application + an event_admin AccountMembership backfilled for every existing
  # agency_admin, in one transaction, welcome email on success. This action only translates its
  # Result into a redirect or a re-rendered form.
  class AccountsController < BaseController
    # #show renders this Account's own dates (event/registration timestamps) in its own time_zone
    # — same "must stay in effect through view rendering, not just the action body" reasoning
    # AgencyConsole::EventsController#apply_account_time_zone's own comment gives, just keyed off
    # `params[:id]` (a flat member route) instead of that controller's nested `params[:account_id]`.
    around_action :apply_account_time_zone, only: [ :show ]

    # requirement.md revisit: "show only latest 10 tenants and top right corner of tenant will
    # have view all link and also have a sidebar which will have all the tenants with
    # pagination." — the dashboard's own Tenants card (AgencyConsole::DashboardController#index)
    # now only previews the newest 10; this is the "View all" destination, the full paginated
    # list, its own sidebar entry (AgencyHelper#agency_nav_items).
    def index
      @agency = Current.agency
      # Pagy 8.x classic API takes `items:`, not `limit:` (Gemfile's own comment on why this app
      # is pinned to 8.x has the full API-shape reasoning) — admin/participants_controller.rb's
      # own `pagy(scope, limit: 25)` predates this and silently falls back to Pagy's own default
      # of 20 as a result; not this task's fix to make, but not one to repeat here either.
      @pagy, @accounts = pagy(@agency.accounts.order(created_at: :desc), items: 15)

      # Event.unscoped_across_tenants — same escape hatch, and same reasoning, as
      # AgencyConsole::DashboardController#index's own comment: TenantScoped's default_scope
      # doesn't recognize an agency-subdomain request, and the explicit account_id filter below
      # keeps this narrow to only the Accounts already loaded onto this one page.
      account_ids = @accounts.map(&:id)
      @event_counts_by_account, @participant_counts_by_account = Event.unscoped_across_tenants do
        [
          Event.where(account_id: account_ids).group(:account_id).count,
          Participant.where(account_id: account_ids).group(:account_id).count
        ]
      end
    end

    def new
      @account = Account.new
      redirect_to_contract_blocked and return unless Current.agency.contract_active?
    end

    def create
      unless Current.agency.contract_active?
        redirect_to_contract_blocked
        return
      end

      attrs = account_params
      result = AccountProvisioning.call(
        account_attributes: attrs.except(:admin_email), admin_email: attrs[:admin_email],
        logo: params.dig(:account, :logo), agency: Current.agency
      )

      if result.success?
        redirect_to agency_root_path,
          notice: "#{result.account.name} provisioned — welcome email sent to #{result.admin_user.email}."
      else
        @account = result.account
        @admin_email = result.admin_user.email # not a real Account attribute — repopulated separately for the re-rendered form
        render :new, status: :unprocessable_content
      end
    end

    # requirement.md revisit: "a client show page and some performance analytics of client and
    # some catchy analytis" — cross-event KPIs/charts for this one Account, read-only, same
    # visual language admin/events/show.html.erb's own event-level workspace already established
    # (shared/_stat_widget, .status-bar/.status-bar-segment, .bar-track/.bar-fill, .arrival-bars) —
    # reused verbatim rather than inventing new chart markup, just aggregated across every one of
    # this Account's events instead of one event's own sessions/ticket-categories.
    #
    # Event.unscoped_across_tenants — same escape hatch/reasoning as #index's own comment: this
    # request runs under Current.agency, not Current.account, so Event/Participant's own
    # TenantScoped default_scope has nothing to recognize otherwise. Every derived value below is
    # read to a plain value (Array/Hash/Integer) *inside* the block, for the same "a CollectionProxy
    # re-evaluates default_scope the moment it's touched again outside it" reason #index's own
    # comment already gives — @events in particular is a plain Array, never re-queried by the view.
    def show
      Event.unscoped_across_tenants do
        @events = @account.events.order(starts_at: :desc).to_a
        @event_status_counts = Event.statuses.keys.index_with { |status| @events.count { |event| event.status == status } }
        @checked_in_count = @events.sum(&:checked_in_participant_count)
        @registrations_by_day = Participant.where(account: @account).pluck(:created_at).map(&:to_date).tally
        @participant_status_counts = Participant.statuses.keys.index_with { |status| Participant.where(account: @account).public_send(status).count }
        @participant_counts_by_event = Participant.where(account: @account).group(:event_id).count
      end

      @participant_count = @participant_status_counts.values.sum
      @live_event_count = @event_status_counts["live"]

      # This Account's own admin roster — AccountMembership deliberately has no TenantScoped
      # default_scope at all (that model's own comment), so no escape hatch needed here either.
      @account_memberships = @account.account_memberships.includes(:user).order(:created_at)
    end

    # requirement.md revisit: "we should have tenant edit option" — contact/timezone upkeep after
    # provisioning, most importantly Account#time_zone (TenantResolvable#with_tenant_time_zone's
    # own comment has the full "why every date/time this app renders depends on getting this
    # right"). `Current.agency.accounts.find` — same authorization boundary #switch/#suspend/
    # #reinstate above already use: an agency can only ever edit one of its own tenants.
    def edit
      @account = Current.agency.accounts.find(params[:id])
    end

    def update
      @account = Current.agency.accounts.find(params[:id])

      # `params[:staff_permissions_form]` — a bare hidden marker outside the `account[...]` nest
      # (agency_console/accounts/show.html.erb's own Staff Permissions card), not
      # `params[:account][:staff_permissions].present?` — an agency turning every single toggle
      # off submits no `account[staff_permissions][...]` checkbox params at all (unchecked HTML
      # checkboxes never submit), which would otherwise be indistinguishable from the *other*
      # form on this same action (#edit's plain name/contact/timezone fields, which never send
      # `staff_permissions` either) — and silently no-op exactly the update the agency just made.
      attrs = account_update_params
      attrs = attrs.merge(staff_permissions: staff_permissions_params) if params[:staff_permissions_form].present?

      # redirect_back (not a fixed path) — same two-possible-trigger-page shape #suspend/
      # #reinstate's own comment already establishes: this action now backs both the plain Edit
      # form (agency_accounts_path is the sensible fallback there) and the Show page's own Staff
      # Permissions card (which wants to land back on itself, not the list).
      if @account.update(attrs)
        redirect_back fallback_location: agency_accounts_path, notice: "#{@account.name} updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    # Agency → Tenant account switch (requirement.md revisit: "agency will controlled all the
    # event using single sign-in as switch account") — mints a one-time AccountSwitch and hands
    # the browser straight to that tenant's own admin/switch, its own subdomain, to redeem it.
    # `Current.agency.accounts.find` (not a bare `Account.find`) is the entire authorization
    # boundary here: an agency can only ever switch into one of its own tenants, 404s otherwise.
    def switch
      account = Current.agency.accounts.find(params[:id])
      account_switch = AccountSwitch.generate_for(user: current_user, account: account)

      # allow_other_host: true — a deliberately cross-subdomain redirect (Rails' open-redirect
      # guard blocks this by default), safe here because the target host is built from
      # account.subdomain_slug (this agency's own tenant, already scoped above), never from
      # unvalidated request input.
      redirect_to redeem_account_switch_url(
        host: "#{account.subdomain_slug}.#{Rails.application.config.x.platform_domain}",
        token: account_switch.token
      ), allow_other_host: true
    end

    # requirement.md revisit: "have a action to suspend and reinstate" — first on the tenant list
    # (agency/accounts#index), then "same action here as well for tenants" on the dashboard's own
    # Tenants preview card (agency_root_path) too — the agency's own oversight of its own tenants,
    # same `Current.agency.accounts.find` authorization boundary as #switch above (an agency can
    # only ever suspend/reinstate one of its own tenants, 404s otherwise). Mirrors
    # SuperAdmin::AccountsController#suspend/#reinstate one tier down. redirect_back (not a fixed
    # agency_accounts_path) — this action now has two possible trigger pages, so it returns to
    # whichever one the button was actually clicked from.
    def suspend
      account = Current.agency.accounts.find(params[:id])
      account.suspended!
      redirect_back fallback_location: agency_accounts_path, notice: "#{account.name} suspended."
    end

    def reinstate
      account = Current.agency.accounts.find(params[:id])
      account.active!
      redirect_back fallback_location: agency_accounts_path, notice: "#{account.name} reinstated."
    end

    private

    # Time.use_zone (not a bare `Time.zone = ...`) — same "must never leak into the next request
    # served on this connection" reasoning AgencyConsole::EventsController#apply_account_time_zone's
    # own comment already gives. Sets `@account` too, so #show itself doesn't look it up again.
    def apply_account_time_zone(&block)
      @account = Current.agency.accounts.find(params[:id])
      Time.use_zone(@account.time_zone, &block)
    end

    # Fixed-hierarchy pivot (requirement.md revisit): "for per year, agency has to pay all the
    # amount in advance to begin with event management" — an annual agency whose one upfront
    # contract Invoice isn't paid yet can't create a tenant at all. A per_event agency has no
    # equivalent gate here — its own pool only ever blocks *event* creation, not tenant creation
    # (Event's own agency_contract_must_be_active validation is the per-event counterpart).
    def redirect_to_contract_blocked
      redirect_to agency_root_path, alert: "Your annual contract hasn't been paid yet — a Super Admin needs to verify payment before you can create tenants."
    end

    def account_params
      params.require(:account).permit(:name, :subdomain_slug, :admin_email, :contact_email, :contact_num, :sender_email, :time_zone)
    end

    # #update's own permitted set — deliberately narrower than #account_params above:
    # :subdomain_slug (this tenant's own hosting identity/login URL) and :admin_email (a one-time
    # provisioning-only concept, not a real Account attribute at all) both stay #new/#create-only.
    def account_update_params
      params.require(:account).permit(:name, :contact_email, :contact_num, :sender_email, :time_zone)
    end

    # requirement.md revisit: "agency will define the client staff permission by toggle on or
    # off" — every catalog key gets an explicit true/false (not just the ones present in params),
    # since an unchecked HTML checkbox never submits at all: a key's *absence* from
    # `params[:account][:staff_permissions]` means "this toggle is off," not "leave it alone" (the
    # `params[:staff_permissions_form]` marker in #update above is what already establishes this
    # form was submitted at all, so every catalog key is meant to be set here).
    def staff_permissions_params
      Account::STAFF_PERMISSION_CATALOG.keys.index_with { |key| params.dig(:account, :staff_permissions, key).present? }
    end
  end
end
