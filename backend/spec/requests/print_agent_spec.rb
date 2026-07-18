require "rails_helper"

# Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1, §4.9 item 3). The
# Electron device's own two HTTP touchpoints — no Devise session involved on either.
RSpec.describe "Print agent", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }
  let(:event) { Current.account = account; create(:event, account: account) }

  before { host! "acme.example.com" }

  describe "POST /print_agent/pair" do
    it "issues a correctly scoped JWT for a valid, unexpired pairing code" do
      Current.account = account
      station = create(:print_station, account: account, event: event)
      code = station.generate_pairing_code!

      post print_agent_pair_path, params: { pairing_code: code }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["station_name"]).to eq(station.name)

      agent = PrintAgentToken.decode(body["token"])
      Current.account = account
      expect(agent.print_station).to eq(station)
      expect(agent.account_id).to eq(account.id)
    end

    it "consumes the code — a second redemption attempt fails" do
      Current.account = account
      station = create(:print_station, account: account, event: event)
      code = station.generate_pairing_code!
      post print_agent_pair_path, params: { pairing_code: code }, as: :json

      post print_agent_pair_path, params: { pairing_code: code }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects an unknown code" do
      post print_agent_pair_path, params: { pairing_code: "NOPE0000" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects a code scoped to a different tenant's subdomain" do
      other_account = create(:account, subdomain_slug: "other")
      Current.account = other_account
      other_event = create(:event, account: other_account)
      other_station = create(:print_station, account: other_account, event: other_event)
      code = other_station.generate_pairing_code!

      post print_agent_pair_path, params: { pairing_code: code }, as: :json # still on acme.example.com

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /print_agent/print_jobs/:id/badge" do
    it "streams the badge PDF for a valid, non-revoked agent token" do
      Current.account = account
      create(:badge, account: account, event: event)
      station = create(:print_station, account: account, event: event)
      agent = create(:print_agent, account: account, event: event, print_station: station)
      job = create(:print_job, account: account, event: event, print_station: station)
      token = PrintAgentToken.encode(agent)

      get print_agent_badge_path(job.id), headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq("application/pdf")
    end

    it "rejects a revoked agent's token" do
      Current.account = account
      station = create(:print_station, account: account, event: event)
      agent = create(:print_agent, account: account, event: event, print_station: station)
      job = create(:print_job, account: account, event: event, print_station: station)
      token = PrintAgentToken.encode(agent)
      agent.update!(revoked_at: Time.current)

      get print_agent_badge_path(job.id), headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a missing/garbage token" do
      Current.account = account
      station = create(:print_station, account: account, event: event)
      job = create(:print_job, account: account, event: event, print_station: station)

      get print_agent_badge_path(job.id)

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
