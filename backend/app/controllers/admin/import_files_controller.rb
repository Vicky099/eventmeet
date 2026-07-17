module Admin
  # Phase 7 — Participant Lifecycle (requirement.md §3.11, §5.4): bulk XLSX participant import.
  # #new is the upload form, #create kicks off ParticipantImportJob and redirects straight to
  # #show, which is the progress-pollable page (a plain meta-refresh while processing — see the
  # view — rather than a JS polling loop, since this phase has no other place that needs one).
  class ImportFilesController < BaseController
    include EventScoped
    before_action :set_import_file, only: [ :show ]

    def new
      authorize Participant, :create?
    end

    def create
      authorize Participant, :create?

      import_file = @event.import_files.build(created_by: current_user)
      uploaded = params.dig(:import_file, :file)
      if uploaded.blank?
        redirect_to new_admin_event_import_file_path(@event), alert: "Choose a .xlsx file to import."
        return
      end

      import_file.attach_tenant_scoped(uploaded)
      import_file.save!
      ParticipantImportJob.perform_later(import_file.id)
      redirect_to admin_event_import_file_path(@event, import_file)
    end

    def show
      authorize Participant, :create?
    end

    # requirement.md revisit: "Import will provide the sample CSV import download option and
    # then in that format admin will enter the user data." A plain, synchronous download (no
    # ExportFile row, no background job, no Cloudinary round-trip at all) — this is a small,
    # static template, not a per-event generated report, so none of ParticipantExportJob's own
    # machinery applies here. ParticipantImportJob::SAMPLE_COLUMNS is the single source for both
    # this template's own columns and what #row_attributes actually recognizes on the way back in.
    def sample
      authorize Participant, :create?

      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "Participants") do |sheet|
        sheet.add_row ParticipantImportJob::SAMPLE_COLUMNS.map(&:first)
        sheet.add_row ParticipantImportJob::SAMPLE_COLUMNS.map(&:last)
      end

      Tempfile.create([ "participant-import-template", ".xlsx" ]) do |tempfile|
        tempfile.binmode
        package.serialize(tempfile.path)
        send_data File.read(tempfile.path), filename: "participant-import-template.xlsx",
          type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", disposition: "attachment"
      end
    end

    private

    def set_import_file
      @import_file = @event.import_files.find(params[:id])
    end
  end
end
