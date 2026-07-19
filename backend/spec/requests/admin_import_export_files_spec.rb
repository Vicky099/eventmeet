require "rails_helper"

# Phase 7 — Participant Lifecycle (requirement.md §3.11, §5.4). ParticipantImportJob/
# ParticipantExportJob's own logic is covered directly in spec/jobs/ — this is just the
# controller layer (upload handling, enqueuing, access control) with jobs stubbed to run inline.
RSpec.describe "Admin Console participant import/export", type: :request do
  include ActiveJob::TestHelper

  let!(:account) { create(:account, subdomain_slug: "acme") }

  before { host! "acme.example.com" }

  def sign_in_with_role(role)
    user = create(:user, email: "#{role}@acme.example", password: "password123!")
    create(:account_membership, user: user, account: account, role: role)
    sign_in user, scope: :user
    user
  end

  def create_event
    Current.account = account
    create(:event, account: account)
  end

  describe "POST /admin/events/:event_id/import_files" do
    before { sign_in_with_role(:event_admin) }

    it "attaches the upload, enqueues ParticipantImportJob, and redirects to the progress page" do
      event = create_event
      file = fixture_file_upload_xlsx

      expect {
        post admin_event_import_files_path(event), params: { import_file: { file: file } }
      }.to have_enqueued_job(ParticipantImportJob)

      import_file = Event.unscoped_across_tenants { event.import_files.last }
      expect(import_file.file).to be_attached
      expect(response).to redirect_to(admin_event_import_file_path(event, import_file))
    end

    it "rejects the request when no file is chosen" do
      event = create_event

      expect {
        post admin_event_import_files_path(event), params: { import_file: {} }
      }.not_to have_enqueued_job(ParticipantImportJob)

      expect(response).to redirect_to(new_admin_event_import_file_path(event))
    end

    def fixture_file_upload_xlsx
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "Participants") { |sheet| sheet.add_row [ "Name" ] }
      Tempfile.create([ "import", ".xlsx" ]) do |tempfile|
        tempfile.binmode
        package.serialize(tempfile.path)
        return Rack::Test::UploadedFile.new(tempfile.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      end
    end
  end

  # requirement.md revisit: "Import will provide the sample CSV import download option and then
  # in that format admin will enter the user data."
  describe "GET /admin/events/:event_id/import_files/new" do
    before { sign_in_with_role(:event_admin) }

    it "links to the sample template download, wired to the progress-modal controller" do
      event = create_event

      get new_admin_event_import_file_path(event)

      link = Nokogiri::HTML(response.body).at_css('a:contains("Download sample template")')
      expect(link["href"]).to eq(sample_admin_event_import_files_path(event))
      expect(link["data-action"]).to eq("click->download-progress#start")
    end
  end

  describe "GET /admin/events/:event_id/import_files/sample" do
    before { sign_in_with_role(:event_admin) }

    it "downloads a real workbook with the header row plus one filled-in example row" do
      event = create_event

      get sample_admin_event_import_files_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.headers["Content-Disposition"]).to include("participant-import-template.xlsx")

      Tempfile.create([ "downloaded-template", ".xlsx" ]) do |tempfile|
        tempfile.binmode
        tempfile.write(response.body)
        tempfile.rewind
        sheet = Roo::Spreadsheet.open(tempfile.path, extension: :xlsx).sheet(0)
        expect(sheet.row(1)).to eq(ParticipantImportJob::SAMPLE_COLUMNS.map(&:first))
        expect(sheet.row(2)).to eq(ParticipantImportJob::SAMPLE_COLUMNS.map(&:last))
      end
    end

    it "produces a template ParticipantImportJob itself can read straight back in" do
      event = create_event
      Current.account = account
      # The template's own Ticket Category example value ("Visitor" — ParticipantImportJob
      # ::SAMPLE_COLUMNS) only round-trips cleanly once a real category by that name exists on
      # this event, same caveat admin/import_files/new.html.erb's own description text calls out.
      # An empty-catalog registration_form keeps this participant to just the unconditional
      # first_name requirement — same reasoning as the Ticket Category column's own spec.
      form = create(:registration_form, account: account, event: event, catalog_fields: {})
      create(:ticket_category, account: account, event: event, name: "Visitor", registration_form: form)

      get sample_admin_event_import_files_path(event)
      Current.account = account

      import_file = event.import_files.create!(account: account, created_by: create(:user))
      import_file.file.attach(io: StringIO.new(response.body), filename: "template.xlsx", content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

      ParticipantImportJob.perform_now(import_file.id)

      expect(import_file.reload.status).to eq("completed")
      expect(import_file.created_count).to eq(1)
      participant = Event.unscoped_across_tenants { event.participants.last }
      expect(participant.name).to eq("John Doe")
      expect(participant.email).to eq("john.doe@example.com")
      expect(participant.ticket_category.name).to eq("Visitor")
    end
  end

  # requirement.md revisit: "Export sidebar button will provide a UI where admin can select the
  # fields which he wants to export."
  describe "GET /admin/events/:event_id/export_files/new" do
    before { sign_in_with_role(:event_admin) }

    it "shows the field picker, grouped, with sessions/custom fields listed as their own checkboxes" do
      event = create_event
      Current.account = account
      form = create(:registration_form, account: account, event: event)
      custom_field = create(:custom_field, account: account, registration_form: form, label: "Dietary Needs")
      session = create(:session, account: account, event: event, name: "Keynote Hall")

      get new_admin_event_export_file_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("First Name")
      expect(response.body).to include(custom_field.label)
      expect(response.body).to include("Time in: #{session.name}")
    end
  end

  describe "POST /admin/events/:event_id/export_files" do
    before { sign_in_with_role(:event_admin) }

    it "creates an ExportFile with the chosen fields, enqueues ParticipantExportJob, and redirects to the progress page" do
      event = create_event

      expect {
        post admin_event_export_files_path(event), params: { fields: [ "first_name", "email" ] }
      }.to have_enqueued_job(ParticipantExportJob)

      export_file = Event.unscoped_across_tenants { event.export_files.last }
      expect(export_file.fields).to eq([ "first_name", "email" ])
      expect(response).to redirect_to(admin_event_export_file_path(event, export_file))
    end

    it "drops any field key that isn't a real, current field for this event" do
      event = create_event

      post admin_event_export_files_path(event), params: { fields: [ "first_name", "not_a_real_field" ] }

      export_file = Event.unscoped_across_tenants { event.export_files.last }
      expect(export_file.fields).to eq([ "first_name" ])
    end

    # Phase 14 — Reporting, Import/Export & Analytics (requirement.md §5.11): "organizer picks
    # columns/format, including CSV/PDF, not just the fixed XLSX layout used today."
    it "creates an ExportFile with the chosen format" do
      event = create_event

      post admin_event_export_files_path(event), params: { fields: [ "first_name" ], file_format: "csv" }

      export_file = Event.unscoped_across_tenants { event.export_files.last }
      expect(export_file.format).to eq("csv")
    end

    it "falls back to xlsx for an unrecognized format value" do
      event = create_event

      post admin_event_export_files_path(event), params: { fields: [ "first_name" ], file_format: "not_a_real_format" }

      export_file = Event.unscoped_across_tenants { event.export_files.last }
      expect(export_file.format).to eq("xlsx")
    end

    it "rejects the request (no job enqueued) when nothing is selected" do
      event = create_event

      expect {
        post admin_event_export_files_path(event), params: { fields: [] }
      }.not_to have_enqueued_job(ParticipantExportJob)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Select at least one field")
    end
  end

  # requirement.md revisit: "download will open modal and show the progress bar and once 100%
  # done then modal will close automatically and xlsx will download" — superseded the earlier
  # "opens in a new tab" behavior: download_progress_controller.js now intercepts the click
  # entirely (fetch + a synthetic <a download> of the resulting blob), so this never actually
  # navigates anywhere — target="_blank" is no longer meaningful and was removed.
  describe "GET /admin/events/:event_id/export_files/:id (download link)" do
    before { sign_in_with_role(:event_admin) }

    it "wires the download link to the progress-modal controller" do
      event = create_event
      Current.account = account
      export_file = event.export_files.create!(account: account, created_by: create(:user), status: :completed, fields: [ "first_name" ])
      export_file.file.attach(io: StringIO.new("fake xlsx"), filename: "participants.xlsx", content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

      get admin_event_export_file_path(event, export_file)

      link = Nokogiri::HTML(response.body).at_css('a:contains("Download .xlsx")')
      expect(link["href"]).to eq(download_admin_event_export_file_path(event, export_file))
      expect(link["data-action"]).to eq("click->download-progress#start")
    end
  end

  # Regression: "This res.cloudinary.com page can't be found ... HTTP ERROR 404" — confirmed live
  # against Cloudinary's own Admin API that the uploaded file genuinely exists; the `cloudinary`
  # gem's own ActiveStorage::Service::CloudinaryService#public_id has a real bug for "raw" (non-
  # image) resources, double-appending the file extension whenever the blob key already ends in
  # one (which every blob key in this app always does) — every #url/#download call the gem builds
  # ends up pointed at "...xlsx.xlsx", a resource that was never actually stored under that name.
  # #download (Admin::ExportFilesController's own comment has the full story) reconstructs the
  # *correct* public_id itself and fetches it through Cloudinary's authenticated download
  # endpoint instead of the gem's own broken URL builder.
  describe "GET /admin/events/:event_id/export_files/:id/download" do
    before { sign_in_with_role(:event_admin) }

    it "streams the workbook's real bytes through this app (the :test service — no Cloudinary involved)" do
      event = create_event
      Current.account = account
      export_file = event.export_files.create!(account: account, created_by: create(:user), status: :completed, fields: [ "first_name" ])
      export_file.file.attach(io: StringIO.new("fake xlsx bytes"), filename: "participants.xlsx", content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

      get download_admin_event_export_file_path(event, export_file)

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("fake xlsx bytes")
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.headers["Content-Disposition"]).to include("participants.xlsx")
    end

    # The actual bug-fix logic (correct public_id construction, Cloudinary fetch, the :test
    # service fallback) is shared with ParticipantImportJob and covered directly in
    # spec/services/cloudinary_raw_file_spec.rb — nothing Cloudinary-specific worth duplicating
    # here beyond the plain :test-service round trip already asserted above.
  end

  describe "access control" do
    it "blocks checkin_staff from starting an import" do
      event = create_event
      sign_in_with_role(:admin_staff)

      post admin_event_import_files_path(event), params: { import_file: {} }

      expect(response).to redirect_to(user_root_path)
    end
  end
end
