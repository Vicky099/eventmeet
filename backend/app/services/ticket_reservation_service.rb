# Phase 6 — Ticketing (requirement.md §5.3). Owns the two pieces of capacity math the checklist
# calls out as belonging to a service object: waitlisting instead of rejecting when a category is
# full, and auto-promoting the next waitlisted entry when a seat frees up. TicketCategory#sync_
# counts!/TicketReservation stay dumb about both — this is the one place that decides.
class TicketReservationService
  Result = Struct.new(:reservation, :success, keyword_init: true) do
    alias_method :success?, :success
  end

  def self.reserve(...)
    new.reserve(...)
  end

  def self.cancel(...)
    new.cancel(...)
  end

  # remain_count is resynced immediately before the capacity check — TicketCategory's stored
  # counts are a cache of its reservations, not a lock; this doesn't need to be airtight against
  # concurrent requests in this phase (no payment/inventory-race scenario exists yet to make that
  # matter), just correct for the normal single-organizer-at-a-time admin console usage.
  def reserve(ticket_category:, seat_count:, holder_name:, holder_email:)
    ticket_category.sync_counts!
    seats = seat_count.to_i
    fits = ticket_category.unlimited? || ticket_category.remain_count >= seats
    status = seats.positive? && fits ? :reserved : :waitlisted

    reservation = ticket_category.ticket_reservations.new(
      event: ticket_category.event,
      seat_count: seat_count,
      holder_name: holder_name,
      holder_email: holder_email,
      status: status
    )
    success = reservation.save
    ticket_category.sync_counts! if success

    Result.new(reservation: reservation, success: success)
  end

  def cancel(reservation)
    return Result.new(reservation: reservation, success: false) if reservation.cancelled?

    was_holding_a_seat = reservation.reserved?
    reservation.update!(status: :cancelled, cancelled_at: Time.current)

    category = reservation.ticket_category
    category.sync_counts!
    promote_waitlist(category) if was_holding_a_seat

    Result.new(reservation: reservation, success: true)
  end

  private

  # FIFO, first-fit-only: the oldest waitlisted reservation is promoted first, but only if it
  # fully fits in whatever capacity is currently free — a 5-seat group either gets all 5 seats or
  # stays waitlisted for a later release, never partially split. Keeps iterating in case one
  # cancellation frees enough room for more than one waitlisted group at once.
  def promote_waitlist(category)
    return if category.unlimited?

    category.ticket_reservations.waitlisted.order(:created_at).each do |candidate|
      category.reload
      break if category.remain_count <= 0
      next if candidate.seat_count > category.remain_count

      candidate.update!(status: :reserved)
      category.sync_counts!
    end
  end
end
