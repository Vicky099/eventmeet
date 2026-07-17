# Phase 7 — Participant Lifecycle (requirement.md §3.11, §5.4): "Bulk XLSX import (async Sidekiq
# job) with the same fuzzy-dedupe matching, progress-pollable." Reuses Participant.duplicate_match
# (the same chain the manual-entry form's own validation runs) so an imported row can never create
# a duplicate the admin form would have rejected — dedupe logic lives in exactly one place.
#
# Column headers are matched case-insensitively against HEADER_MAP; unrecognized columns are
# ignored rather than erroring the whole file, so a template with extra notes columns still
# imports. Custom fields (a ticket_category's resolved RegistrationForm#custom_fields, Phase 7.5)
# aren't populated by import — the fixed identifier/contact columns below are the whole surface
# for this phase.
class ParticipantImportJob < ApplicationJob
  queue_as :default

  # jsonb row_errors is a summary for a human to read, not a full audit log — capped so one
  # catastrophically bad file (thousands of malformed rows) doesn't write an unbounded column.
  ROW_ERROR_CAP = 50

  HEADER_MAP = {
    "first name" => :first_name,
    "first_name" => :first_name,
    "last name" => :last_name,
    "last_name" => :last_name,
    "title" => :title,
    # Legacy single-column templates predating the first/last name split — #split_legacy_name
    # below best-effort-splits this into first_name/last_name when the file has no separate
    # First Name/Last Name columns of its own.
    "name" => :name,
    "email" => :email,
    "contact number" => :contact_num,
    "contact_num" => :contact_num,
    "phone" => :contact_num,
    "company" => :company,
    "department" => :department,
    "position" => :position,
    "nationality" => :nationality,
    "country" => :country,
    "govt id" => :govt_id,
    "govt_id" => :govt_id,
    "government id" => :govt_id,
    "rf id" => :rf_id,
    "rf_id" => :rf_id,
    "rfid" => :rf_id,
    # requirement.md revisit: "ticket category column should be there ... it should be name of
    # ticket category. find category by name and then attach that category to participant." The
    # cell holds a category *name* string, not the real ticket_category_id column Participant
    # actually has — kept under its own attrs key (never passed straight into
    # event.participants.build) so #import_row's own #resolve_ticket_category can look it up
    # against this event's own categories first.
    "ticket category" => :ticket_category_name,
    "ticket_category" => :ticket_category_name
  }.freeze

  # requirement.md revisit: "Import will provide the sample CSV import download option and then
  # in that format admin will enter the user data." One pretty label + one example value per
  # recognized column — the *canonical* variant only (e.g. "Contact Number", not also its
  # "phone"/"contact_num" HEADER_MAP aliases, which exist for reading someone else's export back
  # in, not for what this app's own template should lead with). Admin::ImportFilesController
  # #sample builds the actual downloadable workbook straight from this, so the template and
  # #row_attributes' own recognized-header set can never drift apart. "Visitor" (the Ticket
  # Category example) is a plausible, generic placeholder like every other example value here,
  # not this event's own real category name — #resolve_ticket_category matches by exact name
  # (case-insensitive) against whichever categories *this* event actually has, so the admin fills
  # in a real one of their own before uploading, same as every other example cell.
  SAMPLE_COLUMNS = [
    [ "Title", "Mr." ],
    [ "First Name", "John" ],
    [ "Last Name", "Doe" ],
    [ "Email", "john.doe@example.com" ],
    [ "Contact Number", "+1 555 0100" ],
    [ "Company", "Acme Corp" ],
    [ "Department", "Engineering" ],
    [ "Position", "Manager" ],
    [ "Nationality", "American" ],
    [ "Country", "United States" ],
    [ "Govt ID", "GOVT-12345" ],
    [ "RF ID", "RF-98765" ],
    [ "Ticket Category", "Visitor" ]
  ].freeze

  def perform(import_file_id)
    import_file = ImportFile.unscoped_across_tenants { ImportFile.find(import_file_id) }
    Current.account = import_file.account
    import_file.update!(status: :processing)

    process(import_file)
  rescue StandardError => e
    # A bad/unreadable file (wrong format, corrupted upload) — distinct from "some rows had
    # errors" (that's a normal completed outcome, tracked per-row below).
    Rails.logger.error("[ParticipantImportJob] failed for ImportFile #{import_file_id}: #{e.message}")
    import_file&.update!(status: :failed, row_errors: [ { row: 0, message: e.message } ])
  end

  private

  def process(import_file)
    event = import_file.event
    created = 0
    duplicates = 0
    errors = 0
    row_errors = []
    # Precomputed once per import, not a fresh query per row — the same "bulk-precompute before
    # the loop" shape this codebase already uses elsewhere (e.g. Admin::ScanEventsController
    # #ticket_category_stats). Keyed by downcased name so #ticket_category_id_for's own lookup is
    # case-insensitive, matching HEADER_MAP's own case-insensitive header matching.
    categories_by_name = event.ticket_categories.index_by { |category| category.name.downcase }

    # Not `import_file.file.blob.open` — see CloudinaryRawFile's own comment: the standard
    # ActiveStorage read path (Blob#open/#download, both used under the hood there) is broken for
    # "raw" resources on this app's Cloudinary service, a real gem bug first caught as a 404 on
    # Admin::ExportFilesController's own download link and confirmed here to be the exact same
    # root cause, just surfacing as an ActiveStorage::IntegrityError on the read side instead.
    Tempfile.create([ "import", ".xlsx" ]) do |tempfile|
      tempfile.binmode
      tempfile.write(CloudinaryRawFile.download(import_file.file.blob))
      tempfile.rewind

      spreadsheet = Roo::Spreadsheet.open(tempfile.path, extension: :xlsx)
      headers = spreadsheet.row(1).map { |header| header.to_s.strip.downcase }
      last_row = spreadsheet.last_row
      total_rows = [ last_row - 1, 0 ].max
      import_file.update!(total_rows: total_rows)

      (2..last_row).each do |row_number|
        attrs = row_attributes(headers, spreadsheet.row(row_number))
        next if attrs.values.all?(&:blank?)

        outcome = import_row(event: event, attrs: attrs, categories_by_name: categories_by_name)
        case outcome
        when :created then created += 1
        when :duplicate then duplicates += 1
        else
          errors += 1
          row_errors << { row: row_number, message: outcome } if row_errors.size < ROW_ERROR_CAP
        end

        processed = row_number - 1
        import_file.update!(processed_rows: processed) if processed % 10 == 0 || row_number == last_row
      end
    end

    import_file.update!(
      status: :completed, processed_rows: import_file.total_rows,
      created_count: created, duplicate_count: duplicates, error_count: errors, row_errors: row_errors
    )
  end

  def row_attributes(headers, row_values)
    attrs = {}
    headers.each_with_index do |header, index|
      attribute = HEADER_MAP[header]
      next unless attribute

      attrs[attribute] = row_values[index].to_s.strip
    end
    attrs
  end

  # Returns :created, :duplicate, or a String error message — deliberately not raising, so one
  # bad row doesn't abort the rest of the file.
  def import_row(event:, attrs:, categories_by_name:)
    attrs = split_legacy_name(attrs)

    category, ticket_category_error = ticket_category_for(attrs[:ticket_category_name], categories_by_name)
    return ticket_category_error if ticket_category_error

    # requirement.md revisit: "we should have privilege to set the uniqueness for participant
    # data ... same parameter should be used while importing the data." The category has to be
    # resolved first (above) so its own RegistrationForm#uniqueness_fields — the exact same config
    # Participant#not_a_duplicate reads for the manual-entry form, via TicketCategory
    # #effective_uniqueness_fields — is what this dedupe check uses too; a row with no recognized
    # category falls back to duplicate_match's own default (every field), same as manual entry
    # with no ticket_category selected.
    match, = Participant.duplicate_match(
      event: event, govt_id: attrs[:govt_id], email: attrs[:email], name: full_name(attrs), contact_num: attrs[:contact_num],
      uniqueness_fields: category&.effective_uniqueness_fields
    )
    return :duplicate if match

    participant = event.participants.build(
      attrs.except(:name, :ticket_category_name).merge(
        source: :upload, status: event.default_participant_status, ticket_category_id: category&.id
      )
    )
    return :created if participant.save

    participant.errors.full_messages.to_sentence
  end

  # requirement.md revisit: "ticket category column should be there in sample excel sheet. and it
  # should be name of ticket category. find category by name and then attach that category to
  # participant." A name that doesn't match any of *this* event's own categories is a row error,
  # not silently dropped — a typo in the sheet shouldn't quietly leave a participant uncategorized
  # without the admin ever finding out. An empty cell is fine (no category, same as before this
  # column existed at all). Returns the category itself (not just its id) — #import_row's own
  # duplicate check needs the category to read its configured uniqueness_fields from.
  def ticket_category_for(name, categories_by_name)
    return [ nil, nil ] if name.blank?

    category = categories_by_name[name.downcase]
    return [ nil, "Ticket category '#{name}' not found" ] unless category

    [ category, nil ]
  end

  # Participant#derive_full_name (first_name/last_name are now the primary captured fields) would
  # otherwise silently wipe out a legacy single "Name" column's value — best-effort split on the
  # first space, same as most bulk-import tools handle exactly this migration. A no-op once a file
  # supplies real First Name/Last Name columns of its own.
  def split_legacy_name(attrs)
    return attrs if attrs[:first_name].present? || attrs[:name].blank?

    first, last = attrs[:name].to_s.strip.split(" ", 2)
    attrs.merge(first_name: first, last_name: last)
  end

  def full_name(attrs)
    [ attrs[:first_name], attrs[:last_name] ].compact_blank.join(" ").presence || attrs[:name]
  end
end
