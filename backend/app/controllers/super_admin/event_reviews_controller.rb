module SuperAdmin
  # Phase 5 — Event Approval Workflow (requirement.md §4.7 item 2, §5.2). Every action is already
  # gated to platform_staff by BaseController (same reasoning as AccountsController) — there's no
  # role variation within the Platform Console the way there is within a tenant's own Account, so
  # no separate Pundit policy. Cross-tenant by construction: PlatformRequestScoped (included via
  # BaseController) opens Event's TenantScoped default_scope to every account, not just one.
  class EventReviewsController < BaseController
    before_action :set_event, only: [ :show, :approve, :reject ]

    # Oldest-first (requirement.md §5.2: the 24h SLA is measured from submission, so the
    # longest-waiting item belongs at the top) — submitted_at, not created_at, so a
    # reject → edit → resubmit cycle's clock genuinely resets instead of the item looking
    # perpetually overdue from its original creation time.
    def index
      @events = Event.where(approval_status: :pending).order(submitted_at: :asc)
    end

    def show
    end

    # Doesn't publish the event — that's the tenant's own subsequent manual action, which
    # Admin::EventsController#publish only allows once @event.approved? (requirement.md §5.2
    # revisited: approve unlocks Publish, it doesn't perform it).
    def approve
      @event.approve!(by: current_platform_staff)
      redirect_to platform_event_reviews_path, notice: "#{@event.name} approved."
    end

    # Reason is required — checked here (not just the model's own validation) so a blank
    # submission re-renders the review page with an alert instead of `reject!` raising
    # ActiveRecord::RecordInvalid (same "controller pre-checks the business rule, model method is
    # a raw mutation" split as Admin::EventsController#publish/Event#publish!).
    def reject
      reason = params[:rejection_reason].to_s.strip
      if reason.blank?
        redirect_to platform_event_review_path(@event), alert: "A rejection reason is required."
        return
      end

      @event.reject!(reason: reason)
      EventMailer.rejected(@event).deliver_later
      redirect_to platform_event_reviews_path, notice: "#{@event.name} rejected — organizer notified by email."
    end

    private

    def set_event
      @event = Event.friendly.find(params[:id])
    end
  end
end
