# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# No extra path needed for the vendored webadmin template CSS (requirement.md §5.14/v11) — it
# lives under app/assets/stylesheets/vendor/webadmin, already covered by Propshaft's default
# app/assets/stylesheets load path. Its JS lives under vendor/javascript instead, pinned via
# config/importmap.rb — see vendor/webadmin_template/README.md for the source template.
