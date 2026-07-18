require "rails_helper"

# Phase 10 revisit — Bulk Print (requirement.md §3.6/§5.5's baseline "bulk print queue").
RSpec.describe "Admin Console bulk print", type: :request do
  include ActiveJob::TestHelper

  let!(:account) { create(:account, subdomain_slug: "acme") }

  before { host! "acme.example.com" }

  def sign_in_with_role(role)
    user = create(:user, email: "#{role}@acme.example", password: "password123!")
    create(:account_membership, user: user, account: account, role: role)
    sign_in user, scope: :user
  end

  def create_event(**attrs)
    Current.account = account
    create(:event, account: account, **attrs)
  end

  describe "POST /admin/events/:event_id/bulk_print_runs" do
    before { sign_in_with_role(:owner) }

    it "creates a run and enqueues BulkPrintRunJob" do
      event = create_event
      Current.account = account
      station = create(:print_station, :online, account: account, event: event)

      expect {
        post admin_event_bulk_print_runs_path(event), params: { bulk_print_run: { print_station_id: station.id, limit: 25 } }
      }.to have_enqueued_job(BulkPrintRunJob)

      Current.account = account
      run = event.bulk_print_runs.sole
      expect(response).to redirect_to(admin_event_bulk_print_run_path(event, run))
    end
  end

  describe "BulkPrintRunJob" do
    # completed_count/last_printed_participant only count *succeeded* jobs (the agent's own
    # ack over the channel — see PrintTriggerService's dispatched-vs-sent-vs-succeeded shape and
    # BulkPrintRun's own model spec for that computation) — this job's own job is dispatching,
    # covered here by asserting exactly one new PrintJob (status: sent) landed for the
    # not-yet-printed participant and none for the one that already succeeded.
    it "dispatches up to the limit, skipping participants with an already-succeeded PrintJob" do
      event = create_event
      Current.account = account
      create(:badge, account: account, event: event)
      station = create(:print_station, :online, account: account, event: event)
      already_printed = create(:participant, account: account, event: event)
      create(:print_job, account: account, event: event, print_station: station, participant: already_printed, status: :succeeded)
      pending_one = create(:participant, account: account, event: event)

      run = create(:bulk_print_run, account: account, event: event, print_station: station, created_by: create(:user), limit: 5)

      BulkPrintRunJob.perform_now(run.id)

      Current.account = account
      run.reload
      expect(run).to be_completed
      new_job = run.print_jobs.sole
      expect(new_job).to have_attributes(participant: pending_one, status: "sent", sequence: 1)
    end

    it "marks completed_count/last_printed_participant once the agent acks the job" do
      event = create_event
      Current.account = account
      create(:badge, account: account, event: event)
      station = create(:print_station, :online, account: account, event: event)
      participant = create(:participant, account: account, event: event)
      run = create(:bulk_print_run, account: account, event: event, print_station: station, created_by: create(:user), limit: 5)

      BulkPrintRunJob.perform_now(run.id)
      Current.account = account
      run.print_jobs.sole.update!(status: :succeeded)

      expect(run.completed_count).to eq(1)
      expect(run.last_printed_participant).to eq(participant)
    end
  end
end
