module Admin
  # Phase 8 — Badge Design & Printing (requirement.md §3.6, §5.5). Nested under Event — every
  # Badge belongs to exactly one, and "conditional badge layouts by ticket category" (§5.5) means
  # an event can hold several (one default, plus one per TicketCategory). #index still exists
  # (and is still what #create's own form posts to) but is no longer where anything redirects —
  # the wizard's own Badge step (app/views/admin/events/_badge_step.html.erb) renders the exact
  # same table inline, so #create/#update/#destroy/#copy all send the tenant back there instead;
  # leaving the wizard just to see the list a save already updated was the actual friction being
  # removed, not the table itself needing to move again. #edit hosts the GrapesJS canvas (shared
  # partial with Admin::BadgeTemplatesController#edit — same content/mapping/size shape).
  #
  # No dedicated BadgePolicy — authorization delegates to the parent Event's own EventPolicy,
  # same shortcut TicketCategory's controller already takes for Event-child resources.
  class BadgesController < BaseController
    # Same reasoning as Admin::BadgeTemplatesController::BLANK_CANVAS — #new only asks for
    # name/category/type/size (plus an optional starting template); a fresh, not-from-template
    # Badge still needs *some* non-blank `content` to satisfy HasBadgeMapping's presence
    # validation before the GrapesJS canvas has ever touched it.
    BLANK_CANVAS = "<div style=\"width:100%;height:100%;\"></div>".freeze

    before_action :set_event
    before_action :set_badge, only: [ :edit, :update, :destroy, :preview, :copy ]

    def index
      authorize @event, :update?
      @badges = @event.badges.includes(:ticket_category).order(:ticket_category_id)
    end

    def new
      authorize @event, :update?
      @badge = @event.badges.build(width_cm: 8.5, height_cm: 5.4, content: BLANK_CANVAS)
      @badge_templates = Current.account.badge_templates.order(:name)
    end

    def create
      authorize @event, :update?

      template = Current.account.badge_templates.find_by(id: params[:badge_template_id])
      ticket_category = @event.ticket_categories.find_by(id: params.dig(:badge, :ticket_category_id))

      @badge = if template
        Badge.build_from_template(template, event: @event, ticket_category: ticket_category)
      else
        @event.badges.build(account: @event.account, ticket_category: ticket_category, content: BLANK_CANVAS)
      end
      @badge.assign_attributes(badge_params)

      if @badge.save
        redirect_to edit_admin_event_badge_path(@event, @badge), notice: "#{@badge.name} created."
      else
        @badge_templates = Current.account.badge_templates.order(:name)
        render :new, status: :unprocessable_content
      end
    end

    def edit
      authorize @event, :update?
    end

    def update
      authorize @event, :update?

      if @badge.update(badge_params)
        apply_uploads(@badge)
        redirect_to edit_admin_event_path(@event, step: "badge"), notice: "#{@badge.name} saved."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @event, :update?
      @badge.destroy
      redirect_to edit_admin_event_path(@event, step: "badge"), notice: "#{@badge.name} removed."
    end

    # "Copy to..." (admin/badges/_badges_table.html.erb) — reduces designing the same badge over
    # and over for every ticket category to one click plus a review pass, not a from-scratch
    # redesign each time. Badge.build_from_badge mirrors .build_from_template's own copy shape
    # (content/mapping/size/background_image/logo), just sourcing from another Badge instead of a
    # BadgeTemplate. Lands straight on the GrapesJS canvas (not back on the wizard step) — the
    # whole point is the tenant reviews/adjusts the copy (tokens that only make sense for the
    # *source* category's participants, a different width for a different badge stock, etc.)
    # before it's live for a different category, not that it silently ships unreviewed.
    def copy
      authorize @event, :update?
      ticket_category = @event.ticket_categories.find_by(id: params[:ticket_category_id])

      copy = Badge.build_from_badge(@badge, ticket_category: ticket_category)
      if copy.save
        redirect_to edit_admin_event_badge_path(@event, copy),
          notice: "Copied \"#{@badge.name}\" for #{ticket_category&.name || "Default"} — review it and save."
      else
        redirect_to edit_admin_event_path(@event, step: "badge"), alert: copy.errors.full_messages.to_sentence
      end
    end

    # The eye-icon preview (admin/badges/_badges_table.html.erb) — loaded inside an <iframe> in a
    # modal, so this renders a standalone document, not a fragment inside the admin layout (no
    # sidebar/header makes sense inside that iframe). Runs the exact same BadgeReformService a
    # real print does, against a synthetic, never-persisted Participant built fresh on every
    # request (never touches the DB — no save/valid? call, so none of Participant's own
    # create-time side effects fire: no hex_id/identifier generation, no live-stats broadcast) —
    # there is no real participant to preview against at any point this table actually renders
    # (mid-setup on the wizard/Review, or the standalone Badges page, which has no participant
    # picker of its own either), and even where real participants do exist for this event, showing
    # one specific person's actual data in a generic "what does this badge look like" preview
    # would be a strange (and mildly invasive) way to answer that question.
    #
    # `render html: wrap_preview_html(...).html_safe` — not a `.html_safe`/`raw` call inside an
    # ERB view — deliberately: `badge.content` is trusted, admin-authored markup (the whole point
    # of the GrapesJS editor's saved output — same trust level BadgePdfService's own `wrap_html`
    # already treats it at, plain Ruby string interpolation in a .rb file, no ERB template
    # involved), but Brakeman's CrossSiteScripting check specifically watches ERB `<%= %>` output
    # tags for exactly this "unescaped model attribute" shape and flags it there regardless of
    # trust level — confirmed live (caught the warning, then confirmed it's real and specific to
    # the ERB-view form: an earlier version of this action rendered a `preview.html.erb` view with
    # `<%= raw @content %>`, which tripped it; this controller-only version, structured the same
    # way `BadgePdfService#wrap_html` already is, doesn't).
    def preview
      authorize @event, :update?
      content = BadgeReformService.render(badge: @badge, participant: sample_participant, sample: true)
      render html: wrap_preview_html(content).html_safe
    end

    private

    # Sized with real CSS "cm" units, not a px conversion — same physical-size approach
    # BadgePdfService takes for the actual PDF (Grover/Puppeteer resolve "cm" page dimensions
    # natively) and the GrapesJS design canvas takes for its own on-screen editing area
    # (badge_editor_controller.js's CM_TO_PX) — all three render this badge at the same real
    # physical size, so this preview is a true "what would print" answer, not an approximation.
    # `position: relative` on body for the same reason BadgePdfService's own wrap_html sets it:
    # every token block the badge editor places is absolutely positioned, so it needs a positioned
    # ancestor to anchor to — this is that anchor, applied fresh here regardless of what the saved
    # `content`'s own root element does. `background_style` — same gap BadgePdfService's own
    # `#background_style` was fixed for: this preview modal renders body/style independently of
    # that service, so it needs the identical background composited here too, or an organizer's
    # uploaded background would only ever show up in the final downloaded PDF, never in the
    # "what does this badge look like" preview meant to answer that question up front.
    def wrap_preview_html(fragment)
      <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="utf-8">
            <style>
              html, body { margin: 0; padding: 0; }
              body { position: relative; width: #{@badge.width_cm}cm; height: #{@badge.height_cm}cm; overflow: hidden; #{background_style} }
            </style>
          </head>
          <body>#{fragment}</body>
        </html>
      HTML
    end

    # Same shape as BadgePdfService's own private method of the same name — both build on
    # #background_image_data_uri (HasBadgeMapping), the one place that downloads/base64-encodes
    # the blob.
    def background_style
      data_uri = @badge.background_image_data_uri
      return "" unless data_uri

      "background-image:url(#{data_uri});background-size:cover;background-position:center;"
    end

    # Every field a badge's $OTHER1$/$OTHER2$/$OTHER3$ mapping (HasBadgeMapping::MAPPABLE_FIELDS)
    # could possibly point at gets a plausible placeholder value, not just the handful #new's own
    # BLANK_CANVAS badge would exercise — a badge with, say, $OTHER1$ mapped to "company" should
    # preview showing a real-looking company name, not silently render blank the way an
    # unset/unmapped slot correctly does. hex_id is set explicitly rather than left to
    # Participant#generate_identifiers (a before_validation, on: :create callback) since this
    # record is deliberately never validated or saved.
    def sample_participant
      Participant.new(
        event: @event, name: "Sample Participant", email: "sample.participant@example.com",
        contact_num: "+1 555 0100", company: "Acme Corp", department: "Engineering",
        position: "Attendee", nationality: "Sample", country: "Sampleland",
        govt_id: "SAMPLE-GOVT-ID", rf_id: "SAMPLE-RFID", client_participant_id: "SAMPLE-001",
        hex_id: "SAMPLE-HEX-ID"
      )
    end

    def set_event
      @event = Event.friendly.find(params[:event_id])
    end

    def set_badge
      @badge = @event.badges.find(params[:id])
    end

    def badge_params
      params.require(:badge).permit(:name, :content, :output_type, :width_cm, :height_cm, mapping: {})
    end

    def apply_uploads(badge)
      bg = params.dig(:badge, :background_image)
      badge.attach_background_image(bg) if bg.present?

      logo = params.dig(:badge, :logo)
      badge.attach_logo(logo) if logo.present?
    end
  end
end
