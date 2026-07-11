module Admin
  # Phase 4 — Event Lifecycle (requirement.md §3.2, §5.2). The tabbed builder (Basic Info/Agenda/
  # Ticket Categories/Badge/Review) all hosts off the single `edit` action — no separate read-only
  # `show`, since every tab is either directly editable (Basic Info, autosaved) or a read-only
  # summary (Review) that's part of the same workspace, not a distinct page.
  class EventsController < BaseController
    before_action :set_event, only: [ :edit, :update, :duplicate ]

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
        redirect_to edit_admin_event_path(@event), notice: "#{@event.name} created."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      authorize @event
    end

    # Backs the Basic Info tab's autosave (app/javascript/controllers/autosave_controller.js) —
    # the form lives inside a Turbo Frame, so re-rendering :edit here only actually replaces that
    # frame's content client-side; the tab strip itself lives outside the frame and is untouched.
    def update
      authorize @event

      if @event.update(event_params)
        render :edit
      else
        render :edit, status: :unprocessable_content
      end
    end

    # requirement.md Phase 4: "clone name/mode/participant_fields now; richer clone of
    # tickets/badges revisited once those phases exist" — also copies dates/location, since a
    # required NOT NULL starts_at/ends_at needs *some* value and copying is the most sensible
    # default (the organizer adjusts after). approval_status/status deliberately reset to their
    # defaults (pending/draft) — a duplicate is a brand-new event, not a copy of the original's
    # review state.
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

    # participant_fields arrives as individual "event[participant_fields][field]" => "true"/nil
    # checkbox params (app/views/admin/events/_basic_info_tab.html.erb) — normalized against the
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
