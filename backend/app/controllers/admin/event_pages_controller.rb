module Admin
  # Phase 25.5 — Public Event Site (doc/public_event_site_options.md, Confirmed decisions #2-#4).
  # One EventPage per Event (has_one) — find-or-initialize on #edit, same "edit is the workspace,
  # no separate create step" shape Admin::EmailTemplatesController already takes. Stored/rendered
  # verbatim by the public site — deliberately no sanitization here (Confirmed decision #2: this
  # event's own admin owns the risk for their own page/visitors, not a cross-tenant concern).
  # Saving never touches the event's own status/published_at (Confirmed decision #4) — no
  # EventPolicy#update? "content changed" side effect the way Event::CONTENT_ATTRIBUTES fields get.
  class EventPagesController < BaseController
    include EventScoped

    before_action :set_event_page

    def edit
      authorize @event, :update?
    end

    def update
      authorize @event, :update?

      if @event_page.update(event_page_params)
        redirect_to edit_admin_event_event_page_path(@event), notice: "Event page saved."
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def set_event_page
      @event_page = @event.event_page || @event.build_event_page
    end

    def event_page_params
      params.require(:event_page).permit(:html)
    end
  end
end
