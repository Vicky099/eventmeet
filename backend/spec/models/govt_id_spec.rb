require "rails_helper"

# requirement.md revisit: "If we have govt id then we will upload that list this will be stored in
# database somewhere. Then once participant registration start then the government ID will start
# assign to participant. One govt id will be assigned to one participant." Plus the reverse: "If we
# already have participant, and then we got the govtIDs then while uploading the govtID it should
# automatically assign to the participant."
#
# Participant itself has an after_create_commit callback (#sync_govt_id_with_pool!) that already
# calls .assign_to!/.claim_existing_value! for every participant it creates — so throughout this
# file, a participant is always created *before* any GovtId pool row exists for its event whenever
# a test wants to call .assign_to!/.claim_existing_value! explicitly afterward and observe it do
# real work; otherwise the callback would have already done it moments earlier, during the
# `create(:participant, ...)` line itself, leaving nothing left for the explicit call to do.
RSpec.describe GovtId, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  describe "validations" do
    it "requires a value" do
      expect(build(:govt_id, account: account, event: event, value: nil)).not_to be_valid
    end

    it "is unique by event (requirement.md: 'GOVT ID will be unique by event')" do
      create(:govt_id, account: account, event: event, value: "GID-1")

      expect(build(:govt_id, account: account, event: event, value: "GID-1")).not_to be_valid
    end

    it "allows the same value across two different events" do
      other_event = create(:event, account: account)
      create(:govt_id, account: account, event: event, value: "GID-1")

      expect(build(:govt_id, account: account, event: other_event, value: "GID-1")).to be_valid
    end

    it "can't back two different participants" do
      participant = create(:participant, account: account, event: event, govt_id: nil)
      create(:govt_id, account: account, event: event, value: "GID-1", participant: participant)

      duplicate_assignment = build(:govt_id, account: account, event: event, value: "GID-2", participant: participant)

      expect(duplicate_assignment).not_to be_valid
    end
  end

  describe ".available / .assigned scopes" do
    it "separates unclaimed pool rows from claimed ones" do
      participant = create(:participant, account: account, event: event, govt_id: nil)
      available = create(:govt_id, account: account, event: event, value: "GID-AVAIL")
      taken = create(:govt_id, account: account, event: event, value: "GID-TAKEN", participant: participant, assigned_at: Time.current)

      expect(GovtId.available).to contain_exactly(available)
      expect(GovtId.assigned).to contain_exactly(taken)
    end
  end

  describe ".assign_to! (new participant claims from an existing pool)" do
    it "claims the oldest available id and writes it onto the participant" do
      participant = create(:participant, account: account, event: event, govt_id: nil)
      older = create(:govt_id, account: account, event: event, value: "GID-OLD", created_at: 1.day.ago)
      create(:govt_id, account: account, event: event, value: "GID-NEW")

      GovtId.assign_to!(participant)

      expect(participant.reload.govt_id).to eq("GID-OLD")
      expect(older.reload.participant_id).to eq(participant.id)
      expect(older.reload.assigned_at).to be_present
    end

    it "does nothing when the pool is empty" do
      participant = create(:participant, account: account, event: event, govt_id: nil)

      expect { GovtId.assign_to!(participant) }.not_to raise_error
      expect(participant.reload.govt_id).to be_nil
    end

    it "does nothing when the participant already has a govt_id" do
      participant = create(:participant, account: account, event: event, govt_id: "ALREADY-SET")
      create(:govt_id, account: account, event: event, value: "GID-1")

      GovtId.assign_to!(participant)

      expect(participant.reload.govt_id).to eq("ALREADY-SET")
      expect(GovtId.available.count).to eq(1) # untouched
    end

    it "never assigns the same pool row to two participants" do
      participant_a = create(:participant, account: account, event: event, govt_id: nil)
      participant_b = create(:participant, account: account, event: event, govt_id: nil)
      create(:govt_id, account: account, event: event, value: "GID-ONLY")

      GovtId.assign_to!(participant_a)
      GovtId.assign_to!(participant_b)

      expect(participant_a.reload.govt_id).to eq("GID-ONLY")
      expect(participant_b.reload.govt_id).to be_nil
    end
  end

  describe ".claim_existing_value! (a manually-entered value happens to be in the pool)" do
    it "marks the matching pool row as consumed by this participant" do
      participant = create(:participant, account: account, event: event, govt_id: "GID-1")
      pool_row = create(:govt_id, account: account, event: event, value: "GID-1")

      GovtId.claim_existing_value!(participant)

      expect(pool_row.reload.participant_id).to eq(participant.id)
    end

    it "does nothing when no pool row matches the value" do
      participant = create(:participant, account: account, event: event, govt_id: "NOT-IN-POOL")

      expect { GovtId.claim_existing_value!(participant) }.not_to raise_error
    end

    it "does nothing when the participant has no govt_id" do
      participant = create(:participant, account: account, event: event, govt_id: nil)
      create(:govt_id, account: account, event: event, value: "GID-1")

      GovtId.claim_existing_value!(participant)

      expect(GovtId.available.count).to eq(1) # untouched
    end
  end

  describe ".backfill_event! (govt IDs uploaded after participants already registered)" do
    it "assigns available ids to existing govt_id-less participants, oldest participant first" do
      older_participant = create(:participant, account: account, event: event, govt_id: nil, created_at: 1.day.ago)
      newer_participant = create(:participant, account: account, event: event, govt_id: nil)
      already_has_one = create(:participant, account: account, event: event, govt_id: "ALREADY-SET")
      create(:govt_id, account: account, event: event, value: "GID-1")

      GovtId.backfill_event!(event)

      expect(older_participant.reload.govt_id).to eq("GID-1")
      expect(newer_participant.reload.govt_id).to be_nil # pool ran out
      expect(already_has_one.reload.govt_id).to eq("ALREADY-SET") # untouched
    end

    it "is scoped to the given event only" do
      other_event = create(:event, account: account)
      participant = create(:participant, account: account, event: other_event, govt_id: nil)
      create(:govt_id, account: account, event: event, value: "GID-1")

      GovtId.backfill_event!(event)

      expect(participant.reload.govt_id).to be_nil
    end
  end
end
