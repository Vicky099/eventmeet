module Admin
  # requirement.md revisit: "If we have govt id then we will upload that list ... in upload we
  # should have a separate sample xlsx file to upload the govtID." Mirrors Admin::
  # ImportFilesController's own new/create/show/sample shape exactly (Phase 7) — a distinct
  # controller, not a branch inside that one, matching this app's one-controller-per-upload-flow
  # convention (ImportFilesController/ExportFilesController are already separate despite the
  # near-identical shape). authorize against Participant, same as ImportFilesController — the govt
  # ID pool exists purely to populate Participant#govt_id, not a resource of its own with separate
  # permissions.
  class GovtIdImportFilesController < BaseController
    include EventScoped
    before_action :set_govt_id_import_file, only: [ :show ]

    def new
      authorize Participant, :create?
      @available_count = @event.govt_ids.available.count
      @assigned_count = @event.govt_ids.assigned.count
    end

    def create
      authorize Participant, :create?
      import_file = @event.govt_id_import_files.build(created_by: current_user)
      uploaded = params.dig(:govt_id_import_file, :file)
      if uploaded.blank?
        redirect_to new_admin_event_govt_id_import_file_path(@event), alert: "Choose a .xlsx file to import."
        return
      end
      import_file.attach_tenant_scoped(uploaded)
      import_file.save!
      GovtIdImportJob.perform_later(import_file.id)
      redirect_to admin_event_govt_id_import_file_path(@event, import_file)
    end

    def show
      authorize Participant, :create?
    end

    def sample
      authorize Participant, :create?
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "Govt IDs") do |sheet|
        sheet.add_row GovtIdImportJob::SAMPLE_COLUMNS.map(&:first)
        sheet.add_row GovtIdImportJob::SAMPLE_COLUMNS.map(&:last)
      end
      Tempfile.create([ "govt-id-import-template", ".xlsx" ]) do |tempfile|
        tempfile.binmode
        package.serialize(tempfile.path)
        send_data File.read(tempfile.path), filename: "govt-id-import-template.xlsx",
          type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", disposition: "attachment"
      end
    end

    private

    def set_govt_id_import_file
      @govt_id_import_file = @event.govt_id_import_files.find(params[:id])
    end
  end
end
