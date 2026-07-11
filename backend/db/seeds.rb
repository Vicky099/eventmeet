# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Phase 0/1 local dev fixtures — lets you manually verify login on both hosts without a real
# Phase 2 provisioning UI (that's what actually creates these in production). Not used in test
# (specs build their own data via factories).
if Rails.env.local?
  account = Account.find_or_create_by!(subdomain_slug: "acme") { |a| a.name = "Acme Events" }

  tenant_admin = User.find_or_initialize_by(email: "admin@acme.example")
  tenant_admin.password = "password123!" if tenant_admin.new_record?
  tenant_admin.save!
  AccountMembership.find_or_create_by!(user: tenant_admin, account: account) { |m| m.role = :owner }

  # Phase 2 (requirement.md §4.9 item 4): every real Account gets one at provisioning time via
  # AccountProvisioning — this seed predates that flow, so it's created directly here to keep the
  # dev fixture's invariants matching what provisioning actually produces.
  account.create_oauth_application!(name: "#{account.name} API") unless account.oauth_application

  platform_admin = User.find_or_initialize_by(email: "superadmin@eventmeet.example")
  platform_admin.password = "password123!" if platform_admin.new_record?
  platform_admin.platform_staff = true
  platform_admin.save!

  puts "Seeded: tenant admin admin@acme.example / password123! at acme.lvh.me:3000"
  puts "Seeded: platform admin superadmin@eventmeet.example / password123! at lvh.me:3000"
end
