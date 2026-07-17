module Admin
  # Phase 7.5 — Dynamic Registration Form Builder (requirement.md §5.4/§5.14 v12). Standard
  # resourceful CRUD over standalone, named RegistrationForms — build one (name + catalog fields +
  # custom fields), then assign it to whichever of the event's TicketCategory rows should use it,
  # including all of them at once (#apply_to_all). No :show — same "edit is the workspace" shape
  # every other admin resource in this app already uses. EventPolicy#update? (owner/event_manager)
  # gates every action here the same way it gates editing the event itself — designing/assigning
  # registration forms is part of setting the event up, not a separate permission.
  class RegistrationFormsController < BaseController
    include EventScoped

    def index
      authorize @event, :update?
      @registration_forms = @event.registration_forms.order(:created_at)
      @unassigned_categories = @event.ticket_categories.where(registration_form_id: nil).order(:created_at)
    end

    def new
      authorize @event, :update?
      @registration_form = @event.registration_forms.build
      @ticket_categories = @event.ticket_categories.order(:created_at)
    end

    def create
      authorize @event, :update?
      @registration_form = @event.registration_forms.build(registration_form_params)

      if @registration_form.save
        assign_categories!
        redirect_to admin_event_registration_forms_path(@event), **save_flash("created")
      else
        @ticket_categories = @event.ticket_categories.order(:created_at)
        render :new, status: :unprocessable_content
      end
    end

    def edit
      authorize @event, :update?
      @registration_form = @event.registration_forms.find(params[:id])
      @ticket_categories = @event.ticket_categories.order(:created_at)
    end

    def update
      authorize @event, :update?
      @registration_form = @event.registration_forms.find(params[:id])

      if @registration_form.update(registration_form_params)
        assign_categories!
        redirect_to admin_event_registration_forms_path(@event), **save_flash("updated")
      else
        @ticket_categories = @event.ticket_categories.order(:created_at)
        render :edit, status: :unprocessable_content
      end
    end

    # Categories using this form (TicketCategory#registration_form_id) simply fall back to
    # RegistrationForm::BUILTIN_DEFAULT_CATALOG (dependent: :nullify on the model) — deleting a
    # form an organizer no longer wants doesn't touch the categories themselves.
    def destroy
      authorize @event, :update?
      registration_form = @event.registration_forms.find(params[:id])
      registration_form.destroy!
      redirect_to admin_event_registration_forms_path(@event), notice: "#{registration_form.name} removed."
    end

    private

    def registration_form_params
      permitted = params.require(:registration_form).permit(
        :name,
        custom_fields_attributes: [ :id, :label, :field_type, :options, :required, :position, :_destroy ]
      )
      # catalog_fields arrives as a "catalog_fields[]" array of checked field names (same shape
      # the old, now-retired Basic Info step's participant_fields catalog used), not a
      # hash-of-booleans param — an unchecked box (like an unchecked checkbox generally) submits
      # nothing at all for itself, so "selected" has to be checked against the fixed catalog
      # rather than trusted to arrive complete.
      selected = Array(params.dig(:registration_form, :catalog_fields))
      permitted[:catalog_fields] = Event::PARTICIPANT_FIELD_CATALOG.index_with { |field| selected.include?(field) }
      permitted[:catalog_field_positions] = catalog_field_positions_param
      # requirement.md revisit: "At least one uniqueness parameter should be set." Same
      # checked-array shape as catalog_fields above (an unchecked box submits nothing at all for
      # itself) — intersected against RegistrationForm::UNIQUENESS_FIELDS so a tampered request
      # can't smuggle in an unrecognized value (the model's own inclusion validation is the second,
      # independent layer of the same defense).
      permitted[:uniqueness_fields] = Array(params.dig(:registration_form, :uniqueness_fields)) & RegistrationForm::UNIQUENESS_FIELDS
      permitted
    end

    # catalog_field_positions arrives as a real hash-of-values param (one number input per field,
    # unlike catalog_fields' checked-or-absent array), so it's permitted directly rather than
    # normalized against a submitted array — still only ever the fixed catalog's own keys
    # (permit's hash-of-scalars form only allows what's listed). Blank/non-numeric input falls
    # back to that field's own natural catalog position rather than collapsing to 0, so leaving a
    # box empty doesn't silently pull that field to the very front.
    def catalog_field_positions_param
      raw = params.dig(:registration_form, :catalog_field_positions) || {}
      Event::PARTICIPANT_FIELD_CATALOG.each_with_index.to_h do |field, index|
        [ field, raw[field].presence&.to_i || index ]
      end
    end

    # "Apply to all" (params[:registration_form][:apply_to_all] == "1") assigns every one of the
    # event's ticket categories to this form, overriding whatever was individually checked —
    # exactly the confirmed requirement ("create one form and apply for all ticket category"), not
    # a separate persisted flag: a category added to the event later doesn't retroactively inherit
    # it, this is a one-time bulk assignment, same as checking every box by hand would be.
    # Explicit, not additive: a category previously assigned to this form but left unchecked here
    # is unassigned (falls back to BUILTIN_DEFAULT_CATALOG) — editing assignment always reflects
    # exactly what's currently checked, never "whatever was checked before, plus this."
    def assign_categories!
      category_ids =
        if params.dig(:registration_form, :apply_to_all) == "1"
          @event.ticket_categories.ids
        else
          Array(params.dig(:registration_form, :ticket_category_ids))
        end

      @event.ticket_categories.where(registration_form_id: @registration_form.id).where.not(id: category_ids)
        .update_all(registration_form_id: nil)
      @event.ticket_categories.where(id: category_ids).update_all(registration_form_id: @registration_form.id)
    end

    # A form left unassigned to every category is almost always a mistake, not a deliberate
    # choice — silently, every category just keeps using the built-in default fields instead, and
    # the index page's own indicator (a muted "not assigned" line, easy to miss) wasn't enough on
    # its own to catch it in practice (a real report: an organizer believed a form they'd just
    # configured was "assigned to all," and it wasn't). Surfaced here too, immediately on save,
    # not just passively on the next index visit.
    def save_flash(verb)
      flash = { notice: "#{@registration_form.name} #{verb}." }
      if @registration_form.ticket_categories.count.zero?
        flash[:alert] = "#{@registration_form.name} isn't assigned to any ticket category yet — " \
          "every category will keep using the built-in default fields until you assign it."
      end
      flash
    end
  end
end
