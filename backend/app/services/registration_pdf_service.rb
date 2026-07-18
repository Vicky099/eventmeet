# Phase 13 — Communications, revisited: "each email we send the attachment as well ... in PDF show
# same email template + QRcode for scanning purpose." Same Grover pipeline BadgePdfService already
# uses (app/services/badge_pdf_service.rb) — a real HTML document rendered to PDF bytes via
# headless Chrome — but this renders a normal document page (A4), not a badge's own fixed physical
# size, since a registration-confirmation PDF is meant to be read/printed like any other document,
# not cut to an exact badge stock.
#
# No QR-specific logic here anymore — the QR now lives inside `html` itself (Participant#
# qr_code_data_uri, via the `$QRCODE$` placeholder for a custom EmailTemplate, or directly in the
# built-in confirmation view), the same content that's also the actual email body. This service is
# just "whatever HTML was the email body, rendered to a PDF" — the PDF matches the inbox exactly,
# QR included, with no separate append step to keep in sync.
class RegistrationPdfService
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
