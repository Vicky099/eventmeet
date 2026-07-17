# The cloudinary gem's Active Storage adapter (ActiveStorage::Service::CloudinaryService,
# registered as "Cloudinary" in config/storage.yml) lives outside the gem's own autoload
# tree and is never required by the gem itself — ActiveStorage resolves service classes via
# `.constantize`, not `require`, so without this the app boots fine but blows up the moment
# anything touches the :cloudinary service. It patches ActiveStorage::Blob (adds #key
# override), so it must load after that class exists, not at plain initializer time.
ActiveSupport.on_load(:active_storage_blob) do
  require "active_storage/service/cloudinary_service"
end
