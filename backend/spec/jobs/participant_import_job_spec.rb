require "rails_helper"

RSpec.describe ParticipantImportJob, type: :job do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  # Builds a real .xlsx in memory (via the same caxlsx gem ParticipantExportJob uses) rather than
  # checking in a binary fixture — keeps the "what's actually in the file" visible right next to
  # the assertions that depend on it.
  def build_import_file(rows)
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Participants") do |sheet|
      sheet.add_row [ "Name", "Email", "Contact Number", "Company", "Govt ID" ]
      rows.each { |row| sheet.add_row(row) }
    end

    import_file = event.import_files.create!(account: account, created_by: create(:user))
    Tempfile.create([ "import", ".xlsx" ]) do |tempfile|
      tempfile.binmode
      package.serialize(tempfile.path)
      tempfile.rewind
      import_file.file.attach(io: tempfile, filename: "import.xlsx", content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    end
    import_file
  end

  it "creates new participants and reports duplicate/new counts for a mixed file" do
    create(:participant, account: account, event: event, first_name: "Existing", last_name: "Person", email: "existing@example.com")

    import_file = build_import_file([
      [ "Alice Smith", "alice@example.com", "555-0001", "Acme", nil ],
      [ "Existing Person", "existing@example.com", nil, nil, nil ], # duplicate of the pre-existing row (email+name)
      [ "Bob Jones", "bob@example.com", "555-0002", "Widgets Inc", nil ]
    ])

    described_class.perform_now(import_file.id)
    import_file.reload

    expect(import_file.status).to eq("completed")
    expect(import_file.total_rows).to eq(3)
    expect(import_file.processed_rows).to eq(3)
    expect(import_file.created_count).to eq(2)
    expect(import_file.duplicate_count).to eq(1)
    expect(import_file.error_count).to eq(0)
    expect(event.participants.count).to eq(3) # 1 pre-existing + 2 newly created
    expect(event.participants.pluck(:name)).to include("Alice Smith", "Bob Jones")
  end

  it "marks imported participants with source: upload" do
    import_file = build_import_file([ [ "Alice Smith", "alice@example.com", nil, nil, nil ] ])

    described_class.perform_now(import_file.id)

    expect(event.participants.find_by!(name: "Alice Smith")).to be_upload
  end

  it "records a per-row error without aborting the rest of the file" do
    # A row with a govt_id that collides with another row's dedupe tier is fine; a genuinely
    # invalid row (blank name after an email-only header match) is what should land in row_errors.
    import_file = build_import_file([
      [ nil, "no-name@example.com", nil, nil, nil ], # invalid: name required
      [ "Valid Person", "valid@example.com", nil, nil, nil ]
    ])

    described_class.perform_now(import_file.id)
    import_file.reload

    expect(import_file.created_count).to eq(1)
    expect(import_file.error_count).to eq(1)
    expect(import_file.row_errors.first["row"]).to eq(2) # header is row 1, so the first data row is 2
    expect(import_file.row_errors.first["message"]).to include("First name")
    expect(event.participants.find_by(name: "Valid Person")).to be_present
  end

  it "skips fully-blank rows instead of counting them as errors" do
    import_file = build_import_file([
      [ "Alice Smith", "alice@example.com", nil, nil, nil ],
      [ nil, nil, nil, nil, nil ]
    ])

    described_class.perform_now(import_file.id)
    import_file.reload

    expect(import_file.created_count).to eq(1)
    expect(import_file.error_count).to eq(0)
    expect(import_file.duplicate_count).to eq(0)
  end

  # Regression: an uploaded import file on the Cloudinary service previously raised
  # ActiveStorage::IntegrityError from `blob.open`'s own checksum verification — a real
  # `cloudinary` gem bug (double-appended extension on "raw" resources) also caught on
  # Admin::ExportFilesController's own download link; see CloudinaryRawFile's own comment for the
  # full story. #process now reads through CloudinaryRawFile.download instead, so it never
  # depends on the gem's own broken URL construction at all.
  it "reads the uploaded workbook through CloudinaryRawFile.download, not blob.open directly" do
    import_file = build_import_file([ [ "Alice Smith", "alice@example.com", nil, nil, nil ] ])
    workbook_bytes = import_file.file.download
    expect(CloudinaryRawFile).to receive(:download).with(import_file.file.blob).and_return(workbook_bytes)

    described_class.perform_now(import_file.id)

    expect(import_file.reload.status).to eq("completed")
    expect(event.participants.find_by(name: "Alice Smith")).to be_present
  end

  # requirement.md revisit: "ticket category column should be there in sample excel sheet. and it
  # should be name of ticket category. find category by name and then attach that category to
  # participant."
  describe "Ticket Category column" do
    def build_import_file_with_category(rows)
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "Participants") do |sheet|
        sheet.add_row [ "Name", "Email", "Ticket Category" ]
        rows.each { |row| sheet.add_row(row) }
      end

      import_file = event.import_files.create!(account: account, created_by: create(:user))
      Tempfile.create([ "import", ".xlsx" ]) do |tempfile|
        tempfile.binmode
        package.serialize(tempfile.path)
        tempfile.rewind
        import_file.file.attach(io: tempfile, filename: "import.xlsx", content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      end
      import_file
    end

    it "finds the category by name (case-insensitive) and attaches it to the participant" do
      # A category with no registration_form falls back to TicketCategory
      # #effective_catalog_fields' own BUILTIN_DEFAULT_CATALOG, which requires every catalog
      # field — real, correct behavior, just not what this test is about; an empty-catalog form
      # keeps only the unconditional first_name requirement, matching what the row actually
      # supplies.
      form = create(:registration_form, account: account, event: event, catalog_fields: {})
      category = create(:ticket_category, account: account, event: event, name: "Visitor", registration_form: form)
      import_file = build_import_file_with_category([ [ "Alice Smith", "alice@example.com", "visitor" ] ])

      described_class.perform_now(import_file.id)

      expect(import_file.reload.created_count).to eq(1)
      expect(event.participants.find_by!(name: "Alice Smith").ticket_category).to eq(category)
    end

    it "creates the participant with no category when the cell is blank" do
      import_file = build_import_file_with_category([ [ "Alice Smith", "alice@example.com", nil ] ])

      described_class.perform_now(import_file.id)

      expect(import_file.reload.created_count).to eq(1)
      expect(event.participants.find_by!(name: "Alice Smith").ticket_category).to be_nil
    end

    it "reports a row error (not a silently-dropped category) for a name that matches none of this event's own categories" do
      create(:ticket_category, account: account, event: event, name: "Visitor")
      import_file = build_import_file_with_category([ [ "Alice Smith", "alice@example.com", "Speaker" ] ])

      described_class.perform_now(import_file.id)
      import_file.reload

      expect(import_file.created_count).to eq(0)
      expect(import_file.error_count).to eq(1)
      expect(import_file.row_errors.first["message"]).to include("Speaker", "not found")
      expect(event.participants.find_by(name: "Alice Smith")).to be_nil
    end

    it "never matches a different event's ticket category of the same name" do
      other_event = create(:event, account: account)
      create(:ticket_category, account: account, event: other_event, name: "Visitor")
      import_file = build_import_file_with_category([ [ "Alice Smith", "alice@example.com", "Visitor" ] ])

      described_class.perform_now(import_file.id)
      import_file.reload

      expect(import_file.error_count).to eq(1)
      expect(event.participants.find_by(name: "Alice Smith")).to be_nil
    end
  end

  # requirement.md revisit: "we should have privilege to set the uniqueness for participant data
  # ... same parameter should be used while importing the data." The category is resolved before
  # the dedupe check specifically so this can read that category's own RegistrationForm
  # #uniqueness_fields — the same config Participant#not_a_duplicate uses for manual entry.
  describe "per-category uniqueness_fields" do
    def build_import_file_with_category(rows)
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "Participants") do |sheet|
        sheet.add_row [ "Name", "Email", "Contact Number", "Ticket Category" ]
        rows.each { |row| sheet.add_row(row) }
      end

      import_file = event.import_files.create!(account: account, created_by: create(:user))
      Tempfile.create([ "import", ".xlsx" ]) do |tempfile|
        tempfile.binmode
        package.serialize(tempfile.path)
        tempfile.rewind
        import_file.file.attach(io: tempfile, filename: "import.xlsx", content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      end
      import_file
    end

    it "does not flag an email match as a duplicate when the category only dedupes on contact_num" do
      form = create(:registration_form, account: account, event: event, catalog_fields: {}, uniqueness_fields: [ "contact_num" ])
      create(:ticket_category, account: account, event: event, name: "Visitor", registration_form: form)
      create(:participant, account: account, event: event, email: "alice@example.com", contact_num: "555-0001")
      import_file = build_import_file_with_category([ [ "Alice Smith", "alice@example.com", "555-9999", "Visitor" ] ])

      described_class.perform_now(import_file.id)
      import_file.reload

      expect(import_file.created_count).to eq(1)
      expect(import_file.duplicate_count).to eq(0)
    end

    it "still flags a contact_num match as a duplicate when the category dedupes on contact_num" do
      form = create(:registration_form, account: account, event: event, catalog_fields: {}, uniqueness_fields: [ "contact_num" ])
      create(:ticket_category, account: account, event: event, name: "Visitor", registration_form: form)
      create(:participant, account: account, event: event, email: "someone-else@example.com", contact_num: "555-0001")
      import_file = build_import_file_with_category([ [ "Alice Smith", "alice@example.com", "555-0001", "Visitor" ] ])

      described_class.perform_now(import_file.id)
      import_file.reload

      expect(import_file.created_count).to eq(0)
      expect(import_file.duplicate_count).to eq(1)
    end
  end

  it "marks the import failed (not per-row errors) when the file itself can't be read" do
    import_file = event.import_files.create!(account: account, created_by: create(:user))
    import_file.file.attach(io: StringIO.new("not a real xlsx"), filename: "bad.xlsx", content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

    described_class.perform_now(import_file.id)
    import_file.reload

    expect(import_file.status).to eq("failed")
    expect(import_file.row_errors).to be_present
  end
end
