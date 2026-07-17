module Admin
  # Event-scoped speaker roster (requirement.md §3.8, §5.7) — confirmed with user: one roster per
  # event, not a shared account-wide library. Nested under Event, same shape
  # Admin::EventSessionsController/Admin::SchedulesController already use — no dedicated
  # SpeakerPolicy, authorization delegates to the parent Event's own EventPolicy.
  #
  # Every action redirects back into the event wizard's own "speaker" step
  # (edit_admin_event_path(event, step: "speaker")), not a standalone index page — the wizard
  # step itself *is* the management UI (see app/views/admin/events/edit.html.erb), so the user is
  # never dropped onto a page outside the "building this event" flow.
  class SpeakersController < BaseController
    before_action :set_event
    before_action :set_speaker, only: [ :edit, :update, :destroy ]

    def index
      authorize @event, :update?
      @speakers = @event.speakers.order(:name)
    end

    def new
      @speaker = @event.speakers.build
      authorize @event, :update?
    end

    def create
      @speaker = @event.speakers.build(speaker_params)
      authorize @event, :update?

      if @speaker.save
        apply_uploads(@speaker)
        redirect_to edit_admin_event_path(@event, step: "speaker"), notice: "#{@speaker.name} added."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      authorize @event, :update?
    end

    def update
      authorize @event, :update?

      if @speaker.update(speaker_params)
        apply_uploads(@speaker)
        redirect_to edit_admin_event_path(@event, step: "speaker"), notice: "#{@speaker.name} saved."
      else
        render :edit, status: :unprocessable_content
      end
    end

    # dependent: :restrict_with_error (Speaker#schedules) makes #destroy return false — rather
    # than raise — and populate errors when the speaker already has talks scheduled; no rescue
    # needed, just branch on the return value.
    def destroy
      authorize @event, :update?
      if @speaker.destroy
        redirect_to edit_admin_event_path(@event, step: "speaker"), notice: "#{@speaker.name} removed."
      else
        redirect_to edit_admin_event_path(@event, step: "speaker"), alert: @speaker.errors.full_messages.to_sentence
      end
    end

    private

    def set_event
      @event = Event.friendly.find(params[:event_id])
    end

    def set_speaker
      @speaker = @event.speakers.find(params[:id])
    end

    def speaker_params
      params.require(:speaker).permit(:name, :company, :bio, :country, :nationality, :contact_num, :email, :company_details)
    end

    def apply_uploads(speaker)
      photo = params.dig(:speaker, :photo)
      speaker.attach_photo(photo) if photo.present?
    end
  end
end
