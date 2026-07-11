class Account < ApplicationRecord
  # requirement.md §4.3: blocked so a tenant can never claim a slug that would collide with a
  # platform route (apex, api, admin app chrome, the shared public-site subdomain, etc.).
  RESERVED_SLUGS = %w[
    www api admin app mail events login platform
  ].freeze

  enum :status, { active: 0, suspended: 1 }

  has_many :account_memberships, dependent: :destroy
  has_many :users, through: :account_memberships
  has_many :tenant_domains, dependent: :destroy
  # requirement.md §4.9 item 4: one OAuth application per Account, auto-created at provisioning
  # time (Phase 2). association extended onto Doorkeeper::Application in
  # config/initializers/doorkeeper_application_account.rb.
  has_one :oauth_application, class_name: "Doorkeeper::Application", dependent: :destroy

  validates :name, presence: true
  validates :subdomain_slug, presence: true,
                              uniqueness: { case_sensitive: false },
                              format: {
                                with: /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/,
                                message: "must be lowercase alphanumeric with hyphens, no leading/trailing hyphen"
                              },
                              length: { minimum: 3, maximum: 63 },
                              exclusion: { in: RESERVED_SLUGS, message: "is a reserved word" }

  before_validation { self.subdomain_slug = subdomain_slug&.downcase }
end
