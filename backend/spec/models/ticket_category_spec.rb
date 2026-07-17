require "rails_helper"

RSpec.describe TicketCategory, type: :model do
  let(:account) { create(:account) }

  before { Current.account = account }

  it "is valid with the factory defaults" do
    expect(build(:ticket_category, account: account)).to be_valid
  end

  it "requires a name" do
    category = build(:ticket_category, account: account, name: nil)
    expect(category).not_to be_valid
  end

  it "requires total_count to be a positive integer when present" do
    expect(build(:ticket_category, account: account, total_count: 0)).not_to be_valid
    expect(build(:ticket_category, account: account, total_count: -1)).not_to be_valid
  end

  # Seat-limit-vs-combined-category-totals validation lives on Event now, not here — see
  # spec/models/event_spec.rb ("ticket_categories_within_seat_limit") for why: it has to see every
  # category in the current save, including ones that don't exist in the database yet.

  describe "total_count presence (requirement.md §5.3 revisit — unlimited categories)" do
    it "is not required when the event has no seat limit" do
      event = create(:event, account: account, has_seat_limit: false)
      category = build(:ticket_category, account: account, event: event, total_count: nil)

      expect(category).to be_valid
    end

    it "is required once the event has a seat limit" do
      event = create(:event, account: account, has_seat_limit: true, seat_limit: 100)
      category = build(:ticket_category, account: account, event: event, total_count: nil)

      expect(category).not_to be_valid
      expect(category.errors[:total_count]).to be_present
    end
  end

  describe "#unlimited?" do
    it "is true when total_count is nil" do
      expect(build(:ticket_category, account: account, total_count: nil)).to be_unlimited
    end

    it "is false when total_count is set" do
      expect(build(:ticket_category, account: account, total_count: 10)).not_to be_unlimited
    end
  end

  describe "#sync_counts!" do
    it "reflects only reserved seats in sold_count/remain_count, not waitlisted or cancelled ones" do
      category = create(:ticket_category, account: account, total_count: 10)
      create(:ticket_reservation, account: account, ticket_category: category, seat_count: 3, status: :reserved)
      create(:ticket_reservation, account: account, ticket_category: category, seat_count: 4, status: :waitlisted)
      create(:ticket_reservation, account: account, ticket_category: category, seat_count: 2, status: :cancelled)

      category.sync_counts!

      expect(category.sold_count).to eq(3)
      expect(category.remain_count).to eq(7)
    end

    it "keeps remain_count nil for an unlimited category, still tracking sold_count" do
      event = create(:event, account: account, has_seat_limit: false)
      category = create(:ticket_category, account: account, event: event, total_count: nil)
      create(:ticket_reservation, account: account, ticket_category: category, seat_count: 3, status: :reserved)

      category.sync_counts!

      expect(category.sold_count).to eq(3)
      expect(category.remain_count).to be_nil
    end
  end

  describe "remain_count on direct save (not via TicketReservationService)" do
    it "initializes remain_count to total_count on plain creation, not the schema's 0 default" do
      category = create(:ticket_category, account: account, total_count: 30)

      expect(category.sold_count).to eq(0)
      expect(category.remain_count).to eq(30)
    end

    it "keeps remain_count in step when total_count is edited directly, preserving sold_count" do
      category = create(:ticket_category, account: account, total_count: 10)
      create(:ticket_reservation, account: account, ticket_category: category, seat_count: 4, status: :reserved)
      category.sync_counts!
      expect(category.remain_count).to eq(6)

      category.update!(total_count: 20)

      expect(category.sold_count).to eq(4)
      expect(category.remain_count).to eq(16)
    end
  end
end
