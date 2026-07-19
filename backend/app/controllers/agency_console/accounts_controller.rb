module AgencyConsole
  # Fixed-hierarchy pivot (requirement.md revisit, confirmed with the user: "agency will create the
  # tenants") — the only place a new tenant Account comes into existence now.
  # AccountProvisioning (app/services/account_provisioning.rb, unchanged, already accepts an
  # agency: kwarg) does the actual work — Account + event_admin User + AccountMembership +
  # Doorkeeper::Application + an event_admin AccountMembership backfilled for every existing
  # agency_admin, in one transaction, welcome email on success. This action only translates its
  # Result into a redirect or a re-rendered form.
  class AccountsController < BaseController
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
  end
end
