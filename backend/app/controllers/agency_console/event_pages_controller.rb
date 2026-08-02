module AgencyConsole
  # doc/event_page_templates_plan.md, Stage 3 — moved off Admin::EventPagesController (deleted
  # this same stage): a tenant's own event_admin has no path to this screen anymore, by URL or by
  # nav, only an agency admin does. Same find-or-initialize shape the deleted controller used
  # (#edit works identically whether an EventPage row exists yet or not), just resolved through
  # Current.agency.accounts (this console has no Current.account at all) and wrapped in
  # Event.unscoped_across_tenants — Event/EventPage are both TenantScoped, and every query here
  # (the account/event lookups, the has_one read, and EventPage's own uniqueness-validation query
  # on #update) would otherwise raise TenantScoped::MissingTenantContextError, same trap Stage 2's
  # own EventsController#index note already found.
  #
  # No PunditAuthorizable/`authorize` call — same reasoning BaseController's own comment already
  # gives for this whole namespace: there's no role variation inside an agency to gate against.
  # This also means the tenant-side EventPolicy#update?'s "locked once the event is completed"
  # rule is deliberately not re-implemented here — that rule protects the event's own historical
  # data, not this cosmetic template/page-content assignment, and BaseController's own convention
  # is to not import Pundit into this namespace at all.
  class EventPagesController < BaseController
    def edit
      Event.unscoped_across_tenants { load_event_page }
    end

    def update
      Event.unscoped_across_tenants do
        load_event_page

        if @event_page.update(event_page_params)
          redirect_to edit_agency_account_event_event_page_path(@account, @event), notice: "Event page saved."
        else
          render :edit, status: :unprocessable_content
        end
      end
    end

    private

    def load_event_page
      @account = Current.agency.accounts.find(params[:account_id])
      @event = @account.events.friendly.find(params[:event_id])
      # `account:` passed explicitly — the tenant-session flow this controller replaces got
      # `account_id` prefilled for free (ActiveRecord derives new-record defaults from an active
      # `where(account_id: Current.account.id)` default_scope), but that trick only fires on the
      # `Current.account` branch of TenantScoped's default_scope. This controller runs on the
      # `Current.platform_request` branch instead (`unscoped_across_tenants`, no `where` clause to
      # borrow a default from), so a bare `build_event_page` here would silently leave `account_id`
      # nil and fail EventPage's own `belongs_to :account` presence validation.
      @event_page = @event.event_page || @event.build_event_page(account: @account)
    end

    def event_page_params
      params.require(:event_page).permit(:html, :template_key)
    end
  end
end
