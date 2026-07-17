module Admin
  # Phase 6 — Ticketing (requirement.md §5.3). Nested under Event, backing the wizard's Tickets
  # step — group/bulk reservations against a TicketCategory, manually entered by staff (there's no
  # public self-service registration flow yet; that's Phase 7/18). Capacity math and waitlist
  # promotion both live in TicketReservationService, not here.
  class TicketReservationsController < BaseController
    before_action :set_event
    before_action :set_ticket_category, only: [ :create ]
    before_action :set_reservation, only: [ :cancel ]

    def create
      authorize @event, :update?

      result = TicketReservationService.reserve(
        ticket_category: @ticket_category,
        seat_count: reservation_params[:seat_count],
        holder_name: reservation_params[:holder_name],
        holder_email: reservation_params[:holder_email]
      )

      if result.success?
        word = result.reservation.waitlisted? ? "waitlisted" : "reserved"
        redirect_to edit_admin_event_path(@event, step: "tickets"),
          notice: "#{result.reservation.seat_count} seat(s) #{word} for #{result.reservation.holder_name}."
      else
        redirect_to edit_admin_event_path(@event, step: "tickets"), alert: result.reservation.errors.full_messages.to_sentence
      end
    end

    def cancel
      authorize @event, :update?

      TicketReservationService.cancel(@reservation)
      redirect_to edit_admin_event_path(@event, step: "tickets"), notice: "Reservation for #{@reservation.holder_name} cancelled."
    end

    private

    def set_event
      @event = Event.friendly.find(params[:event_id])
    end

    def set_ticket_category
      @ticket_category = @event.ticket_categories.find(params[:ticket_category_id])
    end

    def set_reservation
      @reservation = TicketReservation.where(event: @event).find(params[:id])
    end

    def reservation_params
      params.require(:ticket_reservation).permit(:seat_count, :holder_name, :holder_email)
    end
  end
end
