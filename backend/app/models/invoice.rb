# Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6, confirmed with the
# user). The simplified lifecycle:
#   event completes -> next day InvoiceGenerationJob auto-creates a `draft` Invoice for
#   `event.quotation.current_amount` (no plan tiers/overage math left — Business is the only plan,
#   priced once via its Quotation) -> Super Admin reviews and `#send!`s it -> tenant submits UTR +
#   a receipt via the "Mark as Paid" modal (`#submit_payment!`) -> Super Admin `#verify!`s it
#   (paid) or `#reject_payment!`s it (clears the UTR/receipt "slot" for exactly one resubmission,
#   with a reason the tenant sees).
#
# One Invoice per Event — enforced with a unique index, matching "one quotation -> one event"
# already enforced on `events.quotation_id`; `has_one :invoice` on Event is the other half.
# PaymentSubmission (a separate table in the original build) is folded directly onto these columns
# — the simplified flow only ever needs one "current" payment attempt at a time, not a full
# multi-attempt history table.
class Invoice < ApplicationRecord
  include TenantScoped
  include TenantScopedAttachment

  enum :status, { draft: 0, awaiting_payment: 1, under_review: 2, paid: 3 }

  belongs_to :event
  belongs_to :submitted_by, class_name: "User", optional: true
  belongs_to :verified_by, class_name: "User", optional: true
  has_one_attached :receipt

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, inclusion: { in: Currency::CODES }
  # A light safety net matching the invariant #submit_payment! itself always maintains (utr set
  # together with the status change, same update! call) — not the actual enforcement point.
  # `rejection_reason` has no equivalent status-based check here (unlike Event's own
  # `if: :rejected?` — this model folds "rejected" back into `awaiting_payment` rather than a
  # distinct status, so there's no clean state to hook a presence validation to); the controller
  # guards a blank reason before ever calling #reject_payment!, same "controller pre-checks,
  # model method is a raw mutation" split every other bang-method in this app already takes.
  validates :utr_reference, presence: true, if: :under_review?

  # InvoiceGenerationJob's own entry point — one Invoice, straight from the approved Quotation's
  # own amount and currency (no editable draft-amount step the way the original per-plan
  # computation needed; there's only one number, so there's nothing to review before this besides
  # "is it correct," which is what the Super Admin's own review-before-#send! step is for).
  def self.generate_for(event)
    event.create_invoice!(account: event.account, amount: event.quotation.current_amount, currency: event.quotation.currency)
  end

  def attach_receipt(uploaded_file)
    attach_tenant_scoped(:receipt, uploaded_file, "invoices", event_id)
  end

  # Super Admin action — the only thing that actually notifies the tenant (BillingMailer, from the
  # controller, not baked in here — same "controller orchestrates, model method is a raw mutation"
  # split every other bang-method in this app takes).
  def send!
    update!(status: :awaiting_payment)
  end

  # Tenant action — the "Mark as Paid" modal. Overwrites any previous (rejected) UTR/receipt —
  # there's only ever one current attempt, not a history of past ones.
  def submit_payment!(utr_reference:, receipt:, by:)
    update!(utr_reference: utr_reference, submitted_by: by, submitted_at: Time.current, status: :under_review)
    attach_receipt(receipt) if receipt.present?
  end

  def verify!(by:)
    update!(status: :paid, verified_by: by, verified_at: Time.current, rejection_reason: nil)
  end

  # Back to awaiting_payment (resubmittable via the same modal) — deliberately does NOT clear
  # `utr_reference`/`receipt`: BillingMailer#payment_rejected reads them to tell the tenant exactly
  # what was rejected, and the next #submit_payment! call overwrites both anyway (one "slot," not a
  # history), so there's no window where a stale value could be mistaken for a fresh submission.
  def reject_payment!(reason:, by:)
    update!(status: :awaiting_payment, rejection_reason: reason, verified_by: by, verified_at: Time.current)
  end
end
