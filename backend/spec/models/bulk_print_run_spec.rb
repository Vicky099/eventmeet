require "rails_helper"

RSpec.describe BulkPrintRun, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  it "computes completed_count and last_printed_participant off its own succeeded print_jobs" do
    run = create(:bulk_print_run, account: account, event: event, limit: 5)
    first = create(:participant, account: account, event: event)
    second = create(:participant, account: account, event: event)
    create(:print_job, account: account, event: event, print_station: run.print_station,
      participant: first, bulk_print_run: run, sequence: 1, status: :succeeded)
    create(:print_job, account: account, event: event, print_station: run.print_station,
      participant: second, bulk_print_run: run, sequence: 2, status: :succeeded)

    expect(run.completed_count).to eq(2)
    expect(run.last_printed_participant).to eq(second)
    expect(run.percent_complete).to eq(40)
  end

  it "excludes pending/failed jobs from completed_count" do
    run = create(:bulk_print_run, account: account, event: event, limit: 5)
    create(:print_job, account: account, event: event, print_station: run.print_station,
      participant: create(:participant, account: account, event: event), bulk_print_run: run, status: :failed)

    expect(run.completed_count).to eq(0)
  end
end
