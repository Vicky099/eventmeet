require "rails_helper"

RSpec.describe CloudinaryRawFile do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  def attach_blob
    export_file = event.export_files.create!(account: account, created_by: create(:user))
    export_file.file.attach(io: StringIO.new("real bytes"), filename: "participants.xlsx", content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    export_file.file.blob
  end

  describe ".download" do
    it "downloads directly for any non-Cloudinary service (this app's own :test/:local Disk services)" do
      blob = attach_blob

      expect(described_class.download(blob)).to eq("real bytes")
    end

    # Regression: "This res.cloudinary.com page can't be found ... HTTP ERROR 404" on the export
    # download link, and separately an ActiveStorage::IntegrityError inside ParticipantImportJob's
    # own read of an uploaded file — both traced to the same real bug in the `cloudinary` gem's
    # own ActiveStorage::Service::CloudinaryService#public_id, confirmed live against Cloudinary's
    # Admin API: it double-appends the file extension for "raw" resources whenever the blob key
    # already ends in one (which every blob key in this app always does), so the gem's own
    # #url/#download build a link to a resource that was never actually stored under that name.
    it "fetches via the corrected (non-double-extension) public_id for a Cloudinary-backed blob" do
      blob = attach_blob
      allow(blob).to receive(:service_name).and_return("cloudinary")
      fake_service = double("cloudinary_service", instance_variable_get: { folder: "eventmeet/test" })
      allow(blob).to receive(:service).and_return(fake_service)

      expect(Cloudinary::Utils).to receive(:private_download_url)
        .with("eventmeet/test/#{blob.key}", nil, resource_type: "raw", type: "upload", attachment: true)
        .and_return("https://signed.example/download")
      expect(Net::HTTP).to receive(:get).with(URI("https://signed.example/download")).and_return("real bytes")

      expect(described_class.download(blob)).to eq("real bytes")
    end

    # Regression (Phase 14 — Reporting, Import/Export & Analytics, requirement.md §5.11): a PDF
    # export 200'd with a Cloudinary "Resource not found" JSON body silently treated as if it
    # were the real file — hardcoding resource_type: "raw" here 404s for a file Cloudinary itself
    # filed under a *different* resource_type bucket at upload time. Confirmed live against
    # Cloudinary's own Admin API: a genuinely-uploaded PDF export only exists under
    # resource_type: "image" (Cloudinary's own ActiveStorage::Service::CloudinaryService
    # #content_type_to_resource_type maps application/pdf there, not "raw").
    it "fetches a PDF-content-type blob under resource_type: image, not raw" do
      export_file = event.export_files.create!(account: account, created_by: create(:user))
      export_file.file.attach(io: StringIO.new("%PDF-1.4 fake bytes"), filename: "participants.pdf", content_type: "application/pdf")
      blob = export_file.file.blob
      allow(blob).to receive(:service_name).and_return("cloudinary")
      fake_service = double("cloudinary_service", instance_variable_get: { folder: "eventmeet/test" })
      allow(blob).to receive(:service).and_return(fake_service)

      expect(Cloudinary::Utils).to receive(:private_download_url)
        .with("eventmeet/test/#{blob.key}", nil, resource_type: "image", type: "upload", attachment: true)
        .and_return("https://signed.example/download")
      allow(Net::HTTP).to receive(:get).and_return("%PDF-1.4 fake bytes")

      described_class.download(blob)
    end
  end

  describe ".resource_type_for" do
    def blob_with_content_type(content_type)
      export_file = event.export_files.create!(account: account, created_by: create(:user))
      export_file.file.attach(io: StringIO.new("bytes"), filename: "file", content_type: content_type)
      export_file.file.blob
    end

    it "maps xlsx/csv (and anything else generic) to raw" do
      expect(described_class.resource_type_for(blob_with_content_type("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))).to eq("raw")
      expect(described_class.resource_type_for(blob_with_content_type("text/csv"))).to eq("raw")
    end

    it "maps pdf to image (Cloudinary renders/transforms PDF pages)" do
      expect(described_class.resource_type_for(blob_with_content_type("application/pdf"))).to eq("image")
    end

    it "maps video/audio to video" do
      expect(described_class.resource_type_for(blob_with_content_type("video/mp4"))).to eq("video")
      expect(described_class.resource_type_for(blob_with_content_type("audio/mpeg"))).to eq("video")
    end

    it "maps a plain image content type to image" do
      expect(described_class.resource_type_for(blob_with_content_type("image/png"))).to eq("image")
    end
  end
end
