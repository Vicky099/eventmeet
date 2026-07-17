module Admin
  # Phase 11 — Agenda, Speakers & Sessions (requirement.md §3.8). Nested under Event — every talk
  # belongs to exactly one. No dedicated SchedulePolicy — same EventPolicy delegation shortcut
  # every other event-nested resource in this app takes.
  #
  # #index is the wizard's "Event Schedule" step content itself — the full day/track timetable
  # (each session's talks, plus any room-less standalone ones), rendered directly in
  # app/views/admin/events/edit.html.erb rather than linked out to. This is the one place all
  # three of Sessions/Speaker/Schedule come together into one view, since a timetable inherently
  # needs all three.
  class SchedulesController < BaseController
    before_action :set_event
    before_action :set_schedule, only: [ :edit, :update, :destroy ]

    def index
      authorize @event, :update?
      sessions = @event.sessions.includes(schedules: :speaker).order(:starts_at)
      @days = sessions.group_by { |session| session.starts_at.to_date }
      @unscheduled_talks = @event.schedules.where(session_id: nil).includes(:speaker).order(:starts_at)
    end

    def new
      @schedule = @event.schedules.build(session_id: params[:session_id])
      authorize @event, :update?
    end

    def create
      @schedule = @event.schedules.build(schedule_params)
      authorize @event, :update?

      if @schedule.save
        redirect_to edit_admin_event_path(@event, step: "event_schedule"), notice: warned_notice(@schedule, "#{@schedule.title} added.")
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      authorize @event, :update?
    end

    def update
      authorize @event, :update?

      if @schedule.update(schedule_params)
        redirect_to edit_admin_event_path(@event, step: "event_schedule"), notice: warned_notice(@schedule, "#{@schedule.title} saved.")
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @event, :update?
      @schedule.destroy
      redirect_to edit_admin_event_path(@event, step: "event_schedule"), notice: "#{@schedule.title} removed."
    end

    private

    def set_event
      @event = Event.friendly.find(params[:event_id])
    end

    def set_schedule
      @schedule = @event.schedules.find(params[:id])
    end

    def schedule_params
      params.require(:schedule).permit(:title, :details, :speaker_id, :session_id, :starts_at, :ends_at)
    end

    # requirement.md Phase 11 checklist: "schedule overlap warnings (same speaker double-booked,
    # informational not blocking)" — checked after a successful save, folded into the same flash
    # notice rather than a separate alert, so it never looks like the save itself failed.
    def warned_notice(schedule, base_notice)
      return base_notice unless schedule.speaker_double_booked?

      "#{base_notice} Note: #{schedule.speaker.name} has another talk scheduled at an overlapping time."
    end
  end
end
