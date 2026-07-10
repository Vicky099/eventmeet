require "rails_helper"

# This is the reusable cross-tenant leak test pattern referenced throughout doc/implementation.md —
# copy this shape for every real TenantScoped model starting with Event in Phase 4.
#
# No production model uses TenantScoped yet in Phase 0 (AccountMembership/TenantDomain deliberately
# opt out — see the comments on those models), so this exercises the concern in isolation against
# an anonymous class riding on the account_memberships table, which already has an account_id column.
RSpec.describe TenantScoped do
  before do
    stub_const("TenantScopedTestModel", Class.new(ApplicationRecord) do
      self.table_name = "account_memberships"
      include TenantScoped
    end)
  end

  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }

  before do
    create(:account_membership, account: account_a)
    create(:account_membership, account: account_b)
  end

  it "raises when queried with no Current.account and no Current.platform_request set" do
    expect { TenantScopedTestModel.count }.to raise_error(TenantScoped::MissingTenantContextError)
  end

  it "scopes to Current.account and never returns another tenant's rows" do
    Current.account = account_a

    expect(TenantScopedTestModel.count).to eq(1)
    expect(TenantScopedTestModel.first.account_id).to eq(account_a.id)
  end

  it "does not leak account_a's row when Current.account is account_b" do
    Current.account = account_b

    expect(TenantScopedTestModel.pluck(:account_id)).to eq([ account_b.id ])
  end

  it "opens up to every tenant's rows under Current.platform_request" do
    Current.platform_request = true

    expect(TenantScopedTestModel.count).to eq(2)
  end

  it "opens up to every tenant's rows via .unscoped_across_tenants without requiring platform_request" do
    expect(TenantScopedTestModel.unscoped_across_tenants { TenantScopedTestModel.count }).to eq(2)
  end
end
