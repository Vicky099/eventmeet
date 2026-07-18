module Admin
  # Phase 13 — Communications, revisited (requirement.md §3.10, §5.10): "customized email template
  # for participant registration ... store that email template with placeholder." Nested under
  # Event (confirmed with user: per-event, not shared across a tenant's events) — same shape
  # Admin::BadgesController takes, one row per EmailTemplate::kind per event (see config/routes.rb's
  # `param: :kind`, letting edit/update/preview work even before a row exists yet, with no separate
  # "create" step).
  #
  # No dedicated EmailTemplatePolicy — authorization delegates to the parent Event's own
  # EventPolicy, same shortcut Admin::BadgesController/TicketCategory's controller already take for
  # Event-child resources.
  class EmailTemplatesController < BaseController
    before_action :set_event
    before_action :set_email_template, only: [ :edit, :update, :destroy, :preview ]

    def index
      authorize @event, :update?
      @email_templates = EmailTemplate.kinds.keys.map do |kind|
        @event.email_templates.find_by(kind: kind) || @event.email_templates.build(kind: kind)
      end
      # "Quick Email Send" modal's own <select> — a list of *kind strings*, not EmailTemplate rows,
      # since :participant_registration belongs here even with no row (EmailTemplate::
      # ALWAYS_SENDABLE_KINDS — it always has real content to broadcast, the built-in confirmation
      # view). Every other kind still needs a configured, active row first — see that constant's
      # own comment for why. Confirmed with the user: :participant_registration is selectable here
      # to deliberately re-blast it to every participant, not just resend it one at a time
      # (Admin::ParticipantsController#resend).
      @sendable_kinds = EmailTemplate.kinds.keys.select { |kind| sendable_kind?(kind) }
      @recipient_count = @event.participants.where.not(email: [ nil, "" ]).count
    end

    def edit
      authorize @event, :update?
      prefill_defaults(@email_template) unless @email_template.persisted?
    end

    def update
      authorize @event, :update?

      if @email_template.update(email_template_params)
        redirect_to admin_event_email_templates_path(@event), notice: "#{@email_template.label} saved."
      else
        render :edit, status: :unprocessable_content
      end
    end

    # "Reset to Default" — removes the customization entirely rather than merely deactivating it;
    # ParticipantMailer#confirmation falls back to the built-in view the moment no row exists.
    def destroy
      authorize @event, :update?
      @email_template.destroy if @email_template.persisted?
      redirect_to admin_event_email_templates_path(@event), notice: "#{@email_template.label} reset to the default template."
    end

    # Renders unsaved editor content (not what's persisted) against sample data — the same
    # rendering path the real send uses (EmailTemplateRenderer), so this is a true preview, not an
    # approximation. JSON in, JSON out: the Stimulus controller driving the editor's preview pane
    # posts the current textarea contents on every "Refresh Preview" click. `event: @event` is the
    # real, persisted event (not a synthetic one, unlike sample_participant below) — this preview
    # runs inside that event's own workspace, so $EVENT_NAME$/etc. show its actual details.
    def preview
      authorize @event, :update?

      rendered = EmailTemplateRenderer.render_email(
        subject: params[:subject].to_s, html_body: params[:html_body].to_s,
        participant: sample_participant, event: @event, account: Current.account
      )

      render json: rendered
    end

    # "Quick Email Send" modal's submit — enqueues QuickEmailSendJob rather than looping over
    # participants inline (see that job's own comment for why); this action just validates which
    # kind was picked and hands off. Takes `kind` as a plain form param (the modal's <select>), not
    # a URL segment/`set_email_template`, and passes it straight through — :participant_registration
    # may have no EmailTemplate row at all (ALWAYS_SENDABLE_KINDS), so this can't resolve a single
    # row up front the way edit/update/destroy/preview do; the job resolves per-kind on its own.
    def quick_send
      authorize @event, :update?

      if sendable_kind?(params[:kind])
        QuickEmailSendJob.perform_later(@event.id, params[:kind])
        recipient_count = @event.participants.where.not(email: [ nil, "" ]).count
        redirect_to admin_event_email_templates_path(@event),
          notice: "Queued \"#{EmailTemplate::KIND_LABELS.fetch(params[:kind])}\" to send to #{recipient_count} participant(s)."
      else
        redirect_to admin_event_email_templates_path(@event), alert: "Select a configured template to send."
      end
    end

    private

    def set_event
      @event = Event.friendly.find(params[:event_id])
    end

    # A kind is offered in "Quick Email Send" when it's either always-sendable (has real,
    # built-in-view content even with no row — EmailTemplate::ALWAYS_SENDABLE_KINDS) or has an
    # actual configured, active EmailTemplate row for this event.
    def sendable_kind?(kind)
      EmailTemplate.kinds.key?(kind) &&
        (EmailTemplate::ALWAYS_SENDABLE_KINDS.include?(kind) || @event.email_templates.exists?(kind: kind, active: true))
    end

    def set_email_template
      raise ActiveRecord::RecordNotFound unless EmailTemplate.kinds.key?(params[:kind])

      @email_template = @event.email_templates.find_or_initialize_by(kind: params[:kind])
    end

    def email_template_params
      params.require(:email_template).permit(:subject, :html_body, :active)
    end

    def prefill_defaults(email_template)
      defaults = EmailTemplate::DEFAULT_TEMPLATES[email_template.kind]
      return if defaults.blank?

      email_template.subject ||= defaults[:subject]
      email_template.html_body = defaults[:html_body] if email_template.html_body.blank?
    end

    # Same shape as Admin::BadgesController#sample_participant — an unsaved, in-memory record so
    # the preview never depends on (or risks emailing) a real participant.
    def sample_participant
      Participant.new(
        event: @event, name: "Sample Participant", first_name: "Sample", last_name: "Participant",
        email: "sample.participant@example.com", client_participant_id: "SAMPLE-001"
      )
    end
  end
end
