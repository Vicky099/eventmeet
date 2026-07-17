require "rails_helper"

RSpec.describe Schedule, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }
  let(:speaker) { create(:speaker, account: account) }

  before { Current.account = account }

  it "is valid with the factory defaults" do
    expect(build(:schedule, account: account, event: event, speaker: speaker)).to be_valid
  end

  it "requires a title" do
    expect(build(:schedule, account: account, event: event, speaker: speaker, title: nil)).not_to be_valid
  end

  it "requires ends_at after starts_at" do
    schedule = build(:schedule, account: account, event: event, speaker: speaker,
      starts_at: 2.hours.from_now, ends_at: 1.hour.from_now)
    expect(schedule).not_to be_valid
  end

  it "is valid with no session (a room-less standalone talk, requirement.md §3.8)" do
    expect(build(:schedule, account: account, event: event, speaker: speaker, session: nil)).to be_valid
  end

  describe "#speaker_double_booked? / .overlapping (requirement.md Phase 11 checklist: informational, not blocking)" do
    it "is false with no other talks" do
      schedule = create(:schedule, account: account, event: event, speaker: speaker,
        starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour)
      expect(schedule).not_to be_speaker_double_booked
    end

    it "is true when the same speaker has an overlapping talk, but the record still saves" do
      create(:schedule, account: account, event: event, speaker: speaker,
        starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour)

      overlapping = build(:schedule, account: account, event: event, speaker: speaker,
        starts_at: 1.day.from_now + 30.minutes, ends_at: 1.day.from_now + 90.minutes)

      expect(overlapping.save).to be true
      expect(overlapping).to be_speaker_double_booked
    end

    it "catches an overlap across two different events under the same account (Speaker is reusable across events)" do
      other_event = create(:event, account: account)
      create(:schedule, account: account, event: event, speaker: speaker,
        starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour)

      overlapping = create(:schedule, account: account, event: other_event, speaker: speaker,
        starts_at: 1.day.from_now + 30.minutes, ends_at: 1.day.from_now + 90.minutes)

      expect(overlapping).to be_speaker_double_booked
    end

    it "is false for back-to-back (non-overlapping) talks" do
      create(:schedule, account: account, event: event, speaker: speaker,
        starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour)

      back_to_back = create(:schedule, account: account, event: event, speaker: speaker,
        starts_at: 1.day.from_now + 1.hour, ends_at: 1.day.from_now + 2.hours)

      expect(back_to_back).not_to be_speaker_double_booked
    end

    it "is false when a different speaker has the overlapping talk" do
      other_speaker = create(:speaker, account: account)
      create(:schedule, account: account, event: event, speaker: other_speaker,
        starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour)

      schedule = create(:schedule, account: account, event: event, speaker: speaker,
        starts_at: 1.day.from_now + 30.minutes, ends_at: 1.day.from_now + 90.minutes)

      expect(schedule).not_to be_speaker_double_booked
    end
  end
end
