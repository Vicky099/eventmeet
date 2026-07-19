# The single source of truth threaded through every request/job (requirement.md §4.2, §4.3).
#
# - `account` is set by the host-resolution middleware (Phase 0.3) when a request arrives on a
#   tenant's admin subdomain, and must be set explicitly by any background job that touches
#   tenant-scoped data.
# - `agency` is set instead of `account` when a request arrives on an Agency's own subdomain
#   (Agency Console, fixed-hierarchy pivot — requirement.md revisit) — mutually exclusive with
#   `account` the same way `platform_request` is, resolved by the same TenantResolvable concern
#   (app/controllers/concerns/tenant_resolvable.rb) that resolves `account`.
# - `platform_request` is set instead of `account` when a request arrives on the apex domain
#   (Platform Console / Super Admin) — those requests are deliberately not tenant-scoped, but are
#   still required to say so explicitly rather than silently falling through (see TenantScoped).
# - `user` is the currently authenticated Devise user, either scope.
class Current < ActiveSupport::CurrentAttributes
  attribute :account, :agency, :user, :platform_request
end
