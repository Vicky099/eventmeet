# Phase 7 — Participant Lifecycle (requirement.md §5.4 new item): "organizer-defined fields
# (text/select/checkbox/file) stored per event, rendered dynamically on the admin manual-entry
# form." Rescoped in Phase 7.5 (requirement.md §5.4/§5.14 v12) from `belongs_to :event` to
# `belongs_to :registration_form` — one set of custom fields per TicketCategory's own form (or
# per event default/shared form), not one list for the whole event. Managed as nested attributes
# on RegistrationForm (see RegistrationForm#custom_fields), same batch-build-then-save-on-Next
# shape Phase 6's TicketCategory established.
class CustomField < ApplicationRecord
  include TenantScoped

  belongs_to :registration_form

  # :dropdown, not :select — an enum value named "select" would generate a `select` class
  # method, colliding with ActiveRecord::Base's own query method of the same name (Rails raises
  # on boot over exactly this). Still labeled "Select" to the organizer (CustomField.field_types
  # humanizes fine either way); only the Ruby-side symbol differs from the requirement doc's wording.
  enum :field_type, { text: 0, dropdown: 1, checkbox: 2, file: 3 }

  validates :label, presence: true
  validates :options, presence: true, if: :dropdown?

  # Newline-separated choices from the builder's textarea, parsed into a real array — only
  # meaningful for field_type: dropdown, but harmless (empty) to call for any other type.
  def options_list
    options.to_s.lines.map(&:strip).reject(&:blank?)
  end
end
