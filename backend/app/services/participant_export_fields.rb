# requirement.md revisit: "Export sidebar button will provide a UI where admin can select the
# fields which he wants to export from the participant ... total time spent in session, in which
# session how much time and all." The single source of truth for every exportable field — both
# admin/export_files/_new.html.erb (the picker) and ParticipantExportJob (the actual workbook
# build) key off the exact same #groups list, so a field can never appear as a checkbox that the
# job doesn't know how to fill, or vice versa. Session/custom-field entries are dynamic (depend on
# this event's own sessions/registration forms), everything else is a fixed list — #groups mixes
# both under one shape so the view never needs to know which is which.
class ParticipantExportFields
  # Deliberately excludes photo/document as raw content (a spreadsheet cell isn't a sensible place
  # for either) but keeps an attached?/not boolean for each — genuinely useful to an organizer
  # auditing "did everyone actually get their photo captured," the file itself is a click away on
  # the participant's own edit page.
  STANDARD_FIELDS = [
    { key: "title", label: "Title" },
    { key: "first_name", label: "First Name" },
    { key: "last_name", label: "Last Name" },
    { key: "email", label: "Email" },
    { key: "contact_num", label: "Contact Number" },
    { key: "company", label: "Company" },
    { key: "department", label: "Department" },
    { key: "position", label: "Position" },
    { key: "nationality", label: "Nationality" },
    { key: "country", label: "Country" },
    { key: "status", label: "Status" },
    { key: "source", label: "Source" },
    { key: "ticket_category", label: "Ticket Category" },
    # requirement.md revisit: "Hex ID will be ID in all places on UI" — matches admin/participants
    # /index.html.erb's own "ID" column header for this exact value.
    { key: "hex_id", label: "ID" },
    { key: "client_participant_id", label: "Client Participant ID" },
    { key: "govt_id", label: "Govt ID" },
    { key: "rf_id", label: "RF ID" },
    { key: "photo_attached", label: "Photo Attached" },
    { key: "document_attached", label: "Document Attached" }
  ].freeze

  # Event-level only (session_id: nil) — matches the same scope Event#checked_in_participant_count
  # / #currently_in_venue_count already use for the dashboards' own KPI tiles; per-session presence
  # is what the dynamic "Time in: <session>" columns below are for instead.
  ATTENDANCE_FIELDS = [
    { key: "checked_in", label: "Checked In" },
    { key: "currently_in_venue", label: "Currently In Venue" },
    { key: "check_in_count", label: "Check-in Count" },
    { key: "total_time_in_event", label: "Total Time in Event" }
  ].freeze

  DEFAULT_KEYS = %w[first_name last_name email contact_num status ticket_category].freeze

  def self.groups(event) = new(event).groups
  def self.label_for(event, key) = new(event).label_for(key)
  def self.default_keys = DEFAULT_KEYS

  def initialize(event)
    @event = event
  end

  def groups
    [
      { name: "Participant Details", fields: STANDARD_FIELDS },
      { name: "Custom Fields", fields: custom_field_defs },
      { name: "Attendance & Time Analytics", fields: ATTENDANCE_FIELDS + session_time_field_defs }
    ].reject { |group| group[:fields].empty? }
  end

  def keys
    groups.flat_map { |group| group[:fields].map { |field| field[:key] } }
  end

  # ParticipantExportJob's own header row — falls back to the raw key for anything not in this
  # event's *current* field list (a custom field or session deleted after an old ExportFile's own
  # #fields was already persisted) rather than raising, since a stale header beats a failed job.
  def label_for(key)
    groups.flat_map { |group| group[:fields] }.find { |field| field[:key] == key }&.fetch(:label) || key
  end

  private

  attr_reader :event

  def custom_field_defs
    CustomField.where(registration_form: event.registration_forms).order(:label).map do |field|
      { key: "custom_field:#{field.id}", label: field.label }
    end
  end

  def session_time_field_defs
    event.sessions.order(:starts_at).map do |session|
      { key: "session_time:#{session.id}", label: "Time in: #{session.name}" }
    end
  end
end
