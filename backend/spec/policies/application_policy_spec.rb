require "rails_helper"

RSpec.describe ApplicationPolicy do
  # ApplicationPolicy's private helpers are what every real per-model policy (starting Phase 4)
  # composes into its own predicates, e.g. `def update? = platform_staff? || owner?` — exercised
  # here via a minimal subclass rather than waiting for a real model to build one against.
  let(:policy_class) do
    Class.new(ApplicationPolicy) do
      def platform_bypass? = platform_staff?
      def owner_only? = owner?
    end
  end

  it "denies every default action for a plain new subclass" do
    policy = ApplicationPolicy.new(build(:user), nil)

    expect(policy.index?).to be false
    expect(policy.show?).to be false
    expect(policy.create?).to be false
    expect(policy.update?).to be false
    expect(policy.destroy?).to be false
  end

  it "recognizes platform_staff via the bypass helper" do
    staff = build(:user, :platform_staff)
    expect(policy_class.new(staff, nil).platform_bypass?).to be true
    expect(policy_class.new(build(:user), nil).platform_bypass?).to be false
  end

  it "recognizes an owner-role AccountMembership on Current.account" do
    account = create(:account)
    owner = create(:user)
    create(:account_membership, user: owner, account: account, role: :owner)
    Current.account = account

    expect(policy_class.new(owner, nil).owner_only?).to be true
  end

  it "does not treat a non-owner role as owner" do
    account = create(:account)
    staff_member = create(:user)
    create(:account_membership, user: staff_member, account: account, role: :checkin_staff)
    Current.account = account

    expect(policy_class.new(staff_member, nil).owner_only?).to be false
  end

  describe ApplicationPolicy::Scope do
    it "defaults to scope.all — tenant isolation is TenantScoped's job, not the policy Scope's" do
      relation = instance_double(ActiveRecord::Relation)
      scope = class_double(ActiveRecord::Base, all: relation)

      expect(ApplicationPolicy::Scope.new(build(:user), scope).resolve).to eq(relation)
    end
  end
end
