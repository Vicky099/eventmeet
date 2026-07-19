# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Local dev fixture — just the one Super Admin login needed to reach the Platform Console.
# Fixed-hierarchy pivot (requirement.md revisit): standalone tenant provisioning no longer exists
# (every Account must come from inside an Agency Console, via AgencyConsole::AccountsController) —
# this file used to also seed a standalone tenant Account/admin directly, bypassing that flow
# entirely; that's no longer a reachable state through the app, so it's not seeded here either.
# Not used in test (specs build their own data via factories).
if Rails.env.local?
  platform_admin = User.find_or_initialize_by(email: "superadmin@eventmeet.example")
  platform_admin.password = "password123!" if platform_admin.new_record?
  platform_admin.platform_staff = true
  platform_admin.save!

  puts "Seeded: platform admin superadmin@eventmeet.example / password123! at lvh.me:3000"
  puts "From there: create an Agency, then log into the agency's own subdomain to create a tenant."
end
