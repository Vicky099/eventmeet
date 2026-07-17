require "rails_helper"

RSpec.describe LiveMetricBucket, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  describe ".increment!" do
    it "atomically upserts into the same minute bucket" do
      now = Time.current.change(sec: 0)
      3.times { LiveMetricBucket.increment!(event: event, metric: :check_in, at: now) }

      bucket = LiveMetricBucket.sole
      expect(bucket.count).to eq(3)
    end

    it "creates separate buckets for different minutes" do
      LiveMetricBucket.increment!(event: event, metric: :check_in, at: Time.current)
      LiveMetricBucket.increment!(event: event, metric: :check_in, at: 5.minutes.from_now)

      expect(LiveMetricBucket.count).to eq(2)
    end

    it "keeps registration and check_in metrics in separate buckets for the same minute" do
      now = Time.current.change(sec: 0)
      LiveMetricBucket.increment!(event: event, metric: :registration, at: now)
      LiveMetricBucket.increment!(event: event, metric: :check_in, at: now)

      expect(LiveMetricBucket.count).to eq(2)
    end
  end

  describe ".sparkline_series (requirement.md §5.15)" do
    it "zero-fills minutes with no activity, ordered chronologically" do
      LiveMetricBucket.increment!(event: event, metric: :check_in, at: Time.current)

      series = LiveMetricBucket.sparkline_series(event: event, metric: :check_in, minutes: 5)

      expect(series.size).to eq(5)
      expect(series.last.last).to eq(1)
      expect(series.first.last).to eq(0)
    end
  end
end
