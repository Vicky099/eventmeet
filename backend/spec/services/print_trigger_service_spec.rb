require "rails_helper"

RSpec.describe PrintTriggerService, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }
  let(:participant) { create(:participant, account: account, event: event) }

  before { Current.account = account }

  context "with no badge designed for the event" do
    it "returns no_badge and writes no ScanEvent" do
      result = PrintTriggerService.call(event: event, participant: participant, source: :manual)

      expect(result).to be_no_badge
      expect(ScanEvent.count).to eq(0)
    end
  end

  context "with a badge but no station" do
    before { create(:badge, account: account, event: event) }

    it "falls back and still logs a print ScanEvent (requirement.md §6 item 13)" do
      result = PrintTriggerService.call(event: event, participant: participant, source: :manual)

      expect(result).to be_fallback
      expect(result.badge).to be_present
      expect(ScanEvent.last).to have_attributes(scan_type: "print", source: "manual", participant: participant)
    end
  end

  context "with a badge and an online default station" do
    before { create(:badge, account: account, event: event) }

    it "dispatches a PrintJob and logs the ScanEvent with source :agent regardless of caller source" do
      station = create(:print_station, :online, account: account, event: event)
      event.update!(default_print_station: station)

      result = PrintTriggerService.call(event: event, participant: participant, source: :manual)

      expect(result).to be_dispatched
      expect(result.station).to eq(station)
      expect(result.print_job).to have_attributes(status: "sent", participant: participant, print_station: station)
      expect(ScanEvent.last).to have_attributes(scan_type: "print", source: "agent")
    end

    it "falls back when the resolved station is offline" do
      station = create(:print_station, account: account, event: event) # not paired/online
      event.update!(default_print_station: station)

      result = PrintTriggerService.call(event: event, participant: participant, source: :manual)

      expect(result).to be_fallback
      expect(PrintJob.count).to eq(0)
    end

    it "prefers an explicitly-passed station over the event default" do
      default_station = create(:print_station, :online, account: account, event: event)
      other_station = create(:print_station, :online, account: account, event: event)
      event.update!(default_print_station: default_station)

      result = PrintTriggerService.call(event: event, participant: participant, source: :manual, station: other_station)

      expect(result.station).to eq(other_station)
    end
  end

  context "debounce (mirrors ScanService's own 30-second window)" do
    before { create(:badge, account: account, event: event) }

    it "debounces a second call for the same participant within the window" do
      PrintTriggerService.call(event: event, participant: participant, source: :manual)

      result = PrintTriggerService.call(event: event, participant: participant, source: :manual)

      expect(result).to be_debounced
      expect(ScanEvent.count).to eq(1)
    end

    it "allows another print once the debounce window has passed" do
      PrintTriggerService.call(event: event, participant: participant, source: :manual)

      travel(PrintTriggerService::DEBOUNCE_WINDOW + 1.second) do
        result = PrintTriggerService.call(event: event, participant: participant, source: :manual)
        expect(result).to be_fallback
      end
    end
  end
end
