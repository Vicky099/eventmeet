# Agency layer (requirement.md revisit): adds a new agency_admin to an EXISTING Agency
# (SuperAdmin::AgencyMembershipsController#create) — distinct from AgencyProvisioning, which only
# ever creates an agency's very first agency_admin alongside the Agency itself.
#
# find_or_initialize_by(email:) — this app has no general "invite a teammate" flow yet (every
# tenant's own first admin comes from AccountProvisioning; there's nothing analogous for adding a
# *second* one), so this covers both cases a Super Admin might actually mean by "add this email to
# the agency": a brand-new person (gets a temp password, same forced-reset flow every other
# provisioned user gets) or an existing platform User who already has other memberships elsewhere
# (reused as-is, no password touched).
#
# Either way, every one of the agency's EXISTING tenant Accounts gets an event_admin
# AccountMembership for this user too — the same backfill AccountProvisioning's own agency: kwarg
# does for a brand-new tenant, just run in the other direction (existing tenants, new agency staff).
class AgencyMembershipProvisioning
  Result = Struct.new(:agency_membership, :user, :temp_password, :success, keyword_init: true) do
    alias_method :success?, :success
  end

  def self.call(...)
    new(...).call
  end

  def initialize(agency:, email:)
    @agency = agency
    @user = User.find_or_initialize_by(email: email)
    @is_new_user = !@user.persisted?
    @temp_password = @is_new_user ? SecureRandom.base58(16) : nil
  end

  def call
    success = false
    membership = nil

    ActiveRecord::Base.transaction do
      if is_new_user
        user.password = temp_password
        user.must_reset_password = true
        unless user.save
          agency.errors.merge!(user.errors)
          raise ActiveRecord::Rollback
        end
      end

      membership = AgencyMembership.new(user: user, agency: agency, role: :agency_admin)
      unless membership.save
        agency.errors.merge!(membership.errors)
        raise ActiveRecord::Rollback
      end

      agency.accounts.each do |account|
        next if AccountMembership.exists?(user: user, account: account)

        AccountMembership.create!(user: user, account: account, role: :event_admin)
      end

      success = true
    end

    if success
      if is_new_user
        AgencyMailer.welcome(user, agency, temp_password).deliver_later
      else
        AgencyMailer.added_to_agency(user, agency).deliver_later
      end
    end

    Result.new(agency_membership: membership, user: user, temp_password: temp_password, success: success)
  end

  private

  attr_reader :agency, :user, :is_new_user, :temp_password
end
