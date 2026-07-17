module Admin
  # Phase 7 — Participant Lifecycle (requirement.md §3.4, §5.4). Nested under Event — every
  # Participant belongs to exactly one, and dedupe/custom-fields/document-requiredness are all
  # scoped to it. No dedicated "show" page (mirrors Admin::EventsController's own "no separate
  # show" call) — the index row + edit form is the whole workspace, there's nothing a read-only
  # detail page would add that the edit form doesn't already have.
  class ParticipantsController < BaseController
    include EventScoped
    before_action :set_participant, only: [ :edit, :update, :destroy, :approve, :badge ]

    # requirement.md §5.4: "Admin search/filter across identifier fields; paginated listing."
    def index
      authorize Participant

      @query = params[:q].to_s.strip
      scope = @event.participants.order(created_at: :desc)
      if @query.present?
        scope = scope.where(
          "name ILIKE :q OR email ILIKE :q OR contact_num ILIKE :q OR govt_id ILIKE :q OR rf_id ILIKE :q OR hex_id ILIKE :q OR client_participant_id ILIKE :q",
          q: "%#{@query}%"
        )
      end
      @pagy, @participants = pagy(scope, limit: 25)
    end

    def new
      @participant = @event.participants.build
      authorize @participant
    end

    def create
      @participant = @event.participants.build(fixed_field_params.merge(source: :manual, status: @event.default_participant_status))
      authorize @participant
      apply_uploads(@participant)

      if @participant.save
        redirect_to admin_event_participants_path(@event), notice: "#{@participant.name} added."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      authorize @participant
    end

    def update
      authorize @participant
      @participant.assign_attributes(fixed_field_params)
      apply_uploads(@participant)

      if @participant.save
        redirect_to admin_event_participants_path(@event), notice: "#{@participant.name} updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @participant
      @participant.destroy
      redirect_to admin_event_participants_path(@event), notice: "#{@participant.name} removed."
    end

    # requirement.md §5.4/§5.14 v12 revisit: "when i select the ticket category then the form
    # fields are not able to view below. ideally it should check the fields configured and then
    # show the form." Backs ticket_category_fields_controller.js's Turbo Frame src repoint —
    # re-renders admin/participants/_dynamic_fields against whichever ticket_category was just
    # selected. For an existing participant (edit), loads the real record so every already-stored
    # attribute (title, company, custom_field_values, attached photo/document) still shows —
    # only the in-memory ticket_category assignment changes, nothing is persisted here. For a new
    # participant, there's nothing persisted to read back, so the section simply starts blank
    # again on every category switch — an accepted trade-off, not a bug.
    def dynamic_fields
      @participant = params[:participant_id].present? ? @event.participants.find(params[:participant_id]) : @event.participants.build
      authorize @participant, @participant.persisted? ? :update? : :create?
      @participant.ticket_category = @event.ticket_categories.find_by(id: params[:ticket_category_id])

      render partial: "dynamic_fields", locals: { participant: @participant, event: @event }
    end

    # requirement.md §3.4: "Bulk destroy, per-participant edit/delete."
    def bulk_destroy
      authorize Participant, :destroy?

      count = @event.participants.where(id: Array(params[:participant_ids])).destroy_all.size
      redirect_to admin_event_participants_path(@event), notice: "#{count} participant(s) removed."
    end

    # requirement.md §5.4: "Approval-based registration toggle... organizer must approve before a
    # participant is considered confirmed." Only meaningful when Event#participant_approval_required?
    # is on — harmless no-op otherwise (an already-confirmed participant just stays confirmed).
    def approve
      authorize @participant, :update?
      @participant.update!(status: :confirmed)
      redirect_to admin_event_participants_path(@event), notice: "#{@participant.name} approved."
    end

    # Phase 8 — Badge Design & Printing (requirement.md §3.6): "on-demand single-badge download
    # endpoint." Event#badge_for resolves the applicable Badge (this participant's own ticket
    # category first, falling back to the event's default) — nil means nothing's been designed
    # yet for this event, a plain redirect back with an alert rather than a broken download.
    def badge
      authorize @participant, :show?
      badge = @event.badge_for(@participant)
      if badge.nil?
        redirect_to admin_event_participants_path(@event), alert: "No badge has been designed for this event yet."
        return
      end

      # Phase 9 (requirement.md §6 item 13): "printing ... subscribe to [the same] Scan Event
      # abstraction" — this is print's own single write path (on-demand only; auto-print via the
      # paired agent is Phase 10), same as ScanService is check-in/out's.
      ScanEvent.create!(
        account: @event.account, event: @event, participant: @participant,
        scan_type: :print, source: :manual, scanned_at: Time.current
      )

      pdf = BadgePdfService.render(badge: badge, participant: @participant)
      send_data pdf, filename: "badge-#{@participant.hex_id}.pdf", type: "application/pdf", disposition: "inline"
    end

    private

    def set_participant
      @participant = @event.participants.find(params[:id])
    end

    # custom_field_values is permitted here (silencing Rails' "Unpermitted parameter" log warning,
    # otherwise logged on every single participant create/update) but deliberately never part of
    # what actually gets mass-assigned — #apply_custom_field_values reads it key-by-key against
    # the event's own real CustomField ids instead. Mass-assigning it directly would be actively
    # wrong, not just redundant: a file-type field's value here is a raw uploaded-file object, and
    # jsonb-serializing that straight into the column (rather than routing it through
    # Participant#attach_custom_field_file) would blow up or silently store garbage.
    def participant_params
      params.require(:participant).permit(
        :ticket_category_id, :title, :first_name, :last_name, :email, :contact_num, :company, :department, :position,
        :nationality, :country, :govt_id, :rf_id,
        custom_field_values: {}
      )
    end

    def fixed_field_params
      participant_params.except(:custom_field_values)
    end

    # photo/document are fixed has_one_attached slots; custom_field_values may additionally carry
    # per-CustomField responses, one of which might itself be a file upload (field_type: file) —
    # those need Participant#attach_custom_field_file instead of a plain mass-assignable column.
    def apply_uploads(participant)
      # "participants", event_id, attachment_name — TenantScopedAttachment#attach_tenant_scoped's
      # segments, matching the exact key shape this model has always used. photo is now uploaded
      # client-side (image_upload_controller.js, straight to Cloudinary) — see
      # Admin::DirectUploadsController for where that same segment shape gets computed ahead of
      # time, before this attach call ever runs.
      photo = params.dig(:participant, :photo)
      participant.attach_tenant_scoped(:photo, photo, "participants", participant.event_id, :photo) if photo.present?

      document = params.dig(:participant, :document)
      participant.attach_tenant_scoped(:document, document, "participants", participant.event_id, :document) if document.present?

      apply_custom_field_values(participant)
    end

    # Phase 7.5 — custom fields now come from the participant's own ticket_category (via its
    # resolved RegistrationForm), not the event as a whole; a participant with no ticket_category
    # selected, or a category with neither its own form nor the event's default configured yet,
    # simply has none to apply.
    def apply_custom_field_values(participant)
      custom_fields = participant.ticket_category&.registration_form&.custom_fields
      return if custom_fields.blank?

      custom_fields.find_each do |field|
        raw = params.dig(:participant, :custom_field_values, field.id.to_s)
        next if raw.nil?

        case field.field_type
        when "file"
          participant.attach_custom_field_file(field.id, raw) if raw.respond_to?(:original_filename)
        when "checkbox"
          participant.custom_field_values[field.id.to_s] = ActiveModel::Type::Boolean.new.cast(raw)
        else
          participant.custom_field_values[field.id.to_s] = raw
        end
      end
    end
  end
end
