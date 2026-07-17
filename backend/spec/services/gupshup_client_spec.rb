require "rails_helper"

# Phase 13 — Communications (requirement.md §3.10, §5.10, §5.12). Definition of Done: "Gupshup
# client handles a non-200 response by marking the notification failed, not raising unhandled" —
# this spec covers the client's own contract (raises the one well-typed DeliveryError, never a raw
# Net::HTTP/timeout exception); NotificationDeliveryJob's own rescue is what actually turns that
# into a `failed` Notification row (spec/jobs/notification_delivery_job_spec.rb).
RSpec.describe GupshupClient do
  describe "#send_message" do
    it "raises DeliveryError when no credentials are configured" do
      client = described_class.new(api_key: nil, source_number: nil)

      expect { client.send_message(to: "+15550100", body: "hi") }.to raise_error(GupshupClient::DeliveryError, /credentials/)
    end

    it "raises DeliveryError when the recipient is blank" do
      client = described_class.new(api_key: "key", source_number: "+15550199")

      expect { client.send_message(to: nil, body: "hi") }.to raise_error(GupshupClient::DeliveryError, /phone number/)
    end

    it "raises DeliveryError (not a raw HTTP exception) on a non-2xx response" do
      client = described_class.new(api_key: "key", source_number: "+15550199")
      response = instance_double(Net::HTTPBadRequest, code: "400", body: "invalid destination", is_a?: false)
      allow(Net::HTTP).to receive(:start).and_return(response)

      expect { client.send_message(to: "+15550100", body: "hi") }.to raise_error(GupshupClient::DeliveryError, /400/)
    end

    it "raises DeliveryError (not a raw network exception) when the request itself fails" do
      client = described_class.new(api_key: "key", source_number: "+15550199")
      allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)

      expect { client.send_message(to: "+15550100", body: "hi") }.to raise_error(GupshupClient::DeliveryError, /Gupshup request failed/)
    end

    it "returns the response on success" do
      client = described_class.new(api_key: "key", source_number: "+15550199")
      response = instance_double(Net::HTTPSuccess, is_a?: true)
      allow(Net::HTTP).to receive(:start).and_return(response)

      expect(client.send_message(to: "+15550100", body: "hi")).to eq(response)
    end
  end
end
