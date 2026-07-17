require "rails_helper"

RSpec.describe Attendance, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }
  let(:participant) { create(:participant, account: account, event: event) }

  before { Current.account = account }

  describe "time-spent computation (requirement.md §3.7)" do
    it "computes time_spent_seconds by pairing against the most recent check_in" do
      check_in_time = 1.hour.ago
      create(:attendance, event: event, participant: participant, account: account,
        from: :event, status: :check_in, occurred_at: check_in_time)

      check_out = create(:attendance, event: event, participant: participant, account: account,
        from: :event, status: :check_out, occurred_at: Time.current)

      expect(check_out.time_spent_seconds).to be_within(2).of(3600)
    end

    it "leaves time_spent_seconds nil for a check_in row" do
      check_in = create(:attendance, event: event, participant: participant, account: account, status: :check_in)
      expect(check_in.time_spent_seconds).to be_nil
    end

    it "leaves time_spent_seconds nil when there's no prior check_in to pair against" do
      check_out = create(:attendance, event: event, participant: participant, account: account, status: :check_out)
      expect(check_out.time_spent_seconds).to be_nil
    end

    it "pairs a manual_check_out the same way a real check_out would" do
      create(:attendance, event: event, participant: participant, account: account,
        status: :check_in, occurred_at: 30.minutes.ago)

      manual_check_out = create(:attendance, event: event, participant: participant, account: account,
        status: :manual_check_out, occurred_at: Time.current)

      expect(manual_check_out.time_spent_seconds).to be_within(2).of(30.minutes.to_i)
    end
  end

  it "defaults occurred_at to now when not given" do
    attendance = create(:attendance, event: event, participant: participant, account: account, occurred_at: nil)
    expect(attendance.occurred_at).to be_within(2.seconds).of(Time.current)
  end
end
