require "rails_helper"

RSpec.describe PrintAgentToken, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  it "round-trips: encoding then decoding resolves back to the same PrintAgent" do
    station = create(:print_station, account: account, event: event)
    agent = create(:print_agent, account: account, event: event, print_station: station)

    token = PrintAgentToken.encode(agent)

    expect(PrintAgentToken.decode(token)).to eq(agent)
  end

  it "returns nil for a garbage token" do
    expect(PrintAgentToken.decode("not-a-jwt")).to be_nil
  end

  it "returns nil for a blank token" do
    expect(PrintAgentToken.decode(nil)).to be_nil
  end

  it "returns nil once the agent has been revoked, even with a still-valid signature" do
    station = create(:print_station, account: account, event: event)
    agent = create(:print_agent, account: account, event: event, print_station: station)
    token = PrintAgentToken.encode(agent)

    agent.update!(revoked_at: Time.current)

    expect(PrintAgentToken.decode(token)).to be_nil
  end

  it "returns nil for a token signed with a different secret" do
    station = create(:print_station, account: account, event: event)
    agent = create(:print_agent, account: account, event: event, print_station: station)
    payload = { account_id: agent.account_id, event_id: agent.event_id, station_id: agent.print_station_id,
                agent_id: agent.id, jti: agent.jti, exp: 1.hour.from_now.to_i }
    tampered = JWT.encode(payload, "wrong-secret", "HS256")

    expect(PrintAgentToken.decode(tampered)).to be_nil
  end
end
