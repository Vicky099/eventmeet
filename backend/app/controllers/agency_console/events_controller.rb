module AgencyConsole
  # doc/event_page_templates_plan.md, Stage 2 — the Agency Console had no way to reach a specific
  # tenant's specific event at all before this (only the tenant list + #switch SSO handoff into
  # that tenant's own Admin Console subdomain). This is deliberately narrow: :index/:show, plus
  # exactly one real write surface (#approve/#reject below) — every other event-management action
  # still happens on the tenant's own Admin Console, unchanged. requirement.md revisit: "client
  # also create event but event created by client requires a agency approval" — #approve/#reject
  # are that review queue's own action pair, the one thing only the agency (not the client itself)
  # can do to an event.
  class EventsController < BaseController
    # requirement.md revisit: "all the dates which are displayed in the UI should obey the tenant
    # timezone" (Account#time_zone's own comment) — TenantResolvable#with_tenant_time_zone already
    # covers the tenant Admin Console, but only ever fires off `Current.account`, which is nil for
    # every Agency Console request (`Current.agency` is set instead — TenantResolvable's own class
    # comment). Confirmed live: an event created with a 10:00 AM–6:00 PM local time showed as
    # 4:30–12:30 on this console's own event pages before this — Time.zone was silently defaulting
    # to UTC for the whole request. This console's own equivalent, scoped to whichever tenant
    # Account this request's `:account_id` names (an Agency Console request can span several
    # tenants across different actions, unlike the Admin Console's single fixed `Current.account`,
    # so there's no one request-wide zone to set the way TenantResolvable does) — an around_action,
    # not a before_action, for the same reason TenantResolvable's own version is one: Time.zone
    # must still be in effect while the view itself renders (every `to_fs`/`strftime` call on an
    # AR timestamp happens there, not in the action method), not just for the duration of this
    # method body. Sets `@account` too, so #index/#show below don't each look it up again.
    around_action :apply_account_time_zone

    def index
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

    # Read-only "view this tenant's event" drill-down off the index row above — a lighter
    # counterpart to Admin::EventsController#show's own event-workspace landing page (that one's
    # KPI tiles/charts/edit entry point are all tenant-side concerns; this is purely "what does
    # this event look like — details, registration counts, and its designed badges — for the
    # agency's own oversight). Everything derived from Participant/TicketCategory/Badge below is
    # read to a plain value (Hash/Integer/Array, never a relation or CollectionProxy) *inside* the
    # `unscoped_across_tenants` block, for the same reason #index's own comment gives:
    # default_scope re-evaluates (and raises, no Current.account here) the moment any of those
    # associations is touched again outside it.
    def show
      Event.unscoped_across_tenants do
        @event = @account.events.includes(:event_page).friendly.find(params[:id])
        @ticket_categories = @event.ticket_categories.order(:created_at).to_a
        @participant_status_counts = Participant.statuses.keys.index_with { |status| @event.participants.public_send(status).count }
        @participant_count = @event.participants.count
        @category_participant_counts = @event.participants.group(:ticket_category_id).count
        @checked_in_count = @event.checked_in_participant_count
        # Badges card — read-only, same "own copy" of admin/badges/_badges_table.html.erb's
        # eye-icon preview modal AgencyConsole::BadgesController#preview itself takes on
        # Admin::BadgesController#preview. `.includes(:ticket_category)` + `.to_a` for the same
        # "plain Array, no CollectionProxy surviving past this block" reason as `@ticket_categories`
        # above.
        @badges = @event.badges.includes(:ticket_category).order(:ticket_category_id).to_a

        # Sessions card + Event Schedule card — read-only counterparts to
        # admin/events/_sessions_step.html.erb and admin/events/_event_schedule_step.html.erb.
        # `@schedule_days` is the same "sessions grouped by day" Hash that step's own view builds
        # (`sessions.group_by { ... }`) — safe as a plain Enumerable#group_by over an already-
        # loaded Array. `@talks_by_session_id` exists only because `session.schedules` itself is
        # NOT safe to call from the view even pre-`includes`'d — a `has_many` CollectionProxy
        # re-derives its scope (and so re-raises TenantScoped::MissingTenantContextError) the
        # moment any Enumerable-ish method touches it outside this block, same trap #index's own
        # comment already documents for a bare association read; grouping every Schedule row by
        # session_id into a plain Hash up front is what lets the view read a session's talks
        # without ever calling `.schedules` on it again.
        @sessions = @event.sessions.order(:starts_at).to_a
        all_schedules = @event.schedules.includes(:speaker).order(:starts_at).to_a
        @talks_by_session_id = all_schedules.select(&:session_id).group_by(&:session_id)
        @unscheduled_talks = all_schedules.reject(&:session_id)
        @schedule_days = @sessions.group_by { |session| session.starts_at.to_date }
      end
    end

    # The review queue's own "yes" — requirement.md revisit's own approval requirement.
    # `approval_pending?` guard, not just "any event" — approving/rejecting only makes sense on an
    # event actually awaiting review; an already-decided one has no business being re-decided
    # through this same pair of actions.
    def approve
      Event.unscoped_across_tenants { @event = @account.events.friendly.find(params[:id]) }

      unless @event.approval_pending?
        redirect_to agency_account_event_path(@account, @event), alert: "#{@event.name} isn't awaiting approval."
        return
      end

      Event.unscoped_across_tenants { @event.approve!(by: current_user) }
      notify_event_decision(:approved)
      redirect_to agency_account_event_path(@account, @event), notice: "#{@event.name} approved."
    end

    # The review queue's own "no" — same shape SuperAdmin::InvoicesController#reject already
    # takes one tier up (a required reason, no silent/reasonless rejection), just one tenant lower
    # and against Event instead of Invoice. Event#reject! (not #destroy) — the client's own
    # Admin::EventsController#resubmit_for_approval is the way back from here, so the event and
    # everything already configured on it survives a rejection.
    def reject
      Event.unscoped_across_tenants { @event = @account.events.friendly.find(params[:id]) }

      unless @event.approval_pending?
        redirect_to agency_account_event_path(@account, @event), alert: "#{@event.name} isn't awaiting approval."
        return
      end

      reason = params[:rejection_reason].to_s.strip
      if reason.blank?
        redirect_to agency_account_event_path(@account, @event), alert: "A reason for rejecting this event is required."
        return
      end

      Event.unscoped_across_tenants { @event.reject!(reason: reason, by: current_user) }
      notify_event_decision(:rejected)
      redirect_to agency_account_event_path(@account, @event), notice: "#{@event.name} sent back for changes."
    end

    private

    # Current.set(account:) — same reasoning AccountMembershipProvisioning's own identical wrapper
    # gives: Notification is TenantScoped, and this whole controller runs under Current.agency,
    # not Current.account. `@account.admin_users` (the client's own event_admin roster), never the
    # agency's own users — they're the ones who just acted, not who needs telling.
    def notify_event_decision(outcome)
      subject = outcome == :approved ? "#{@event.name} approved" : "#{@event.name} needs changes"

      Current.set(account: @account) do
        @account.admin_users.each do |user|
          Notifier.email(
            mailer_class: EventMailer, mailer_method: outcome, mailer_args: [ @event, user.email ],
            notifiable: @event, account: @account, to: user.email, subject: subject
          )
        end
      end
    end

    # Time.use_zone (not a bare `Time.zone = ...`) — same "must never leak into the next request
    # served on this connection" reasoning TenantResolvable#with_tenant_time_zone's own comment
    # already gives, just scoped to this one already-authorized tenant Account instead of
    # `Current.account`.
    def apply_account_time_zone(&block)
      @account = Current.agency.accounts.find(params[:account_id])
      Time.use_zone(@account.time_zone, &block)
    end
  end
end
