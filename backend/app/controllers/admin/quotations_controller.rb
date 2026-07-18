module Admin
  # Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6, confirmed with the
  # user): "Tenant sends the request for the event -> Super Admin reverts with the price -> Tenant
  # reviews, negotiates (up to 3 times) or approves." Every event needs one of these, priced
  # individually — there are no plan tiers left. This is the tenant's own half of that negotiation
  # — kicking off a request (#new/#create, standalone from Admin::EventsController since no Event
  # can exist yet) and responding to whatever the Super Admin sends (#approve/#reject, from #show).
  #
  # No :edit/:update/:destroy — a Quotation is requested once and then only ever responded to, on
  # both sides of the negotiation (SuperAdmin::QuotationsController#send_amount is the mirror
  # action). Once `approved?`, the actual "use it" step happens on Admin::EventsController#new/
  # #create, not here.
  class QuotationsController < BaseController
    before_action :set_quotation, only: [ :show, :approve, :reject ]

    def index
      authorize Quotation
      # .includes(:event) — the index's own "Create Event" action (approved + not-yet-consumed
      # only) needs to know per-row whether a quotation's already been used, and this avoids an
      # N+1 doing it.
      @quotations = Current.account.quotations.includes(:event).order(created_at: :desc)
    end

    def new
      @quotation = Current.account.quotations.build
      authorize @quotation
    end

    def create
      @quotation = Current.account.quotations.build(quotation_params.merge(requested_by: current_user))
      authorize @quotation

      if @quotation.save
        redirect_to admin_quotations_path, notice: "Quotation requested for \"#{@quotation.event_name}\" — a Super Admin will send an amount soon."
      else
        render :new, status: :unprocessable_content
      end
    end

    def show
      authorize @quotation
      # Real query, not the `has_one :event` association — same "don't trust `quotation.event`"
      # reasoning as Event's own `quotation_must_be_approved_and_available` comment (Rails'
      # `inverse_of` auto-detection can read back a stale in-memory assignment instead of what's
      # actually persisted); a fresh lookup by foreign key is the only reliable read here too.
      @event = Event.find_by(quotation_id: @quotation.id)
    end

    def approve
      authorize @quotation, :update?
      @quotation.approve!(by: current_user)
      redirect_to new_admin_event_path(quotation_id: @quotation.id), notice: "Quotation approved — you can now create the event."
    end

    def reject
      authorize @quotation, :update?
      note = params[:rejection_note].to_s.strip

      if note.blank?
        redirect_to admin_quotation_path(@quotation), alert: "A note explaining the rejection is required."
        return
      end

      @quotation.reject!(note: note, by: current_user)
      status_message = @quotation.cancelled? ? "cancelled after 3 rounds of negotiation — start a fresh request if you still need this event." : "sent back — a Super Admin will send a revised amount."
      redirect_to admin_quotation_path(@quotation), notice: "Quotation #{status_message}"
    end

    private

    def set_quotation
      @quotation = Current.account.quotations.find(params[:id])
    end

    # Confirmed with the user: the Super Admin was pricing quotations blind — these are what's
    # actually collected on the request form now (Quotation's own model comment has the full
    # "why").
    def quotation_params
      params.require(:quotation).permit(
        :event_name, :expected_participant_count, :invite_via_email, :invite_via_whatsapp,
        :support_requested, :additional_notes
      )
    end
  end
end
