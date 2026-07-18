# Mirrors RegistrationPdfService's own shape exactly — one small Grover wrapper per document
# type is this app's established convention (BadgePdfService is the other sibling), not a
# shared generic "render this HTML as a PDF" service.
class InvoicePdfService
  MARGIN = "12mm".freeze

  def self.render(html:)
    new(html: html).render
  end

  def initialize(html:)
    @html = html
  end

  def render
    Grover.new(
      html,
      format: "A4",
      margin: { top: MARGIN, bottom: MARGIN, left: MARGIN, right: MARGIN },
      print_background: true
    ).to_pdf
  end

  private

  attr_reader :html
end
