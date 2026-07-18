module Admin
  # Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1, §8). The admin-facing
  # management surface for print stations: create a station, generate a pairing code for the
  # operator to type into the Electron app, revoke a paired agent, and (via #update_settings) the
  # event-wide auto-print toggle + default-station picker.
  class PrintStationsController < BaseController
    include EventScoped
    before_action :set_print_station, only: [ :edit, :update, :destroy, :generate_pairing_code, :revoke ]

    def index
      authorize PrintStation
      @print_stations = @event.print_stations.order(:created_at)
    end

    def new
      @print_station = @event.print_stations.build
      authorize @print_station
    end

    def create
      @print_station = @event.print_stations.build(print_station_params)
      authorize @print_station

      if @print_station.save
        redirect_to admin_event_print_stations_path(@event), notice: "#{@print_station.name} added."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      authorize @print_station
    end

    def update
      authorize @print_station

      if @print_station.update(print_station_params)
        redirect_to admin_event_print_stations_path(@event), notice: "#{@print_station.name} saved."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @print_station
      @print_station.destroy
      redirect_to admin_event_print_stations_path(@event), notice: "#{@print_station.name} removed."
    end

    def generate_pairing_code
      authorize @print_station, :update?
      @print_station.generate_pairing_code!
      redirect_to admin_event_print_stations_path(@event), notice: "Pairing code generated for #{@print_station.name} — valid for 10 minutes."
    end

    # Phase 10 (requirement.md: "an admin can revoke a station's pairing at any time, immediately
    # invalidating its JWT"). Forces any live Action Cable connection for that agent to drop right
    # now, not just on its next reconnect attempt — ActionCable's own remote-disconnect API,
    # matched against the same `current_print_agent` identity ApplicationCable::Connection sets.
    #
    # `current_user: nil` alongside it — confirmed live as a real bug, not a style choice:
    # RemoteConnections#where raises InvalidIdentifiersError unless the hash's keys cover *every*
    # identifier declared on the Connection class (`identified_by :current_user, :current_print_agent`),
    # not just the one being matched on — a browser/admin identity was never involved here, but
    # Action Cable still requires the key present (nil is the correct "don't care" value; a print
    # agent's own connection never sets current_user in the first place).
    def revoke
      authorize @print_station, :update?
      agent = @print_station.current_agent

      if agent
        agent.update!(revoked_at: Time.current)
        ActionCable.server.remote_connections.where(current_user: nil, current_print_agent: agent).disconnect
      end

      redirect_to admin_event_print_stations_path(@event), notice: "#{@print_station.name}'s pairing revoked."
    end

    # requirement.md §5.5.1: "auto-print on/off toggle per event," plus which station a manual
    # Print click/check-in targets when nothing more specific is picked. A couple of Event fields
    # edited alongside the station list itself, not a separate settings page.
    #
    # update_columns (not update!) deliberately — same reasoning TicketCategory#sync_counts!'s own
    # comment already gives for the identical shape: these two columns are independent of the rest
    # of Event's business validations, so there's no reason to re-run them for a write that only
    # ever touches these already-valid settings fields. Confirmed live as a real bug, not a
    # hypothetical: an event created before the Phase 15 quotation gate existed (no `quotation_id`)
    # 500'd on every save here with "Quotation must exist" — completely unrelated to print
    # settings, which is exactly the class of failure update_columns exists to avoid. Values are
    # still correctly type-cast (checkbox "1"/"0" -> boolean, blank string -> nil for the FK) —
    # confirmed live — since that casting happens in the SQL layer, not in validations.
    def update_settings
      authorize @event, :update?
      @event.update_columns(event_print_settings_params.to_h.symbolize_keys)
      redirect_to admin_event_print_stations_path(@event), notice: "Print settings saved."
    end

    private

    def set_print_station
      @print_station = @event.print_stations.find(params[:id])
    end

    def print_station_params
      params.require(:print_station).permit(:name, :printer_name)
    end

    def event_print_settings_params
      params.require(:event).permit(:auto_print_enabled, :default_print_station_id)
    end
  end
end
