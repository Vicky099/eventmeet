# Include in every tenant-scoped model (Event, Participant, Badge, ... from Phase 4 onward).
#
# requirement.md §4.2: "Every query path (web, API, background job, console) must be tenant-scoped
# by construction — a job that forgets to filter by account_id is the #1 cause of cross-tenant data
# leaks in SaaS systems and must be prevented structurally, not just by convention."
#
# This default-scopes every query to Current.account. There are exactly two ways to legitimately
# see across tenants:
#   1. A request on the apex domain (SuperAdmin::) — the host-resolution before_action sets
#      Current.platform_request instead of Current.account, and the scope opens up to `all`.
#   2. An explicit, narrow escape hatch — Model.unscoped_across_tenants { ... } — for rake tasks/
#      console/one-off cross-tenant maintenance where neither of the above applies.
#
# Anything else (a controller action that never ran through the host middleware, a job that forgot
# to set Current.account) raises loudly instead of silently returning every tenant's rows.
module TenantScoped
  extend ActiveSupport::Concern

  class MissingTenantContextError < StandardError; end

  included do
    belongs_to :account

    default_scope do
      if Current.account
        where(account_id: Current.account.id)
      elsif Current.platform_request
        all
      else
        raise MissingTenantContextError,
          "#{name} was queried with no Current.account set and no Current.platform_request — " \
          "set Current.account explicitly (jobs) or route through SuperAdmin:: (apex requests), " \
          "or use .unscoped_across_tenants for a deliberate one-off cross-tenant query."
      end
    end
  end

  class_methods do
    def unscoped_across_tenants(&block)
      Current.set(platform_request: true) { unscoped(&block) }
    end
  end
end
