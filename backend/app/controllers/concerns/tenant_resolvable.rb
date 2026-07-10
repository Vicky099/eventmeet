# Included by the tenant Admin Console's Admin::BaseController. The routing constraint
# (Hosting::TenantSubdomainConstraint) already guarantees the Host is a syntactically valid
# tenant subdomain by the time we get here — this resolves it to a real Account (or 404s) and
# sets Current.account, which every TenantScoped model's default_scope depends on
# (requirement.md §4.2).
module TenantResolvable
  extend ActiveSupport::Concern

  included do
    before_action :resolve_tenant!
    around_action :with_tenant_database_context
  end

  private

  def resolve_tenant!
    slug = Hosting::Resolver.new(request.host).subdomain_label
    account = Account.find_by(subdomain_slug: slug)

    return head :not_found unless account

    Current.account = account
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
end
