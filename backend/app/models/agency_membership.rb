# Mirrors AccountMembership exactly, one tier up: join entity between a User and an Agency, not a
# column on either — same reasoning (a user could conceivably manage more than one agency).
class AgencyMembership < ApplicationRecord
  enum :role, { agency_admin: 0 }

  belongs_to :user
  belongs_to :agency

  validates :user_id, uniqueness: { scope: :agency_id }
  validate :user_is_not_platform_staff

  private

  def user_is_not_platform_staff
    return unless user&.platform_staff?

    errors.add(:user, "platform staff cannot hold an AgencyMembership (requirement.md §4.1)")
  end
end
