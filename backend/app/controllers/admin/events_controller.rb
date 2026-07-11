module Admin
  # Phase 4 — Event Lifecycle (requirement.md §3.2, §5.2, revisited for the stepper wizard). The
  # wizard (Basic Info/Agenda/Ticket Categories/Badge/Review) all hosts off the single `edit`
  # action, `params[:step]` selecting which one renders — no separate read-only `show`, since
  # every step is either directly editable (Basic Info, so far) or a read-only summary (Review)
  # that's part of the same workspace, not a distinct page.
  class EventsController < BaseController
    # Order matters — it's also the Next/Previous adjacency (#next_step below). Agenda/Tickets/
    # Badge don't have real forms yet (Phase 11/6/8 stubs), so #update never actually sees
    # `step: "agenda"` etc. today; STEPS already includes them so the nav and Next/Previous chain
    # are complete now instead of needing a second pass once those phases land.
    STEPS = %w[basic_info agenda tickets badge review].freeze

    before_action :set_event, only: [ :edit, :update, :duplicate, :publish, :submit_for_review ]

    def index
      authorize Event
      @status_filter = params[:status].to_s.presence_in(Event.statuses.keys)
      @events = Current.account.events.order(created_at: :desc)
      @events = @events.where(status: @status_filter) if @status_filter
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

    # The Review step's Publish button (requirement.md §5.2 revisited) — moves the event out of
    # Draft via Event#publish!. Distinct from approval_status/Super Admin review (still Phase 5):
    # this only controls the event's own draft/scheduled-live lifecycle, not public visibility.
    def publish
      authorize @event, :update?

      if @event.basic_info_complete?
        @event.publish!
        redirect_to edit_admin_event_path(@event, step: "review"), notice: "#{@event.name} published."
      else
        redirect_to edit_admin_event_path(@event, step: "review"), alert: "Finish the Basic Info step before publishing."
      end
    end

    # The Review step's "Submit for review" button (requirement.md §5.2, §4.7 item 2) — the only
    # thing that ever puts an event in SuperAdmin::EventReviewsController's queue for the first
    # time (Event#submit_for_review!, unsubmitted -> pending), also used to resubmit after a
    # rejection. Same basic_info_complete? gate as #publish, for the same reason: nothing
    # incomplete belongs in front of a Super Admin reviewer.
    def submit_for_review
      authorize @event, :update?

      if @event.basic_info_complete?
        @event.submit_for_review!
        redirect_to edit_admin_event_path(@event, step: "review"), notice: "#{@event.name} submitted for review."
      else
        redirect_to edit_admin_event_path(@event, step: "review"), alert: "Finish the Basic Info step before submitting for review."
      end
    end

    # requirement.md Phase 4: "clone name/mode/participant_fields now; richer clone of
    # tickets/badges revisited once those phases exist" — also copies dates/location, since a
    # required NOT NULL starts_at/ends_at needs *some* value and copying is the most sensible
    # default (the organizer adjusts after). approval_status/status/published_at deliberately
    # reset to their defaults (unsubmitted/draft/nil) — a duplicate is a brand-new, unpublished,
    # never-submitted event, not a copy of the original's review or publish state.
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

    # participant_fields arrives as individual "event[participant_fields][field]" => "true"/nil
    # checkbox params (app/views/admin/events/_basic_info_step.html.erb) — normalized against the
    # fixed catalog here rather than mass-assigned, so an unchecked box (which submits nothing at
    # all) reliably clears to false instead of leaving the previous value untouched.
    def event_params
      permitted = params.require(:event).permit(:name, :mode, :starts_at, :ends_at, :address, :meeting_link, :map_url, :banner_orientation)
      permitted[:participant_fields] = Event::PARTICIPANT_FIELD_CATALOG.index_with do |field|
        params.dig(:event, :participant_fields, field) == "true"
      end
      permitted
    end
  end
end
