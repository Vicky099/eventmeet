# Phase 10 revisit — Bulk Print (requirement.md §3.6/§5.5's baseline "bulk print queue,"
# rebuilt against real PrintStation/PrintJob infrastructure). completed_count/
# last_printed_participant are computed off this run's own print_jobs, not stored — one source of
# truth for "how far did this batch get," which is exactly what an admin needs to know when a
# physical printer runs out of paper mid-run (requirement.md revisit: "we should know what was
# the last participant badge").
class BulkPrintRun < ApplicationRecord
  include TenantScoped

  belongs_to :event
  belongs_to :print_station
  belongs_to :created_by, class_name: "User"
  has_many :print_jobs, dependent: :nullify

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }

  validates :limit, numericality: { only_integer: true, greater_than: 0 }

  def completed_count
    print_jobs.succeeded.count
  end

  def failed_jobs
    print_jobs.failed.order(:sequence)
  end

  def last_printed_participant
    print_jobs.succeeded.order(:sequence).last&.participant
  end

  def percent_complete
    return 0 if limit.to_i.zero?

    ((completed_count.to_f / limit) * 100).round
  end
end
