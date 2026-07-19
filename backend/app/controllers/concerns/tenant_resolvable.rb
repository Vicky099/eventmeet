# Included by both the tenant Admin Console's Admin::BaseController and the Agency Console's
# AgencyConsole::BaseController (fixed-hierarchy pivot, requirement.md revisit) — both consoles share the
# exact same subdomain routing constraint (Hosting::TenantSubdomainConstraint) and the exact same
# :user Devise login (an agency_admin is an ordinary :user-scope User who also needs to log into
# *tenant* subdomains with the same credentials, unlike :platform_staff's genuinely separate role/
# scope — see AgencyConsole::BaseController's own comment). Resolves the Host to a real Account OR a real
# Agency (or 404s if neither), setting Current.account or Current.agency accordingly — every
# TenantScoped model's default_scope depends on the former (requirement.md §4.2); the latter is
# what AgencyConsole::BaseController's own before_action requires instead.
module TenantResolvable
  extend ActiveSupport::Concern

  included do
    before_action :resolve_tenant!
    around_action :with_tenant_database_context
    around_action :with_tenant_time_zone
  end

  private

  def resolve_tenant!
    slug = Hosting::Resolver.new(request.host).subdomain_label
    account = Account.find_by(subdomain_slug: slug)

    if account
      Current.account = account
      return
    end

    agency = Agency.find_by(subdomain_slug: slug)
    return head :not_found unless agency

    Current.agency = agency
  end

  # requirement.md §4.2's database-level defense-in-depth (see lib/tenant_row_level_security.rb):
  # sets the Postgres session variable every RLS policy checks, for the lifetime of this action.
  # Reset unconditionally in the ensure block — connections are reused across requests via the
  # pool, so a stale value must never leak into the next request served on the same connection.
  def with_tenant_database_context
    return yield unless Current.account

    quoted_id = ActiveRecord::Base.connection.quote(Current.account.id)
    ActiveRecord::Base.connection.execute("SET app.current_account_id = #{quoted_id}")
    yield
  ensure
    ActiveRecord::Base.connection.execute("RESET app.current_account_id") if Current.account
  end

  # requirement.md revisit: "all the dates which are display in the UI should abey the tenant
  # timezone." Time.use_zone (not a bare `Time.zone = ...`) — it saves/restores the previous
  # thread-local zone around the block, the same "must never leak into the next request served on
  # this connection" concern with_tenant_database_context's own comment already calls out, just
  # for Time.zone instead of the Postgres session var. Every existing strftime/to_fs call on an AR
  # timestamp attribute already renders correctly once this is set — Rails' own
  # time_zone_aware_attributes (on by default, confirmed still on for this app) converts every
  # such attribute from its UTC storage to Time.zone on read, with no per-view change needed.
  def with_tenant_time_zone(&block)
    return yield unless Current.account

    Time.use_zone(Current.account.time_zone, &block)
  end
end
