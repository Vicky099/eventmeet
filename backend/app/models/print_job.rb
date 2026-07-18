# Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1, §8). One row per print
# actually dispatched to a paired station — PrintTriggerService's own queue/status-tracking unit.
# Not written for the plain PDF-download fallback (no station paired/online) — that path stays
# the pre-existing on-demand-download behavior (Phase 8), only ever logging a `print` ScanEvent,
# same as before this phase existed.
class PrintJob < ApplicationRecord
  include TenantScoped

  belongs_to :event
  belongs_to :print_station
  belongs_to :participant
  belongs_to :bulk_print_run, optional: true

  enum :status, { pending: 0, sent: 1, succeeded: 2, failed: 3 }
  # manual (participant list/show Print button) / kiosk (check-in "also print"/"print only") /
  # bulk (BulkPrintRunJob) — mirrors ScanEvent#source's "who/what triggered this" shape, kept as
  # its own enum since the two taxonomies aren't the same values.
  enum :source, { manual: 0, kiosk: 1, bulk: 2 }
end
