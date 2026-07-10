# The single source of truth threaded through every request/job (requirement.md §4.2, §4.3).
#
# - `account` is set by the host-resolution middleware (Phase 0.3) when a request arrives on a
#   tenant's admin subdomain, and must be set explicitly by any background job that touches
#   tenant-scoped data.
# - `platform_request` is set instead of `account` when a request arrives on the apex domain
#   (Platform Console / Super Admin) — those requests are deliberately not tenant-scoped, but are
#   still required to say so explicitly rather than silently falling through (see TenantScoped).
# - `user` is the currently authenticated Devise user, either scope.
class Current < ActiveSupport::CurrentAttributes
  attribute :account, :user, :platform_request
end
