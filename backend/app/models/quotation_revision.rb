# Phase 15 — Platform Billing & Invoicing (requirement.md §4.6, §8): one row per rejection round of
# a Quotation's negotiation — see Quotation#reject! for how these get created (never directly).
# `amount` is a snapshot of what was rejected, not what's being offered next — the Super Admin's
# revised figure just becomes the parent Quotation's own `current_amount` (Quotation#send_amount!),
# not a second write onto this same row.
class QuotationRevision < ApplicationRecord
  include TenantScoped

  belongs_to :quotation
  belongs_to :created_by, class_name: "User"

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :rejection_note, presence: true
end
