# Quotations were priced in an implicit, unstated currency — the Super Admin now picks one
# explicitly per amount sent (defaults to INR, the platform's primary currency), and it carries
# through to the QuotationRevision snapshot (currency could differ between negotiation rounds, same
# reasoning `amount` is already snapshotted per revision) and the Invoice generated from the
# approved quotation (InvoiceGenerationJob copies it straight across — one quotation's currency is
# the event's currency for its whole billing lifecycle).
class AddCurrencyToQuotationsAndInvoices < ActiveRecord::Migration[8.0]
  def change
    add_column :quotations, :currency, :string, null: false, default: "INR"
    add_column :quotation_revisions, :currency, :string, null: false, default: "INR"
    add_column :invoices, :currency, :string, null: false, default: "INR"
  end
end
