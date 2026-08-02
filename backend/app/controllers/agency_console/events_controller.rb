module AgencyConsole
  # doc/event_page_templates_plan.md, Stage 2 — the Agency Console had no way to reach a specific
  # tenant's specific event at all before this (only the tenant list + #switch SSO handoff into
  # that tenant's own Admin Console subdomain). This is deliberately narrow: :index only, existing
  # solely so an agency admin can get from "a tenant" to "that tenant's Event Page screen"
  # (AgencyConsole::EventPagesController) — every other event-management action still happens on
  # the tenant's own Admin Console, unchanged.
  class EventsController < BaseController
    def index
      @account = Current.agency.accounts.find(params[:account_id])

      # Event.unscoped_across_tenants — same escape hatch, and same reasoning, as
      # AgencyConsole::DashboardController#index's own comment: TenantScoped's default_scope
      # doesn't recognize an agency-subdomain request (Current.account is nil here), and the
      # explicit `@account.events` scoping keeps this narrow to only this one, already-authorized
      # tenant. `.includes(:event_page)` + `.to_a` both execute *inside* the block — EventPage is
      # its own TenantScoped model, but `unscoped_across_tenants` sets `Current.platform_request`
      # for the whole block (not just Event's own scope), so the preload query is covered by the
      # same escape hatch without a second explicit `EventPage.unscoped_across_tenants` call. The
      # dashboard controller's own comment warns that merely returning the built relation/
      # CollectionProxy re-evaluates default_scope (and re-raises) the next time it's touched, even
      # for an already-preloaded target — so the view must read a plain Array here and the already-
      # preloaded `event.event_page` off each one, never re-call `@account.events` itself.
      @events = Event.unscoped_across_tenants { @account.events.order(starts_at: :desc).includes(:event_page).to_a }
    end
  end
end
