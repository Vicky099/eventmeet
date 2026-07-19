module Admin
  # Phase 4 — Event Lifecycle (requirement.md §3.2, §5.2, revisited for the stepper wizard,
  # further revisited to split Agenda into three distinct steps). The wizard (Basic Info/
  # Sessions/Speaker/Event Schedule/Ticket Categories/Badge/Review) all hosts off the single
  # `edit` action, `params[:step]` selecting which one renders — setup/authoring stays entirely
  # there. `#show` (Phase 7.5, requirement.md §5.14 v12) is a *different* thing: the event
  # workspace's own landing page — reachable from the Events index and every event-scoped nav
  # entry (AdminHelper#event_nav_items) — a read-only overview + a way back into `#edit` to keep
  # configuring, not a copy of any wizard step.
  #
  # Fixed-hierarchy pivot (requirement.md revisit, confirmed with the user): "remove all the
  # workflows where super admin allow to create the events" — no more Quotation picker, no more
  # Super Admin content-review step. Every tenant's Account belongs to an Agency (Agency::
  # AccountsController is the only place a new one is created); Event's own agency_contract_must_be_active
  # validation is the real, hard gate on #create/#duplicate — this controller no longer needs its
  # own pre-check branch the way the removed quotation flow did.
  class EventsController < BaseController
    # Order matters — it's also the Next/Previous adjacency (#next_step below). Sessions/Speaker/
    # Event Schedule (Admin::EventSessionsController/Admin::SpeakersController/
    # Admin::SchedulesController) and Badge (Admin::BadgesController) never submit a form on this
    # controller at all — each renders its own management UI directly in the step panel (or, for
    # Badge specifically, a GrapesJS canvas that genuinely doesn't fit in one — confirmed with
    # user it stays a dedicated page) via its own create/update/destroy actions, which redirect
    # back to this same step rather than a separate page — so #update never actually sees
    # `step: "sessions"`/`"speaker"`/`"event_schedule"`/`"badge"`. Tickets (Phase 6) is the one
    # step besides Basic Info with a real form here, same "Next saves it" shape.
    STEPS = %w[basic_info sessions speaker event_schedule tickets badge review].freeze

    before_action :set_event, only: [ :show, :edit, :update, :duplicate, :publish ]

    def index
      authorize Event
      @status_filter = params[:status].to_s.presence_in(Event.statuses.keys)
      @events = Current.account.events.order(created_at: :desc)
      @events = @events.where(status: @status_filter) if @status_filter
      @agency = Current.account.agency
    end

    def new
      @event = Current.account.events.build
      authorize @event
    end

    def create
      @event = Current.account.events.build(event_params)
      authorize @event

      if @event.save
        redirect_to edit_admin_event_path(@event, step: STEPS.first), notice: "#{@event.name} created."
      else
        render :new, status: :unprocessable_content
      end
    end

    # The event-workspace landing page (see the class comment above) — real data, not a stub:
    # status badge (same as the wizard's own top row), a few live counts, and the core setup
    # details, plus a way into #edit to keep configuring. EventPolicy#show? (any member) is the
    # same permissive check every other read view in this controller already uses.
    #
    # Registration status/ticket-category counts are computed fresh here (plain COUNT queries),
    # not read off EventLiveStats — confirmed live: that denormalized counter had drifted stale
    # against this exact event's real participant rows (registered_count read 6 against an actual
    # count of 1), almost certainly test/console data manipulated outside the normal
    # create/destroy callback path rather than a bug in the counter itself, but it's exactly the
    # kind of drift this read-only overview shouldn't risk surfacing — this page isn't the
    # high-frequency live check-in view (Admin::ScanEventsController#index) EventLiveStats exists
    # to serve cheaply, so a couple of real queries costs nothing meaningful here.
    def show
      authorize @event
      @participant_status_counts = Participant.statuses.keys.index_with { |status| @event.participants.public_send(status).count }
      @ticket_categories = @event.ticket_categories.order(:created_at)
      # Real Participant rows, not TicketCategory#sold_count — that column is derived solely from
      # ticket_reservations (the public self-registration hold/checkout flow) and never moves for a
      # participant added straight from the admin console's own "Add Participant" form (or CSV
      # import), so it under-counts real registrations on precisely the path this overview is meant
      # to reflect.
      @category_participant_counts = @event.participants.group(:ticket_category_id).count

      # Phase 14 — Reporting, Import/Export & Analytics (requirement.md §5.11): "registrations-
      # over-time ... check-in rate, session popularity, engagement funnel" — merged onto this
      # same landing page (renamed "Analytics" in the sidebar, AdminHelper#event_nav_items)
      # rather than a second, separate dashboard page; this workspace already *was* the event's
      # analytics/reporting home, just missing these specific views. Revenue and sponsor ROI are
      # deliberately not here — see the view's own comment for why (no payment gateway anywhere
      # in this app; Sponsor/Exhibitor is Phase 12, not built yet).
      @registrations_by_day = @event.daily_registration_counts
      @session_popularity = @event.sessions.includes(:session_live_stats)
        .map { |session| { name: session.name, checked_in_count: session.session_live_stats&.checked_in_count || 0 } }
        .sort_by { |row| -row[:checked_in_count] }
      @session_attended_count = @event.session_attended_participant_count
      registered_count = @event.participants.count
      @check_in_rate = registered_count.positive? ? ((@event.checked_in_participant_count.to_f / registered_count) * 100).round(1) : 0
    end

    def edit
      authorize @event
      @step = params[:step].presence_in(STEPS) || STEPS.first
    end

    # Backs the wizard's per-step Next button — a real save (not autosave) that advances to the
    # following step on success, or stays put with errors on failure. `params[:step]` (top-level,
    # not nested under event[]) identifies which step's form was submitted; only Basic Info has
    # one so far. A save here that changes any Event::CONTENT_ATTRIBUTES on an already-published
    # event silently reverts it to draft (Event#revert_to_draft_if_published_content_changed) —
    # no special-casing needed on this end.
    def update
      authorize @event
      current_step = params[:step].presence_in(STEPS) || STEPS.first

      if @event.update(event_params)
        redirect_to edit_admin_event_path(@event, step: next_step(current_step))
      else
        @step = current_step
        render :edit, status: :unprocessable_content
      end
    end

    # The Review step's Publish button — moves the event out of Draft via Event#publish!.
    # Fixed-hierarchy pivot (requirement.md revisit): no more Super Admin approval gate — every
    # event that exists at all already cleared Agency#contract_active? at creation time
    # (Event#agency_contract_must_be_active), so the only thing left to check is the content itself.
    def publish
      authorize @event, :update?

      if @event.basic_info_complete?
        @event.publish!
        redirect_to edit_admin_event_path(@event, step: "review"), notice: "#{@event.name} published."
      else
        redirect_to edit_admin_event_path(@event, step: "review"), alert: "Finish the Basic Info step before publishing."
      end
    end

    # requirement.md Phase 4: "clone name/mode/participant_fields now; richer clone of
    # tickets/badges revisited once those phases exist" — also copies dates/location, since a
    # required NOT NULL starts_at/ends_at needs *some* value and copying is the most sensible
    # default (the organizer adjusts after). status/published_at deliberately reset to their
    # defaults (draft/nil) — a duplicate is a brand-new, unpublished event, not a copy of the
    # original's publish state. Consumes another slot from the account's own Agency, same as any
    # other #create (Event#agency_contract_must_be_active is the real gate either way).
    def duplicate
      authorize @event, :create?

      clone = Current.account.events.build(
        name: "Copy of #{@event.name}",
        mode: @event.mode,
        starts_at: @event.starts_at,
        ends_at: @event.ends_at,
        address: @event.address,
        meeting_link: @event.meeting_link,
        map_url: @event.map_url,
        banner_orientation: @event.banner_orientation,
        participant_fields: @event.participant_fields
      )
      clone.save!
      redirect_to edit_admin_event_path(clone), notice: "Duplicated as \"#{clone.name}\"."
    end

    private

    # Relies on Event's own TenantScoped default_scope (requirement.md §4.2) for isolation —
    # already the single source of truth, no extra `Current.account.events` wrapper needed on the
    # read side (unlike #new/#create, which must set account explicitly since default_scope only
    # affects querying, not new-record attribute assignment).
    def set_event
      @event = Event.friendly.find(params[:id])
    end

    def next_step(step)
      STEPS[[ STEPS.index(step) + 1, STEPS.size - 1 ].min]
    end

    # ticket_categories_attributes — the Tickets step's own nested rows (Event
    # accepts_nested_attributes_for :ticket_categories); :id/:_destroy are what let an existing
    # row be updated or removed in the same batch instead of only ever appending new ones.
    # Deliberately no :participant_fields / :custom_fields_attributes here — the Basic Info step
    # no longer edits either. `participant_fields` stays a real Event column, still read by the
    # manual participant-entry form and CSV import (Phase 7.5 moves it onto RegistrationForm);
    # `custom_fields_attributes` refers to nothing on Event at all anymore — CustomField was
    # rescoped onto RegistrationForm (Phase 7.5), managed from its own Design Registration Form
    # screen instead.
    def event_params
      params.require(:event).permit(
        :name, :description, :mode, :starts_at, :ends_at, :address, :meeting_link, :map_url, :banner_orientation,
        :has_seat_limit, :seat_limit, :participant_approval_required, :is_paid, :send_registration_email,
        :scheduled_report_frequency,
        ticket_categories_attributes: [ :id, :name, :total_count, :document_required, :_destroy ]
      )
    end
  end
end
