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
  end
end
