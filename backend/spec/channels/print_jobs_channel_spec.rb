require "rails_helper"

RSpec.describe PrintJobsChannel, type: :channel do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }
  let(:station) { create(:print_station, account: account, event: event) }
  let(:agent) { create(:print_agent, account: account, event: event, print_station: station, connected: false) }

  before do
    Current.account = account
    stub_connection(current_print_agent: agent)
  end

  it "subscribes a live agent to its station's stream and marks it connected" do
    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(station)
    expect(agent.reload).to be_connected
  end

  it "rejects a revoked agent" do
    agent.update!(revoked_at: Time.current)

    subscribe

    expect(subscription).to be_rejected
  end

  it "marks the agent disconnected on unsubscribe" do
    subscribe
    unsubscribe

    expect(agent.reload).not_to be_connected
  end

  # Phase 10 DoD: "a simulated agent connection ... receives a PrintJob push when a qualifying
  # scan occurs and auto-print is on" — the channel side of that: broadcast_to(station, ...)
  # reaches a subscribed agent.
  it "receives a print_job broadcast for its own station" do
    subscribe
    Current.account = account # subscribe's own executor wrap resets Current — see #subscribed's comment
    participant = create(:participant, account: account, event: event)

    expect {
      PrintJobsChannel.broadcast_to(station, "action" => "print_job", "job_id" => "some-id", "participant_name" => participant.name)
    }.to have_broadcasted_to(station).with(hash_including("action" => "print_job", "participant_name" => participant.name))
  end

  describe "#job_update" do
    it "updates a PrintJob to succeeded" do
      job = create(:print_job, account: account, event: event, print_station: station, status: :sent)
      subscribe

      perform :job_update, "job_id" => job.id, "status" => "succeeded"

      expect(job.reload).to be_succeeded
    end

    it "updates a PrintJob to failed with the reported error" do
      job = create(:print_job, account: account, event: event, print_station: station, status: :sent)
      subscribe

      perform :job_update, "job_id" => job.id, "status" => "failed", "error" => "printer offline"

      expect(job.reload).to be_failed
      expect(job.error_message).to eq("printer offline")
    end
  end

  describe "#heartbeat" do
    it "touches last_seen_at" do
      subscribe
      agent.update!(last_seen_at: 1.hour.ago)

      perform :heartbeat

      expect(agent.reload.last_seen_at).to be_within(5.seconds).of(Time.current)
    end
  end
end
