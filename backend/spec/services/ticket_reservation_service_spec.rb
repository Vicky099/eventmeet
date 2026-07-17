require "rails_helper"

RSpec.describe TicketReservationService, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  describe ".reserve" do
    it "reserves seats and decrements the category's remain_count" do
      category = create(:ticket_category, account: account, event: event, total_count: 5)

      result = described_class.reserve(ticket_category: category, seat_count: 2, holder_name: "Alice", holder_email: "alice@example.com")

      expect(result).to be_success
      expect(result.reservation).to be_reserved
      expect(category.reload.sold_count).to eq(2)
      expect(category.remain_count).to eq(3)
    end

    it "waitlists instead of rejecting when the category is already full" do
      category = create(:ticket_category, account: account, event: event, total_count: 2)
      described_class.reserve(ticket_category: category, seat_count: 2, holder_name: "Alice", holder_email: "alice@example.com")

      result = described_class.reserve(ticket_category: category, seat_count: 1, holder_name: "Bob", holder_email: "bob@example.com")

      expect(result).to be_success
      expect(result.reservation).to be_waitlisted
      expect(category.reload.remain_count).to eq(0)
    end

    it "waitlists a request that would exceed remaining capacity, even if some seats are free" do
      category = create(:ticket_category, account: account, event: event, total_count: 5)
      described_class.reserve(ticket_category: category, seat_count: 4, holder_name: "Alice", holder_email: "alice@example.com")

      result = described_class.reserve(ticket_category: category, seat_count: 3, holder_name: "Bob", holder_email: "bob@example.com")

      expect(result.reservation).to be_waitlisted
      expect(category.reload.remain_count).to eq(1)
    end

    it "fails validation for a non-positive seat_count instead of silently waitlisting" do
      category = create(:ticket_category, account: account, event: event, total_count: 5)

      result = described_class.reserve(ticket_category: category, seat_count: 0, holder_name: "Alice", holder_email: "alice@example.com")

      expect(result).not_to be_success
      expect(result.reservation.errors[:seat_count]).to be_present
    end

    it "always reserves (never waitlists) against an unlimited category, regardless of how many seats are requested" do
      category = create(:ticket_category, account: account, event: event, total_count: nil)

      result = described_class.reserve(ticket_category: category, seat_count: 500, holder_name: "Alice", holder_email: "alice@example.com")

      expect(result).to be_success
      expect(result.reservation).to be_reserved
      expect(category.reload.sold_count).to eq(500)
      expect(category.remain_count).to be_nil
    end
  end

  describe ".cancel" do
    it "restores remain_count when cancelling an active reservation" do
      category = create(:ticket_category, account: account, event: event, total_count: 5)
      reservation = described_class.reserve(ticket_category: category, seat_count: 2, holder_name: "Alice", holder_email: "alice@example.com").reservation

      result = described_class.cancel(reservation)

      expect(result).to be_success
      expect(reservation.reload).to be_cancelled
      expect(reservation.cancelled_at).to be_present
      expect(category.reload.remain_count).to eq(5)
    end

    it "auto-promotes the oldest waitlisted reservation once a seat frees up, leaving a later one waitlisted if the freed capacity is already spoken for" do
      category = create(:ticket_category, account: account, event: event, total_count: 2)
      first = described_class.reserve(ticket_category: category, seat_count: 2, holder_name: "Alice", holder_email: "alice@example.com").reservation
      second = described_class.reserve(ticket_category: category, seat_count: 2, holder_name: "Bob", holder_email: "bob@example.com").reservation
      third = described_class.reserve(ticket_category: category, seat_count: 1, holder_name: "Carol", holder_email: "carol@example.com").reservation
      expect(second).to be_waitlisted
      expect(third).to be_waitlisted

      described_class.cancel(first)

      expect(second.reload).to be_reserved
      expect(third.reload).to be_waitlisted
      expect(category.reload.remain_count).to eq(0)
    end

    it "promotes every waitlisted group that fits when a cancellation frees enough capacity for more than one" do
      category = create(:ticket_category, account: account, event: event, total_count: 3)
      alice = described_class.reserve(ticket_category: category, seat_count: 3, holder_name: "Alice", holder_email: "alice@example.com").reservation
      bob = described_class.reserve(ticket_category: category, seat_count: 2, holder_name: "Bob", holder_email: "bob@example.com").reservation
      carol = described_class.reserve(ticket_category: category, seat_count: 1, holder_name: "Carol", holder_email: "carol@example.com").reservation

      described_class.cancel(alice)

      expect(bob.reload).to be_reserved
      expect(carol.reload).to be_reserved
      expect(category.reload.remain_count).to eq(0)
    end

    it "skips a waitlisted group too large for the freed capacity, promoting a later one that fits (first-fit, not strict FIFO blocking)" do
      category = create(:ticket_category, account: account, event: event, total_count: 2)
      alice = described_class.reserve(ticket_category: category, seat_count: 2, holder_name: "Alice", holder_email: "alice@example.com").reservation
      big_group = described_class.reserve(ticket_category: category, seat_count: 3, holder_name: "Big Group", holder_email: "big@example.com").reservation
      solo = described_class.reserve(ticket_category: category, seat_count: 1, holder_name: "Solo", holder_email: "solo@example.com").reservation

      described_class.cancel(alice)

      expect(big_group.reload).to be_waitlisted
      expect(solo.reload).to be_reserved
      expect(category.reload.remain_count).to eq(1)
    end

    it "does not promote anything when cancelling an already-waitlisted reservation" do
      category = create(:ticket_category, account: account, event: event, total_count: 1)
      described_class.reserve(ticket_category: category, seat_count: 1, holder_name: "Alice", holder_email: "alice@example.com")
      waitlisted = described_class.reserve(ticket_category: category, seat_count: 1, holder_name: "Bob", holder_email: "bob@example.com").reservation

      result = described_class.cancel(waitlisted)

      expect(result).to be_success
      expect(waitlisted.reload).to be_cancelled
      expect(category.reload.remain_count).to eq(0)
    end

    it "is a no-op on an already-cancelled reservation" do
      category = create(:ticket_category, account: account, event: event, total_count: 5)
      reservation = described_class.reserve(ticket_category: category, seat_count: 1, holder_name: "Alice", holder_email: "alice@example.com").reservation
      described_class.cancel(reservation)

      result = described_class.cancel(reservation)

      expect(result).not_to be_success
    end
  end
end
