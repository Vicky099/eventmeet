require "rails_helper"

# requirement.md revisit: "If we have govt id then we will upload that list this will be stored in
# database somewhere ... in upload we should have a separate sample xlsx file to upload the
# govtID."
RSpec.describe GovtIdImportJob, type: :job do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  def build_import_file(rows, header: "Govt ID")
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Govt IDs") do |sheet|
      sheet.add_row [ header ]
      rows.each { |row| sheet.add_row([ row ]) }
    end

    import_file = event.govt_id_import_files.create!(account: account, created_by: create(:user))
    Tempfile.create([ "govt_id_import", ".xlsx" ]) do |tempfile|
      tempfile.binmode
      package.serialize(tempfile.path)
      tempfile.rewind
      import_file.file.attach(io: tempfile, filename: "import.xlsx", content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    end
    import_file
  end

  it "adds each value to the event's pool and reports created/duplicate counts" do
    create(:govt_id, account: account, event: event, value: "GID-1") # pre-existing, so the file's own "GID-1" row is a duplicate

    import_file = build_import_file(%w[GID-1 GID-2 GID-3])

    described_class.perform_now(import_file.id)
    import_file.reload

    expect(import_file.status).to eq("completed")
    expect(import_file.total_rows).to eq(3)
    expect(import_file.created_count).to eq(2)
    expect(import_file.duplicate_count).to eq(1)
    expect(event.govt_ids.pluck(:value)).to contain_exactly("GID-1", "GID-2", "GID-3")
  end

  it "matches the header case-insensitively" do
    import_file = build_import_file([ "GID-1" ], header: "govt_id")

    described_class.perform_now(import_file.id)

    expect(import_file.reload.created_count).to eq(1)
  end

  it "skips fully-blank rows" do
    import_file = build_import_file([ "GID-1", nil ])

    described_class.perform_now(import_file.id)
    import_file.reload

    expect(import_file.created_count).to eq(1)
    expect(import_file.duplicate_count).to eq(0)
  end

  it "fails the whole import (not per-row) when the file has no recognized Govt ID column" do
    import_file = build_import_file([ "GID-1" ], header: "Notes")

    described_class.perform_now(import_file.id)
    import_file.reload

    expect(import_file.status).to eq("failed")
    expect(import_file.row_errors.first["message"]).to include("Govt ID")
  end

  # requirement.md revisit: "If we already have participant, and then we got the govtIDs then
  # while uploading the govtID it should automatically assign to the participant."
  describe "backfilling existing participants" do
    it "assigns freshly-imported ids to participants that don't have one yet, oldest first" do
      older = create(:participant, account: account, event: event, govt_id: nil, created_at: 1.day.ago)
      newer = create(:participant, account: account, event: event, govt_id: nil)
      already_has_one = create(:participant, account: account, event: event, govt_id: "PRE-EXISTING")
      import_file = build_import_file([ "GID-1" ])

      described_class.perform_now(import_file.id)

      expect(older.reload.govt_id).to eq("GID-1")
      expect(newer.reload.govt_id).to be_nil
      expect(already_has_one.reload.govt_id).to eq("PRE-EXISTING")
    end

    it "does not touch participants in a different event" do
      other_event = create(:event, account: account)
      other_participant = create(:participant, account: account, event: other_event, govt_id: nil)
      import_file = build_import_file([ "GID-1" ])

      described_class.perform_now(import_file.id)

      expect(other_participant.reload.govt_id).to be_nil
    end
  end

  it "marks the import failed when the file itself can't be read" do
    import_file = event.govt_id_import_files.create!(account: account, created_by: create(:user))
    import_file.file.attach(io: StringIO.new("not a real xlsx"), filename: "bad.xlsx", content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

    described_class.perform_now(import_file.id)
    import_file.reload

    expect(import_file.status).to eq("failed")
    expect(import_file.row_errors).to be_present
  end

  # Regression: same real `cloudinary` gem "raw" resource bug ParticipantImportJob's own spec
  # guards against — see CloudinaryRawFile's own comment for the full story.
  it "reads the uploaded workbook through CloudinaryRawFile.download, not blob.open directly" do
    import_file = build_import_file([ "GID-1" ])
    workbook_bytes = import_file.file.download
    expect(CloudinaryRawFile).to receive(:download).with(import_file.file.blob).and_return(workbook_bytes)

    described_class.perform_now(import_file.id)

    expect(import_file.reload.status).to eq("completed")
    expect(event.govt_ids.find_by(value: "GID-1")).to be_present
  end
end
