require "rails_helper"

# requirement.md revisit: "If we have govt id then we will upload that list this will be stored in
# database somewhere ... in upload we should have a separate sample xlsx file to upload the
# govtID." GovtIdImportJob's own logic is covered directly in spec/jobs/ — this is just the
# controller layer (upload handling, enqueuing, access control), mirroring admin_import_export_
# files_spec.rb's own participant-import coverage.
RSpec.describe "Admin Console govt ID import", type: :request do
  include ActiveJob::TestHelper

  let!(:account) { create(:account, subdomain_slug: "acme") }

  before { host! "acme.example.com" }

  def sign_in_with_role(role)
    user = create(:user, email: "#{role}@acme.example", password: "password123!")
    create(:account_membership, user: user, account: account, role: role)
    sign_in user, scope: :user
  end

  def create_event
    Current.account = account
    create(:event, account: account)
  end

  def fixture_file_upload_xlsx
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Govt IDs") { |sheet| sheet.add_row [ "Govt ID" ] }
    Tempfile.create([ "govt_id_import", ".xlsx" ]) do |tempfile|
      tempfile.binmode
      package.serialize(tempfile.path)
      return Rack::Test::UploadedFile.new(tempfile.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    end
  end

  describe "GET /admin/events/:event_id/govt_id_import_files/new" do
    before { sign_in_with_role(:event_admin) }

    it "shows the current pool's available/assigned counts and links to the sample template" do
      event = create_event
      Current.account = account
      participant = create(:participant, account: account, event: event, govt_id: nil)
      create(:govt_id, account: account, event: event, value: "GID-1")
      create(:govt_id, account: account, event: event, value: "GID-2", participant: participant, assigned_at: Time.current)

      get new_admin_event_govt_id_import_file_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1")
      link = Nokogiri::HTML(response.body).at_css('a:contains("Download sample template")')
      expect(link["href"]).to eq(sample_admin_event_govt_id_import_files_path(event))
      expect(link["data-action"]).to eq("click->download-progress#start")
    end
  end

  describe "POST /admin/events/:event_id/govt_id_import_files" do
    before { sign_in_with_role(:event_admin) }

    it "attaches the upload, enqueues GovtIdImportJob, and redirects to the progress page" do
      event = create_event
      file = fixture_file_upload_xlsx

      expect {
        post admin_event_govt_id_import_files_path(event), params: { govt_id_import_file: { file: file } }
      }.to have_enqueued_job(GovtIdImportJob)

      import_file = Event.unscoped_across_tenants { event.govt_id_import_files.last }
      expect(import_file.file).to be_attached
      expect(response).to redirect_to(admin_event_govt_id_import_file_path(event, import_file))
    end

    it "rejects the request when no file is chosen" do
      event = create_event

      expect {
        post admin_event_govt_id_import_files_path(event), params: { govt_id_import_file: {} }
      }.not_to have_enqueued_job(GovtIdImportJob)

      expect(response).to redirect_to(new_admin_event_govt_id_import_file_path(event))
    end
  end

  describe "GET /admin/events/:event_id/govt_id_import_files/sample" do
    before { sign_in_with_role(:event_admin) }

    it "downloads a real single-column workbook GovtIdImportJob itself can read straight back in" do
      event = create_event

      get sample_admin_event_govt_id_import_files_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.headers["Content-Disposition"]).to include("govt-id-import-template.xlsx")

      Current.account = account
      import_file = event.govt_id_import_files.create!(account: account, created_by: create(:user))
      import_file.file.attach(io: StringIO.new(response.body), filename: "template.xlsx", content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

      GovtIdImportJob.perform_now(import_file.id)

      expect(import_file.reload.status).to eq("completed")
      expect(import_file.created_count).to eq(1)
      expect(event.govt_ids.sole.value).to eq("GOVT-12345")
    end
  end

  describe "access control" do
    it "blocks checkin_staff from starting a govt ID import" do
      event = create_event
      sign_in_with_role(:admin_staff)

      post admin_event_govt_id_import_files_path(event), params: { govt_id_import_file: {} }

      expect(response).to redirect_to(user_root_path)
    end

    it "redirects an unauthenticated request to the tenant login" do
      event = create_event

      get new_admin_event_govt_id_import_file_path(event)

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "cross-tenant isolation (requirement.md §4.2)" do
    it "404s when Account A requests Account B's event's govt ID import page" do
      other_account = create(:account, subdomain_slug: "other")
      Current.account = other_account
      other_event = create(:event, account: other_account)

      sign_in_with_role(:event_admin)

      get new_admin_event_govt_id_import_file_path(other_event.slug)

      expect(response).to have_http_status(:not_found)
    end
  end
end
