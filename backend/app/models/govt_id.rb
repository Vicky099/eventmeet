# requirement.md revisit: "If we have govt id then we will upload that list this will be stored in
# database somewhere. Then once participant registration start then the government ID will start
# assign to participant. One govt id will be assigned to one participant." AND the reverse: "If we
# already have participant, and then we got the govtIDs then while uploading the govtID it should
# automatically assign to the participant." One pool, fed from either direction — GovtIdImportJob
# populates it (and immediately backfills any already-registered participant still missing a
# govt_id via .backfill_event!), and Participant's own after_create_commit callback
# (#sync_govt_id_with_pool!) claims from it the moment a new participant without one is created.
# Both directions funnel through this class's own methods so there's exactly one place a race
# between two participants claiming the same id can be prevented.
class GovtId < ApplicationRecord
  include TenantScoped

  belongs_to :event
  # optional: nil is the normal "still sitting in the pool, unclaimed" state — not an error state.
  belongs_to :participant, optional: true

  validates :value, presence: true, uniqueness: { scope: :event_id }
  # A pool row can back at most one participant — the DB's own unique index on participant_id
  # (allowing any number of nulls) is the real backstop; this just surfaces it as a normal Rails
  # validation error for the rare direct-assignment path that goes through validations at all
  # (assign_to!/claim_existing_value! below use update_all/update_column specifically to skip
  # them, for the same reason Participant's own pool-sync callback does — see that file).
  validates :participant_id, uniqueness: true, allow_nil: true

  scope :available, -> { where(participant_id: nil) }
  scope :assigned, -> { where.not(participant_id: nil) }

  # The "participant registers, pool already has ids" direction. Silently no-ops (not an error)
  # when the participant already has a govt_id (nothing to assign) or the pool is empty for this
  # event (an event that never uploaded a govt ID list works exactly as it did before this feature
  # existed). FOR UPDATE SKIP LOCKED, not a plain first — two participants being created at the
  # same moment (concurrent manual entries from two admin tabs, or a burst of API-created rows)
  # must never be handed the *same* available row; skipping whatever's already locked lets each
  # transaction grab a *different* one instead of blocking on the other.
  def self.assign_to!(participant)
    return if participant.govt_id.present?

    transaction do
      row = available.where(event_id: participant.event_id).order(:created_at).lock("FOR UPDATE SKIP LOCKED").first
      return unless row

      row.update!(participant_id: participant.id, assigned_at: Time.current)
      # update_column, not update! — this is a bookkeeping write-back onto an already-valid,
      # already-persisted record from a value this table itself just guaranteed unique; running
      # Participant's full validation/callback chain again here would be redundant at best (and
      # at worst re-triggers e.g. the registration-confirmation email for a row that already sent
      # one on its own creation).
      participant.update_column(:govt_id, row.value)
    end
  end

  # The reverse direction: a participant already has a govt_id (typed in manually, or supplied by
  # Participant Import's own "Govt ID" column) that happens to match a value sitting unclaimed in
  # this event's pool. Marks that pool row consumed so a later #assign_to!/.backfill_event! can
  # never hand the same value out a second time. A plain conditional UPDATE (not a SELECT+lock) is
  # enough — GovtId's own (event_id, value) uniqueness means at most one row can ever match.
  def self.claim_existing_value!(participant)
    return if participant.govt_id.blank?

    available.where(event_id: participant.event_id, value: participant.govt_id)
      .update_all(participant_id: participant.id, assigned_at: Time.current)
  end

  # The "govt ids uploaded after participants already registered" direction — GovtIdImportJob
  # calls this once per batch, after the new rows are in. Oldest participant first (registration
  # order, not upload order): whoever registered first is fairest to hand an id to first once
  # supply catches up with demand.
  def self.backfill_event!(event)
    event.participants.where(govt_id: [ nil, "" ]).order(:created_at).find_each { |participant| assign_to!(participant) }
  end
end
