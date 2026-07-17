# Phase 13 — Communications (requirement.md §3.10, §5.10, §5.12). "Gupshup account/sender-number/
# template setup is the stakeholder's own responsibility, not a platform-engineering task —
# implementation can assume the credential exists" (§10.16) — this class builds the integration
# code against Gupshup's own REST API (https://api.gupshup.io/wa/api/v1/msg — the standard
# form-encoded "send message" endpoint, `apikey` header auth), not the Gupshup account itself.
# Platform-level credential (ENV, not per-tenant — requirement.md §8: "sent via Gupshup,
# platform-level credential (not per-tenant)"), same env-var-driven pattern ApplicationMailer's
# own MAILER_FROM already uses for its platform-level default.
class GupshupClient
  class DeliveryError < StandardError; end

  ENDPOINT = "https://api.gupshup.io/wa/api/v1/msg".freeze

  def initialize(api_key: ENV["GUPSHUP_API_KEY"], source_number: ENV["GUPSHUP_SOURCE_NUMBER"])
    @api_key = api_key
    @source_number = source_number
  end

  # to: a plain phone number string (User#contact_num, requirement.md §8 — "no separate
  # WhatsApp-specific field needed"). Raises DeliveryError (never lets a raw Net::HTTP/timeout
  # exception escape) on missing credentials or a non-2xx response — NotificationDeliveryJob's own
  # rescue is what actually turns that into a `failed` Notification row; this class's only job is
  # "never raise something unhandled," per this phase's own Definition of Done.
  def send_message(to:, body:)
    raise DeliveryError, "Gupshup credentials not configured (GUPSHUP_API_KEY/GUPSHUP_SOURCE_NUMBER)" if @api_key.blank? || @source_number.blank?
    raise DeliveryError, "recipient phone number is blank" if to.blank?

    response = post(to: to, body: body)
    raise DeliveryError, "Gupshup returned #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    response
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
    raise DeliveryError, "Gupshup request failed: #{e.class}: #{e.message}"
  end

  private

  def post(to:, body:)
    uri = URI(ENDPOINT)
    form = {
      "channel" => "whatsapp",
      "source" => @source_number,
      "destination" => to,
      "message" => { type: "text", text: body }.to_json,
      "src.name" => @source_number
    }

    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.post(uri.path, URI.encode_www_form(form), "apikey" => @api_key, "Content-Type" => "application/x-www-form-urlencoded")
    end
  end
end
