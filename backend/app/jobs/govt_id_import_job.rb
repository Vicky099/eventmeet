# requirement.md revisit: "If we have govt id then we will upload that list this will be stored
# in database somewhere ... in upload we should have a separate sample xlsx file to upload the
# govtID." Same bulk-XLSX-into-a-progress-pollable-job shape as ParticipantImportJob (Phase 7),
# for a single-column file of raw government ID values instead of full participant rows. Once the
# batch is in, immediately backfills any of this event's existing participants who don't have a
# govt_id yet (GovtId.backfill_event! — requirement.md revisit: "while uploading the govtID it
# should automatically assign to the participant") — the other direction, brand-new participants
# claiming a pool id at the moment they register, is Participant's own
# after_create_commit :sync_govt_id_with_pool! and needs no help from this job at all.
class GovtIdImportJob < ApplicationJob
  queue_as :default

  HEADER_MAP = {
    "govt id" => :value,
    "govt_id" => :value,
    "government id" => :value,
    "government_id" => :value
  }.freeze

  SAMPLE_COLUMNS = [
    [ "Govt ID", "GOVT-12345" ]
  ].freeze

  def perform(govt_id_import_file_id)
    import_file = GovtIdImportFile.unscoped_across_tenants { GovtIdImportFile.find(govt_id_import_file_id) }
    Current.account = import_file.account
    import_file.update!(status: :processing)

    process(import_file)
  rescue StandardError => e
    Rails.logger.error("[GovtIdImportJob] failed for GovtIdImportFile #{govt_id_import_file_id}: #{e.message}")
    import_file&.update!(status: :failed, row_errors: [ { row: 0, message: e.message } ])
  end

  private

  def process(import_file)
    event = import_file.event
    created = 0
    duplicates = 0

    # CloudinaryRawFile.download, not blob.open/blob.download directly — same real `cloudinary`
    # gem "raw" resource bug ParticipantImportJob's own comment documents; identical fix, reused
    # as-is rather than duplicated.
    Tempfile.create([ "govt_id_import", ".xlsx" ]) do |tempfile|
      tempfile.binmode
      tempfile.write(CloudinaryRawFile.download(import_file.file.blob))
      tempfile.rewind

      spreadsheet = Roo::Spreadsheet.open(tempfile.path, extension: :xlsx)
      headers = spreadsheet.row(1).map { |header| header.to_s.strip.downcase }
      # A single-column template is much easier to upload the *wrong* file for (the wrong
      # spreadsheet entirely, or the participant import template by mistake) than an 11-column
      # one — worth failing loudly with a clear reason instead of silently "completing" having
      # imported nothing at all.
      raise "No recognized \"Govt ID\" column found in the uploaded file" if headers.none? { |header| HEADER_MAP.key?(header) }

      last_row = spreadsheet.last_row
      total_rows = [ last_row - 1, 0 ].max
      import_file.update!(total_rows: total_rows)

      (2..last_row).each do |row_number|
        attrs = row_attributes(headers, spreadsheet.row(row_number))
        next if attrs.values.all?(&:blank?)

        if import_row(event: event, value: attrs[:value].to_s.strip)
          created += 1
        else
          duplicates += 1
        end

        processed = row_number - 1
        import_file.update!(processed_rows: processed) if processed % 10 == 0 || row_number == last_row
      end
    end

    # requirement.md revisit: "while uploading the govtID it should automatically assign to the
    # participant." Runs once per import (not per row) — cheaper, and equivalent either way since
    # GovtId.assign_to! only ever consumes one pool row per participant regardless of how many are
    # newly available.
    GovtId.backfill_event!(event)

    import_file.update!(
      status: :completed, processed_rows: import_file.total_rows, created_count: created, duplicate_count: duplicates
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

  # true (created) or false (duplicate — already in this event's pool) — never a String error
  # message, unlike ParticipantImportJob#import_row's own version: the only way GovtId#save can
  # fail here is its own uniqueness validation (a fully-blank row was already skipped by #process
  # before this is ever called), so there's no other failure mode worth a per-row message for.
  def import_row(event:, value:)
    event.govt_ids.build(value: value).save
  end
end
