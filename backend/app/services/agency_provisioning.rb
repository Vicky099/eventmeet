# Agency layer (requirement.md revisit): the only way an Agency comes into existence — Super
# Admin-provisioned from the Platform Console (SuperAdmin::AgenciesController), mirrors
# AccountProvisioning (app/services/account_provisioning.rb) one tier up. One call creates the
# Agency, its first agency_admin User with a temp password (reuses Phase 1's forced-reset flow,
# User#must_reset_password), and the AgencyMembership tying them together — all in one transaction.
class AgencyProvisioning
  Result = Struct.new(:agency, :admin_user, :temp_password, :success, keyword_init: true) do
    alias_method :success?, :success
  end

  def self.call(...)
    new(...).call
  end

  def initialize(agency_attributes:, admin_email:)
    @agency = Agency.new(agency_attributes)
    @temp_password = SecureRandom.base58(16)
    @admin_user = User.new(email: admin_email, password: @temp_password, must_reset_password: true)
  end

  def call
    success = false

    # Same "success is a plain local, not derived from the in-memory objects afterwards" reasoning
    # as AccountProvisioning's own comment — ActiveRecord::Rollback doesn't un-set persisted?/id.
    ActiveRecord::Base.transaction do
      raise ActiveRecord::Rollback unless agency.save

      unless admin_user.save
        admin_user.errors.each { |error| agency.errors.add(:admin_email, error.message) }
        raise ActiveRecord::Rollback
      end

      AgencyMembership.create!(user: admin_user, agency: agency, role: :agency_admin)
      # Fixed-hierarchy pivot (requirement.md revisit): an `annual` agency's one upfront contract
      # Invoice is raised right here, in the same transaction — Agency#contract_active? (the gate
      # both AgencyConsole::AccountsController#create and Event's own creation validation check) reads
      # `invoice&.paid?`, so a draft has to exist from the moment the agency itself does, same
      # "auto-create it so nobody has to remember to raise one" reasoning InvoiceGenerationJob's
      # own comment already established for the per-event path.
      Invoice.generate_for_agency_contract(agency) if agency.annual?
      success = true
    end

    AgencyMailer.welcome(admin_user, agency, temp_password).deliver_later if success

    Result.new(agency: agency, admin_user: admin_user, temp_password: temp_password, success: success)
  end

  private

  attr_reader :agency, :admin_user, :temp_password
end
