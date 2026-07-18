# Phase 15 — Platform Billing & Invoicing (requirement.md §4.6, §8): the Business-tier negotiation
# — "organizer requests a Business-tier event -> Super Admin sends amount -> tenant approves (event
# creation unblocked) or rejects-with-note ... up to 3 rejections; on the 3rd, cancelled."
#
# Deliberately NOT `belongs_to :event` — a Quotation exists *before* any Event row can (that's the
# whole point of the gate, Event's own quotation_must_be_approved_and_available). `has_one :event`
# below is the reverse: once approved and consumed, exactly one Event ends up pointing back at it
# via `events.quotation_id`.
#
# `status` mirrors Event's own approval state-machine shape (`#submit_for_review!`/`#approve!`/
# `#reject!`) almost exactly, just with a 4th terminal `cancelled` state Event's own approval never
# needed. `pending` covers two different waiting states on purpose — "Super Admin hasn't sent a
# first amount yet" and "tenant hasn't decided on a sent amount yet" — `current_amount.present?` is
# what tells a view which one it's looking at; a 5th enum value would just duplicate that.
class Quotation < ApplicationRecord
  include TenantScoped

  enum :status, { pending: 0, approved: 1, rejected: 2, cancelled: 3 }

  MAX_REJECTIONS = 3

  belongs_to :requested_by, class_name: "User"
  belongs_to :approved_by, class_name: "User", optional: true
  has_many :quotation_revisions, dependent: :destroy
  has_one :event

  validates :event_name, presence: true
  validates :current_amount, numericality: { greater_than: 0 }, allow_nil: true
  validates :currency, inclusion: { in: Currency::CODES }
  # Confirmed with the user: the Super Admin was pricing a quotation with no idea how many people
  # it was actually for — required from the very first request, not an optional nice-to-have.
  # `invite_via_email`/`invite_via_whatsapp`/`support_requested` are plain booleans (checkboxes on
  # the request form) rather than a combined enum — a tenant can legitimately want any combination
  # of the three, including none.
  #
  # `on: :create` — real bug caught live: without it, every `#approve!`/`#reject!`/`#send_amount!`
  # (all plain `update!` calls) on a quotation from *before* this field existed raised
  # ActiveRecord::RecordInvalid, since full validation reruns on every save, not just the create
  # this field is actually meant to gate. Same "don't retroactively invalidate legacy rows"
  # reasoning as `events.quotation_id` staying nullable at the DB level (Event's own migration
  # comment) — enforced only at the one point new data is actually collected.
  validates :expected_participant_count, presence: true, numericality: { only_integer: true, greater_than: 0 }, on: :create

  # Super Admin action — both the very first offer (current_amount nil -> a real figure) and every
  # revision after a rejection use this same method; the caller doesn't need to know which. No
  # `by:` — unlike #approve!, there's no column to record who sent it (revisit if that auditing is
  # ever actually needed; not worth a column nobody reads yet). `currency` is picked fresh each
  # send (defaults to whatever's already on the row, i.e. INR on the very first send) — nothing
  # stops a revised offer switching currency, and QuotationRevision's own snapshot is what makes
  # that safe to display accurately after the fact.
  def send_amount!(amount:, currency: self.currency)
    update!(current_amount: amount, currency: currency, status: :pending, sent_at: Time.current, approved_by: nil, approved_at: nil)
  end

  def approve!(by:)
    update!(status: :approved, approved_by: by, approved_at: Time.current)
  end

  # Tenant action — logs a QuotationRevision (the audit trail: what was rejected, why, by whom),
  # then either goes back to the Super Admin for a revised offer (`rejected`) or, on the 3rd
  # rejection, ends the negotiation for good (`cancelled` — requirement.md: "the tenant would need
  # to start a fresh Business-tier request to try again, not resume a cancelled one").
  def reject!(note:, by:)
    transaction do
      quotation_revisions.create!(account: account, amount: current_amount, currency: currency, rejection_note: note, created_by: by)
      update!(status: quotation_revisions.count >= MAX_REJECTIONS ? :cancelled : :rejected)
    end
  end
end
