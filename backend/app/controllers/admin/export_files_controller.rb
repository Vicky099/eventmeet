module Admin
  # Phase 7 — Participant Lifecycle (requirement.md §3.11, §5.4), revisited: "Export sidebar
  # button will provide a UI where admin can select the fields which he wants to export." #new is
  # that field picker (ParticipantExportFields.groups, shared with ParticipantExportJob so the
  # picker and the actual workbook build can never disagree on what a key means); #create kicks
  # off ParticipantExportJob with the chosen fields and redirects to #show, a progress-pollable
  # page that turns into a download link once ExportFile#file is attached.
  class ExportFilesController < BaseController
    include EventScoped
    before_action :set_export_file, only: [ :show, :download ]

    def new
      authorize Participant, :index?
      @field_groups = ParticipantExportFields.groups(@event)
      @default_keys = ParticipantExportFields.default_keys
    end

    # Intersected against this event's own current valid keys (not trusted as submitted) — same
    # "never trust a bare id from another event/tenant" reasoning
    # Admin::ScanEventsController#create already applies to session_id.
    def create
      authorize Participant, :index?
      fields = Array(params[:fields]) & ParticipantExportFields.groups(@event).flat_map { |group| group[:fields].map { |field| field[:key] } }

      if fields.empty?
        @field_groups = ParticipantExportFields.groups(@event)
        @default_keys = ParticipantExportFields.default_keys
        flash.now[:alert] = "Select at least one field to export."
        render :new, status: :unprocessable_content
        return
      end

      # Phase 14 — Reporting, Import/Export & Analytics (requirement.md §5.11): "organizer picks
      # columns/format, including CSV/PDF." `file_format`, not `format` — see ExportFile's own
      # comment on why the form field can't be named `format` (a reserved Rails routing/params
      # concept). Falls back to xlsx for anything not a recognized ExportFile#format value, same
      # "never trust a bare submitted value" reasoning as `fields` above.
      export_file = @event.export_files.create!(
        created_by: current_user, fields: fields,
        format: ExportFile.formats.key?(params[:file_format]) ? params[:file_format] : "xlsx"
      )
      ParticipantExportJob.perform_later(export_file.id)
      redirect_to admin_event_export_file_path(@event, export_file)
    end

    def show
      authorize Participant, :index?
    end

    # **Bug fix**: "This res.cloudinary.com page can't be found ... HTTP ERROR 404" — a real
    # Cloudinary-gem bug for "raw" (non-image) resources, not an access restriction; see
    # CloudinaryRawFile's own comment for the full story. #download streams the bytes through
    # this app instead of redirecting straight to the gem's own broken URL.
    def download
      authorize Participant, :index?
      send_data CloudinaryRawFile.download(@export_file.file.blob), filename: @export_file.file.filename.to_s,
        type: @export_file.file.content_type, disposition: "attachment"
    end

    private

    def set_export_file
      @export_file = @event.export_files.find(params[:id])
    end
  end
end
