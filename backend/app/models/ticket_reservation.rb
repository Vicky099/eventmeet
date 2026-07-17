# Phase 6 — Ticketing (requirement.md §5.3): a group/bulk hold — "one reservation holds N spots
# against a category, with per-seat detail fillable later or via forwarded claim links." Not one
# row per attendee; Phase 7's Participant model is where individual per-seat detail eventually
# attaches. Created/cancelled exclusively through TicketReservationService, which owns the
# capacity math and waitlist promotion this model doesn't do for itself.
class TicketReservation < ApplicationRecord
  include TenantScoped

  belongs_to :event
  belongs_to :ticket_category

  # No "paid"/"confirmed" distinction — requirement.md §5.3's scope note means a reservation that
  # holds a seat at all is already final; no payment gateway exists yet to gate anything further.
  enum :status, { reserved: 0, waitlisted: 1, cancelled: 2 }

  validates :seat_count, numericality: { only_integer: true, greater_than: 0 }
  validates :holder_name, presence: true
  validates :holder_email, presence: true

  before_validation :generate_claim_token, on: :create

  private

  # Thin stub, as the Phase 6 checklist calls for — a real per-seat claim-link consumption flow
  # (validating the token, letting the claimant fill in their own details) is Phase 7/18
  # territory. Exists now so that flow has something to attach to later without a migration.
  def generate_claim_token
    self.claim_token ||= SecureRandom.hex(16)
  end
end
