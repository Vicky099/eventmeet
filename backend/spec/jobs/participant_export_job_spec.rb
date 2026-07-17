require "rails_helper"

RSpec.describe ParticipantExportJob, type: :job do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  def open_sheet(export_file)
    export_file.file.blob.open { |tempfile| yield Roo::Spreadsheet.open(tempfile.path, extension: :xlsx).sheet(0) }
  end

  it "builds a workbook with exactly the columns the ExportFile was given, in order" do
    create(:participant, account: account, event: event, first_name: "Alice", last_name: "Smith", email: "alice@example.com")
    export_file = event.export_files.create!(account: account, created_by: create(:user), fields: %w[first_name last_name email])

    described_class.perform_now(export_file.id)
    export_file.reload

    expect(export_file.status).to eq("completed")
    expect(export_file.file).to be_attached
    expect(export_file.file.filename.to_s).to end_with(".xlsx")

    open_sheet(export_file) do |sheet|
      expect(sheet.row(1)).to eq([ "First Name", "Last Name", "Email" ])
      expect(sheet.row(2)).to eq([ "Alice", "Smith", "alice@example.com" ])
    end
  end

  # Belt-and-suspenders for any ExportFile row that predates the field picker (fields: [] default).
  it "falls back to ParticipantExportFields.default_keys when fields is empty" do
    create(:participant, account: account, event: event, first_name: "Alice", last_name: "Smith", email: "alice@example.com")
    export_file = event.export_files.create!(account: account, created_by: create(:user))

    described_class.perform_now(export_file.id)

    open_sheet(export_file.reload) { |sheet| expect(sheet.row(1)).to eq(ParticipantExportFields.default_keys.map { |key| ParticipantExportFields.label_for(event, key) }) }
  end

  it "exports a custom field's response, keyed by that field's own id" do
    form = create(:registration_form, account: account, event: event)
    field = create(:custom_field, account: account, registration_form: form, label: "Dietary Needs")
    category = create(:ticket_category, account: account, event: event, registration_form: form)
    create(:participant, account: account, event: event, ticket_category: category, custom_field_values: { field.id.to_s => "Vegetarian" })
    export_file = event.export_files.create!(account: account, created_by: create(:user), fields: [ "custom_field:#{field.id}" ])

    described_class.perform_now(export_file.id)

    open_sheet(export_file.reload) do |sheet|
      expect(sheet.row(1)).to eq([ "Dietary Needs" ])
      expect(sheet.row(2)).to eq([ "Vegetarian" ])
    end
  end

  # requirement.md revisit: "total time spent in session, in which session how much time."
  it "exports per-session time spent, summed across every check-in/out cycle in that session" do
    session = create(:session, account: account, event: event, name: "Keynote Hall")
    participant = create(:participant, account: account, event: event)
    create(:attendance, account: account, event: event, participant: participant, session: session, from: :session, status: :check_out, time_spent_seconds: 600)
    create(:attendance, account: account, event: event, participant: participant, session: session, from: :session, status: :check_out, time_spent_seconds: 900)
    export_file = event.export_files.create!(account: account, created_by: create(:user), fields: [ "session_time:#{session.id}" ])

    described_class.perform_now(export_file.id)

    open_sheet(export_file.reload) do |sheet|
      expect(sheet.row(1)).to eq([ "Time in: Keynote Hall" ])
      expect(sheet.row(2)).to eq([ "25m" ]) # 600 + 900 seconds
    end
  end

  it "exports attendance analytics (checked in, currently in venue, check-in count, total time)" do
    participant = create(:participant, account: account, event: event)
    ScanService.call(event: event, identifier: participant.hex_id, scan_type: "check_in")
    export_file = event.export_files.create!(
      account: account, created_by: create(:user),
      fields: %w[checked_in currently_in_venue check_in_count total_time_in_event]
    )

    described_class.perform_now(export_file.id)

    open_sheet(export_file.reload) do |sheet|
      expect(sheet.row(2)).to eq([ "Yes", "Yes", 1, nil ]) # never checked out — no time_spent_seconds yet
    end
  end

  it "marks the export failed if something blows up mid-build" do
    export_file = event.export_files.create!(account: account, created_by: create(:user))
    allow(Axlsx::Package).to receive(:new).and_raise(StandardError, "boom")

    described_class.perform_now(export_file.id)

    expect(export_file.reload.status).to eq("failed")
  end

  # Phase 14 — Reporting, Import/Export & Analytics (requirement.md §5.11): "organizer picks
  # columns/format, including CSV/PDF, not just the fixed XLSX layout used today."
  describe "format: csv" do
    it "builds a real CSV with exactly the columns the ExportFile was given, in order" do
      create(:participant, account: account, event: event, first_name: "Alice", last_name: "Smith", email: "alice@example.com")
      export_file = event.export_files.create!(
        account: account, created_by: create(:user), fields: %w[first_name last_name email], format: :csv
      )

      described_class.perform_now(export_file.id)
      export_file.reload

      expect(export_file.status).to eq("completed")
      expect(export_file.file.filename.to_s).to end_with(".csv")
      expect(export_file.file.content_type).to eq("text/csv")

      rows = CSV.parse(export_file.file.download)
      expect(rows[0]).to eq([ "First Name", "Last Name", "Email" ])
      expect(rows[1]).to eq([ "Alice", "Smith", "alice@example.com" ])
    end
  end

  # Real Grover/headless-Chrome rendering, not mocked — same convention
  # spec/services/badge_pdf_service_spec.rb already established for this app's one other PDF
  # generator.
  describe "format: pdf" do
    it "builds a real, valid PDF with a row per participant" do
      create(:participant, account: account, event: event, first_name: "Alice", last_name: "Smith", email: "alice@example.com")
      export_file = event.export_files.create!(
        account: account, created_by: create(:user), fields: %w[first_name last_name email], format: :pdf
      )

      described_class.perform_now(export_file.id)
      export_file.reload

      expect(export_file.status).to eq("completed")
      expect(export_file.file.filename.to_s).to end_with(".pdf")
      expect(export_file.file.content_type).to eq("application/pdf")

      reader = PDF::Reader.new(StringIO.new(export_file.file.download))
      text = reader.pages.first.text
      expect(text).to include("First Name", "Alice", "alice@example.com")
    end
  end
end
