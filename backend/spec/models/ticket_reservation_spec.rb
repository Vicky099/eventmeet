require "rails_helper"

RSpec.describe TicketReservation, type: :model do
  let(:account) { create(:account) }

  before { Current.account = account }

  it "is valid with the factory defaults" do
    expect(build(:ticket_reservation, account: account)).to be_valid
  end

  it "requires a positive seat_count" do
    expect(build(:ticket_reservation, account: account, seat_count: 0)).not_to be_valid
  end

  it "requires holder_name and holder_email" do
    reservation = build(:ticket_reservation, account: account, holder_name: nil, holder_email: nil)
    expect(reservation).not_to be_valid
    expect(reservation.errors[:holder_name]).to be_present
    expect(reservation.errors[:holder_email]).to be_present
  end

  it "generates a unique claim_token on create" do
    a = create(:ticket_reservation, account: account)
    b = create(:ticket_reservation, account: account)

    expect(a.claim_token).to be_present
    expect(a.claim_token).not_to eq(b.claim_token)
  end

  it "defaults to reserved status" do
    expect(create(:ticket_reservation, account: account).status).to eq("reserved")
  end
end
