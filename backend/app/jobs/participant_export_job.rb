# Phase 7 — Participant Lifecycle (requirement.md §3.11, §5.4), revisited: "bulk XLSX export...
# generated async and delivered via a signed cloud URL, with progress polling," now with a real
# field picker (Admin::ExportFilesController#new/#create, ParticipantExportFields) in front of it
# — ExportFile#fields is the exact ordered list of column keys this job builds the workbook from,
# chosen per-request rather than a single fixed column list every time. Attendance/session
# time-spent columns were explicitly stubbed here through Phase 7 (those tables didn't exist yet);
# Phase 9/11 backfilled them, and this is that backfill — #build_context below is what actually
# reads them now.
class ParticipantExportJob < ApplicationJob
  queue_as :default

  def perform(export_file_id)
    export_file = ExportFile.unscoped_across_tenants { ExportFile.find(export_file_id) }
    Current.account = export_file.account
    export_file.update!(status: :processing)

    attach_workbook(export_file)
    export_file.update!(status: :completed)
  rescue StandardError => e
    Rails.logger.error("[ParticipantExportJob] failed for ExportFile #{export_file_id}: #{e.message}")
    export_file&.update!(status: :failed)
  end

  private

  def attach_workbook(export_file)
    package = build_package(export_file)

    Tempfile.create([ "participants", ".xlsx" ]) do |tempfile|
      tempfile.binmode
      package.serialize(tempfile.path)
      tempfile.rewind
      export_file.attach_tenant_scoped(
        io: tempfile,
        filename: "participants-#{export_file.event.slug}-#{Date.current.iso8601}.xlsx",
        content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      )
    end
  end

  def build_package(export_file)
    event = export_file.event
    # Falls back to the same defaults the picker itself pre-checks — belt-and-suspenders for any
    # ExportFile row that predates this field, rather than shipping a header-only, empty workbook.
    fields = export_file.fields.presence || ParticipantExportFields.default_keys
    export_fields = ParticipantExportFields.new(event)
    context = build_context(event)

    Axlsx::Package.new.tap do |package|
      package.workbook.add_worksheet(name: "Participants") do |sheet|
        sheet.add_row fields.map { |key| export_fields.label_for(key) }
        event.participants.find_each do |participant|
          sheet.add_row fields.map { |key| field_value(key, participant, context) }
        end
      end
    end
  end

  # Every value below is read out of one of these four hashes (or a plain participant column) —
  # never a fresh query inside the per-participant loop. Bounded to this one event's own
  # attendance/scan history, the same "not worth a raw-SQL trade-off at this row count" call
  # Event#currently_in_venue_count's own comment already makes for the equivalent per-event
  # aggregate.
  def build_context(event)
    {
      event_time_by_participant: Attendance.where(event: event, from: :event).where.not(time_spent_seconds: nil)
        .group(:participant_id).sum(:time_spent_seconds),
      session_time_by_participant_and_session: Attendance.where(event: event, from: :session).where.not(time_spent_seconds: nil)
        .group(:participant_id, :session_id).sum(:time_spent_seconds),
      check_in_counts: event.scan_events.check_in.where(session_id: nil).group(:participant_id).count,
      # Same computation Event#currently_in_venue_count's own KPI tile already uses — reused
      # rather than a second copy of the same group_by/transform_values.
      latest_event_scan_by_participant: event.latest_event_level_scan_by_participant
    }
  end

  def field_value(key, participant, context)
    case key
    when "title" then participant.title
    when "first_name" then participant.first_name
    when "last_name" then participant.last_name
    when "email" then participant.email
    when "contact_num" then participant.contact_num
    when "company" then participant.company
    when "department" then participant.department
    when "position" then participant.position
    when "nationality" then participant.nationality
    when "country" then participant.country
    when "status" then participant.status.humanize
    when "source" then participant.source.humanize
    when "ticket_category" then participant.ticket_category&.name
    when "hex_id" then participant.hex_id
    when "client_participant_id" then participant.client_participant_id
    when "govt_id" then participant.govt_id
    when "rf_id" then participant.rf_id
    when "photo_attached" then participant.photo.attached? ? "Yes" : "No"
    when "document_attached" then participant.document.attached? ? "Yes" : "No"
    when "checked_in" then context[:check_in_counts][participant.id].to_i.positive? ? "Yes" : "No"
    when "currently_in_venue" then context[:latest_event_scan_by_participant][participant.id]&.check_in? ? "Yes" : "No"
    when "check_in_count" then context[:check_in_counts][participant.id] || 0
    when "total_time_in_event" then format_duration(context[:event_time_by_participant][participant.id])
    else dynamic_field_value(key, participant, context)
    end
  end

  def dynamic_field_value(key, participant, context)
    if key.start_with?("custom_field:")
      participant.custom_field_values[key.delete_prefix("custom_field:")]
    elsif key.start_with?("session_time:")
      session_id = key.delete_prefix("session_time:")
      format_duration(context[:session_time_by_participant_and_session][[ participant.id, session_id ]])
    end
  end

  def format_duration(seconds)
    return nil if seconds.nil?
    return "0m" if seconds < 60

    hours, remainder = seconds.to_i.divmod(3600)
    minutes = remainder / 60
    [ ("#{hours}h" if hours.positive?), "#{minutes}m" ].compact.join(" ")
  end
end
