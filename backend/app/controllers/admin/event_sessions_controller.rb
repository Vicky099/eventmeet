module Admin
  # Phase 11 — Agenda, Speakers & Sessions (requirement.md §3.8, §5.6). Nested under Event — every
  # Session belongs to exactly one. No dedicated SessionPolicy — authorization delegates to the
  # parent Event's own EventPolicy, same shortcut Admin::BadgesController already takes.
  #
  # Named EventSessionsController, not SessionsController — Admin::SessionsController is already
  # Devise's login controller (config/routes.rb has the full explanation). The route/URL still
  # reads "sessions" (config/routes.rb: `resources :sessions, controller: "admin/event_sessions"`)
  # — only this class's own name avoids the collision.
  #
  # #index is the wizard's "Sessions" step content itself (rendered directly in
  # app/views/admin/events/edit.html.erb, not linked out to) — a focused list of this event's
  # rooms/tracks/capacity. The combined day/track timetable *with* each session's talks lives on
  # the separate "Event Schedule" step (Admin::SchedulesController#index) instead.
  class EventSessionsController < BaseController
    before_action :set_event
    before_action :set_session, only: [ :edit, :update, :destroy ]

    def index
      authorize @event, :update?
      @sessions = @event.sessions.order(:starts_at)
    end

    def new
      @session = @event.sessions.build
      authorize @event, :update?
    end

    def create
      @session = @event.sessions.build(session_params)
      authorize @event, :update?

      if @session.save
        redirect_to edit_admin_event_path(@event, step: "sessions"), notice: "#{@session.name} added."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      authorize @event, :update?
    end

    def update
      authorize @event, :update?

      if @session.update(session_params)
        redirect_to edit_admin_event_path(@event, step: "sessions"), notice: "#{@session.name} saved."
      else
        render :edit, status: :unprocessable_content
      end
    end

    # dependent: :restrict_with_error (Session#scan_events/#attendances) makes #destroy return
    # false — rather than raise — once the session has real check-in history.
    def destroy
      authorize @event, :update?
      if @session.destroy
        redirect_to edit_admin_event_path(@event, step: "sessions"), notice: "#{@session.name} removed."
      else
        redirect_to edit_admin_event_path(@event, step: "sessions"), alert: @session.errors.full_messages.to_sentence
      end
    end

    private

    def set_event
      @event = Event.friendly.find(params[:event_id])
    end

    def set_session
      @session = @event.sessions.find(params[:id])
    end

    def session_params
      params.require(:session).permit(:name, :room, :track, :starts_at, :ends_at, :seat_limit)
    end
  end
end
