class TenantDomain < ApplicationRecord
  # Deliberately does NOT include TenantScoped: this is the table the host-resolution middleware
  # (Phase 0.3) queries by `domain` to figure out what Current.account *should* be — it must be
  # freely findable with no tenant context yet, since resolving it is how that context gets set.

  enum :kind, { subdomain: 0, custom: 1 }
  enum :tls_status, { pending: 0, active: 1, failed: 2 }, prefix: :tls

  belongs_to :account

  validates :domain, presence: true, uniqueness: { case_sensitive: false }

  before_validation { self.domain = domain&.downcase }

  def verified?
    verified_at.present?
  end
end
