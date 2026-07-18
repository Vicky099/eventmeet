# Shared currency support for Quotation/QuotationRevision/Invoice (requirement.md §4.6's billing
# lifecycle) — a small fixed set, not a full ISO-4217 list, since this app only ever needs
# whatever the platform actually invoices in. INR is the default everywhere (`Quotation#currency`
# defaults to it — the platform's primary currency) — the others exist so a Super Admin can quote
# a specific event in a different currency when asked to.
module Currency
  SYMBOLS = {
    "INR" => "₹",
    "USD" => "$",
    "EUR" => "€",
    "GBP" => "£"
  }.freeze

  CODES = SYMBOLS.keys.freeze

  def self.symbol_for(code)
    SYMBOLS.fetch(code, code)
  end
end
