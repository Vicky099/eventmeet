require "rails_helper"

RSpec.describe Event, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }

  before { Current.account = account }

  it "is valid with the factory defaults" do
    expect(build(:event, account: account)).to be_valid
  end

  it "requires a name" do
    event = build(:event, account: account, name: nil)
    expect(event).not_to be_valid
    expect(event.errors[:name]).to be_present
  end

  it "requires ends_at to be after starts_at" do
    event = build(:event, account: account, starts_at: 2.days.from_now, ends_at: 1.day.from_now)
    expect(event).not_to be_valid
    expect(event.errors[:ends_at]).to be_present
  end

  # Basic Info mandatory fields (requirement.md UI note): on-site needs Address AND a Google
  # Maps link; virtual needs a meeting link; hybrid needs all three.
  describe "mode-dependent location presence" do
    it "requires address and map_url for on_site" do
      event = build(:event, account: account, mode: :on_site, address: nil, map_url: nil, meeting_link: nil)
      expect(event).not_to be_valid
      expect(event.errors[:address]).to be_present
      expect(event.errors[:map_url]).to be_present
    end

    it "requires meeting_link for virtual, and does not require address/map_url" do
      event = build(:event, account: account, mode: :virtual, address: nil, map_url: nil, meeting_link: nil)
      expect(event).not_to be_valid
      expect(event.errors[:meeting_link]).to be_present
      expect(event.errors[:address]).to be_empty
      expect(event.errors[:map_url]).to be_empty
    end

    it "requires address, map_url, and meeting_link for hybrid" do
      event = build(:event, account: account, mode: :hybrid, address: nil, map_url: nil, meeting_link: nil)
      expect(event).not_to be_valid
      expect(event.errors[:address]).to be_present
      expect(event.errors[:map_url]).to be_present
      expect(event.errors[:meeting_link]).to be_present
    end

    it "is valid for virtual with only a meeting_link" do
      event = build(:event, account: account, mode: :virtual, address: nil, map_url: nil, meeting_link: "https://example.com/room")
      expect(event).to be_valid
    end

    it "is valid for on_site with both address and map_url present" do
      event = build(:event, account: account, mode: :on_site, address: "123 Main St", map_url: "https://maps.google.com/?q=123")
      expect(event).to be_valid
    end
  end

  describe "slug (friendly_id, scoped per account)" do
    it "generates a slug from the name on create" do
      event = create(:event, account: account, name: "Annual Meetup")
      expect(event.slug).to eq("annual-meetup")
    end

    it "allows the same slug to be reused by a different account" do
      other_account = create(:account)
      create(:event, account: account, name: "Annual Meetup")

      Current.account = other_account
      other_event = create(:event, account: other_account, name: "Annual Meetup")

      expect(other_event.slug).to eq("annual-meetup")
    end

    it "disambiguates a second event with the same name within the same account" do
      create(:event, account: account, name: "Annual Meetup")
      second = create(:event, account: account, name: "Annual Meetup")

      expect(second.slug).not_to eq("annual-meetup")
      expect(second.slug).to start_with("annual-meetup")
    end
  end

  describe "participant_fields jsonb round-trip" do
    it "persists and reloads an arbitrary hash" do
      event = create(:event, account: account, participant_fields: { "email" => true, "company" => false })
      expect(event.reload.participant_fields).to eq({ "email" => true, "company" => false })
    end

    it "defaults to an empty hash" do
      event = create(:event, account: account)
      expect(event.participant_fields).to eq({})
    end
  end

  describe "#basic_info_complete?" do
    it "is false when required fields are missing" do
      event = build(:event, account: account, name: nil)
      expect(event.basic_info_complete?).to be false
    end

    it "is true once name, dates, and mode-appropriate location are all present" do
      event = build(:event, account: account, mode: :on_site, address: "123 Main St")
      expect(event.basic_info_complete?).to be true
    end

    it "is false for a virtual event with only an address, no meeting_link" do
      event = build(:event, account: account, mode: :virtual, address: "123 Main St", meeting_link: nil)
      expect(event.basic_info_complete?).to be false
    end

    it "is false for an on_site event with an address but no map_url" do
      event = build(:event, account: account, mode: :on_site, address: "123 Main St", map_url: nil)
      expect(event.basic_info_complete?).to be false
    end
  end

  # Wizard stepper's green-checkmark state (app/views/admin/events/edit.html.erb).
  describe "#step_complete?" do
    it "delegates basic_info to #basic_info_complete?" do
      complete = build(:event, account: account, mode: :on_site, address: "123 Main St")
      incomplete = build(:event, account: account, name: nil)

      expect(complete.step_complete?("basic_info")).to be true
      expect(incomplete.step_complete?("basic_info")).to be false
    end

    it "is false for sessions/speaker/event_schedule/tickets/badge with nothing created yet" do
      event = create(:event, account: account)

      expect(event.step_complete?("sessions")).to be false
      expect(event.step_complete?("speaker")).to be false
      expect(event.step_complete?("event_schedule")).to be false
      expect(event.step_complete?("tickets")).to be false
      expect(event.step_complete?("badge")).to be false
    end

    it "is true for sessions/speaker/event_schedule/tickets/badge once at least one row exists" do
      event = create(:event, account: account)
      create(:session, account: account, event: event)
      create(:speaker, account: account, event: event)
      create(:schedule, account: account, event: event)
      create(:ticket_category, account: account, event: event)
      create(:badge, account: account, event: event)

      expect(event.step_complete?("sessions")).to be true
      expect(event.step_complete?("speaker")).to be true
      expect(event.step_complete?("event_schedule")).to be true
      expect(event.step_complete?("tickets")).to be true
      expect(event.step_complete?("badge")).to be true
    end

    it "treats review as complete only once the event is published" do
      event = create(:event, account: account, starts_at: 1.day.from_now, ends_at: 2.days.from_now)
      expect(event.step_complete?("review")).to be false

      event.publish!

      expect(event.step_complete?("review")).to be true
    end

    it "is false for an unrecognized step" do
      event = create(:event, account: account)
      expect(event.step_complete?("nonexistent")).to be false
    end
  end

  describe "status enum" do
    it "defaults to draft" do
      expect(create(:event, account: account).status).to eq("draft")
    end

    it "exposes the full lifecycle" do
      expect(Event.statuses.keys).to eq(%w[draft up_coming live completed])
    end
  end

  describe "#publish!" do
    it "sets published_at and computes status from the schedule" do
      event = create(:event, account: account, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)

      event.publish!

      expect(event.published?).to be true
      expect(event.status).to eq("live")
    end

    it "leaves an unpublished event as draft" do
      event = create(:event, account: account)
      expect(event.published?).to be false
    end
  end

  describe "reverting to draft when a published event's content changes" do
    it "clears published_at and resets status to draft on a content-field edit" do
      event = create(:event, account: account, starts_at: 1.day.from_now, ends_at: 2.days.from_now)
      event.publish!
      expect(event.status).to eq("up_coming")

      event.update!(name: "Renamed After Publish")

      expect(event.published?).to be false
      expect(event.status).to eq("draft")
    end

    it "does not revert on a status-only write (EventSchedulerJob's own update)" do
      event = create(:event, account: account, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      event.publish!

      event.update!(status: :completed)

      expect(event.published?).to be true
      expect(event.status).to eq("completed")
    end

    it "does not revert an event that was never published" do
      event = create(:event, account: account)

      event.update!(name: "Still Draft")

      expect(event.published?).to be false
      expect(event.status).to eq("draft")
    end

    # Basic Info gap-fill: description/is_paid/send_registration_email are edited on the same
    # step as name/mode/etc, so they revert a published event to draft on edit the same way.
    it "reverts on an edit to the new Basic Info gap-fill fields too" do
      event = create(:event, account: account, starts_at: 1.day.from_now, ends_at: 2.days.from_now)
      event.publish!

      event.update!(description: "New description")
      expect(event.status).to eq("draft")

      event.publish!
      event.update!(is_paid: true)
      expect(event.status).to eq("draft")

      event.publish!
      event.update!(send_registration_email: true)
      expect(event.status).to eq("draft")
    end
  end

  describe "approval_status enum" do
    it "defaults to unsubmitted, with no submitted_at until explicitly submitted" do
      event = create(:event, account: account)

      expect(event.approval_status).to eq("unsubmitted")
      expect(event.submitted_at).to be_nil
    end

    it "only enters pending (and so the review queue) via an explicit submit_for_review!" do
      event = create(:event, account: account)

      event.submit_for_review!

      expect(event.approval_status).to eq("pending")
      expect(event.submitted_at).to be_present
    end
  end

  describe "#approve!" do
    it "sets approval_status, approved_by, and approved_at" do
      event = create(:event, account: account)
      staff = create(:user, :platform_staff)

      event.approve!(by: staff)

      expect(event.approval_status).to eq("approved")
      expect(event.approved_by).to eq(staff)
      expect(event.approved_at).to be_present
    end

    it "is not reverted by a later content edit (requirement.md §5.2 v8 re-approval-on-edit)" do
      event = create(:event, account: account)
      event.approve!(by: create(:user, :platform_staff))

      event.update!(name: "Renamed After Approval")

      expect(event.reload.approval_status).to eq("approved")
    end

    it "does not publish the event — that's the tenant's own subsequent manual step" do
      event = create(:event, account: account, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      expect(event.published?).to be false

      event.approve!(by: create(:user, :platform_staff))

      expect(event.published?).to be false
      expect(event.status).to eq("draft")
    end
  end

  describe "#reject!" do
    it "requires a reason and sets rejection_reason" do
      event = create(:event, account: account)

      event.reject!(reason: "Missing venue details")

      expect(event.approval_status).to eq("rejected")
      expect(event.rejection_reason).to eq("Missing venue details")
    end

    it "is invalid without a rejection_reason" do
      event = build(:event, account: account, approval_status: :rejected, rejection_reason: nil)
      expect(event).not_to be_valid
      expect(event.errors[:rejection_reason]).to be_present
    end
  end

  describe "#submit_for_review!" do
    it "resets a rejected event back to pending and clears the previous review" do
      event = create(:event, account: account)
      event.reject!(reason: "Fix the schedule")

      event.submit_for_review!

      expect(event.approval_status).to eq("pending")
      expect(event.rejection_reason).to be_nil
      expect(event.approved_by).to be_nil
      expect(event.approved_at).to be_nil
    end

    it "refreshes submitted_at on a resubmit, not just the first submission" do
      event = create(:event, account: account)
      event.submit_for_review!
      first_submitted_at = event.submitted_at
      event.reject!(reason: "Fix the schedule")

      travel_to(1.day.from_now) { event.submit_for_review! }

      expect(event.submitted_at).to be > first_submitted_at
    end
  end

  it "walks the full unsubmitted -> pending -> rejected -> resubmitted -> approved review cycle" do
    event = create(:event, account: account)
    staff = create(:user, :platform_staff)
    expect(event.approval_status).to eq("unsubmitted")

    event.submit_for_review!
    expect(event.approval_status).to eq("pending")

    event.reject!(reason: "Fix the schedule")
    expect(event.approval_status).to eq("rejected")
    expect(event.rejection_reason).to eq("Fix the schedule")

    event.submit_for_review!
    expect(event.approval_status).to eq("pending")
    expect(event.rejection_reason).to be_nil

    event.approve!(by: staff)
    expect(event.approval_status).to eq("approved")
    expect(event.approved_by).to eq(staff)
  end

  describe "#review_sla_at_risk?" do
    it "is false well within the 24h SLA" do
      event = create(:event, :pending_review, account: account, submitted_at: 1.hour.ago)
      expect(event.review_sla_at_risk?).to be false
    end

    it "is true once within the warning window of the 24h SLA" do
      event = create(:event, :pending_review, account: account, submitted_at: 21.hours.ago)
      expect(event.review_sla_at_risk?).to be true
    end

    it "is true once the SLA has been breached outright" do
      event = create(:event, :pending_review, account: account, submitted_at: 25.hours.ago)
      expect(event.review_sla_at_risk?).to be true
    end

    it "is false when never submitted, regardless of how stale the record is" do
      event = create(:event, account: account)
      expect(event.review_sla_at_risk?).to be false
    end

    it "is false once no longer pending, regardless of how long ago it was submitted" do
      event = create(:event, :pending_review, account: account, submitted_at: 30.hours.ago)
      event.approve!(by: create(:user, :platform_staff))

      expect(event.review_sla_at_risk?).to be false
    end
  end

  describe "#clear_seat_limit_unless_flagged" do
    it "discards a stale seat_limit when has_seat_limit is false" do
      event = create(:event, account: account, has_seat_limit: true, seat_limit: 50)

      event.assign_attributes(has_seat_limit: false)
      event.valid?

      expect(event.seat_limit).to be_nil
    end

    it "leaves seat_limit untouched when has_seat_limit is true" do
      event = create(:event, account: account, has_seat_limit: true, seat_limit: 50)

      event.valid?

      expect(event.seat_limit).to eq(50)
    end
  end

  describe "#clear_category_total_counts_unless_seat_limited" do
    it "discards every category's total_count when has_seat_limit turns off" do
      event = create(:event, account: account, has_seat_limit: true, seat_limit: 100)
      category = create(:ticket_category, account: account, event: event, total_count: 60)
      event.reload

      event.assign_attributes(has_seat_limit: false)
      event.valid?

      # Reads back through the same in-memory association the callback actually mutated — not the
      # standalone `category` variable (a separate Ruby object for the same DB row) and not a
      # reload (which would just re-fetch the still-unpersisted-change DB value). Same reasoning
      # as ticket_categories_within_seat_limit's own spec, above.
      expect(event.ticket_categories.find { |c| c.id == category.id }.total_count).to be_nil
    end

    it "leaves categories' total_count untouched when has_seat_limit stays on" do
      event = create(:event, account: account, has_seat_limit: true, seat_limit: 100)
      category = create(:ticket_category, account: account, event: event, total_count: 60)
      event.reload

      event.valid?

      expect(event.ticket_categories.find { |c| c.id == category.id }.total_count).to eq(60)
    end

    it "also clears a brand-new category built in the same save, not just already-persisted ones" do
      event = create(:event, account: account, has_seat_limit: false)
      event.ticket_categories.build(account: account, name: "General", total_count: 60)

      event.valid?

      expect(event.ticket_categories.first.total_count).to be_nil
    end
  end

  describe "seat_limit presence" do
    it "is required once has_seat_limit is toggled on" do
      event = build(:event, account: account, has_seat_limit: true, seat_limit: nil)

      expect(event).not_to be_valid
      expect(event.errors[:seat_limit]).to be_present
    end

    it "is not required when has_seat_limit is off" do
      event = build(:event, account: account, has_seat_limit: false, seat_limit: nil)

      expect(event).to be_valid
    end
  end

  describe "#destroyed_categories_have_no_participants" do
    it "rejects marking a category with existing participants for destruction" do
      event = create(:event, account: account)
      category = create(:ticket_category, account: account, event: event)
      create(:participant, account: account, event: event, ticket_category: category)
      event.reload

      # Mirrors the real Tickets-step flow (same reasoning as
      # "accounts for a category's newly-edited value", above) — mutates the association's own
      # loaded in-memory record, not a separately-queried `.first`, which is what
      # #destroyed_categories_have_no_participants actually iterates.
      event.assign_attributes(ticket_categories_attributes: { "0" => { id: category.id, _destroy: "1" } })

      expect(event).not_to be_valid
      expect(event.errors[:base].first).to include("participants are already registered")
    end

    it "allows marking a category with no participants for destruction" do
      event = create(:event, account: account)
      category = create(:ticket_category, account: account, event: event)
      event.reload

      event.assign_attributes(ticket_categories_attributes: { "0" => { id: category.id, _destroy: "1" } })

      expect(event).to be_valid
    end
  end

  describe "#ticket_categories_within_seat_limit (requirement.md §5.3)" do
    it "allows any combined total when the event has no seat_limit" do
      event = create(:event, account: account, seat_limit: nil)
      event.ticket_categories.build(account: account, name: "General", total_count: 1_000)

      expect(event).to be_valid
    end

    it "rejects a single new category that alone exceeds the seat_limit" do
      event = create(:event, account: account, seat_limit: 50)
      event.ticket_categories.build(account: account, name: "General", total_count: 51)

      expect(event).not_to be_valid
      expect(event.errors[:seat_limit]).to be_present
    end

    # The exact bug reported live: seat_limit 100, three brand-new categories totalling 150 in
    # one save — none exceeds 100 alone, only their sum does. The old (removed)
    # TicketCategory-level validation missed this entirely: each new row queried the database for
    # "other categories' total," which was 0 for all three since none of them existed yet.
    it "rejects several brand-new categories submitted together whose combined total exceeds the seat_limit, even though none exceeds it alone" do
      event = create(:event, account: account, seat_limit: 100)
      event.ticket_categories.build(account: account, name: "General", total_count: 60)
      event.ticket_categories.build(account: account, name: "VIP", total_count: 50)
      event.ticket_categories.build(account: account, name: "Press", total_count: 40)

      expect(event).not_to be_valid
      expect(event.errors[:seat_limit].first).to include("150")
    end

    it "allows several brand-new categories submitted together when their combined total fits" do
      event = create(:event, account: account, seat_limit: 100)
      event.ticket_categories.build(account: account, name: "General", total_count: 60)
      event.ticket_categories.build(account: account, name: "VIP", total_count: 40)

      expect(event).to be_valid
    end

    it "accounts for a category's newly-edited value, not its stale persisted one" do
      event = create(:event, account: account, seat_limit: 50)
      category = create(:ticket_category, account: account, event: event, total_count: 50)
      # Creating the category via a separate factory call, above, doesn't touch `event`'s own
      # in-memory `ticket_categories` — and `create(:event, ...)` already triggered this very
      # validation once (during its own save), which caches an empty association on `event` right
      # then. Reload to match what the real flow actually looks like: Admin::EventsController's
      # `set_event` does a fresh `Event.friendly.find` every request, so nested attributes always
      # assign against an unloaded (or already-current) association, never a stale cached one.
      event.reload

      # Mirrors the real Tickets-step flow (Admin::EventsController#update ->
      # event.assign_attributes(ticket_categories_attributes: ...)) — accepts_nested_attributes_for
      # finds the existing category by :id and mutates it *within* the event's own loaded
      # `ticket_categories` association, which is what the validation actually reads. Reassigning
      # a standalone `category` variable's attribute wouldn't touch that same in-memory copy.
      event.assign_attributes(ticket_categories_attributes: { "0" => { id: category.id, total_count: 45 } })
      expect(event).to be_valid

      event.assign_attributes(ticket_categories_attributes: { "0" => { id: category.id, total_count: 51 } })
      expect(event).not_to be_valid
    end

    it "ignores a category marked for destruction in the same save" do
      event = create(:event, account: account, seat_limit: 50)
      category = create(:ticket_category, account: account, event: event, total_count: 50)
      event.reload # see the comment above — avoids validating against a stale cached association

      event.ticket_categories.build(account: account, name: "General", total_count: 40)
      event.ticket_categories.find { |c| c.id == category.id }.mark_for_destruction

      expect(event).to be_valid
    end
  end

  describe "#badge_for / #badge_for_category (requirement.md §5.5)" do
    it "returns nil when no badges exist" do
      event = create(:event, account: account)
      participant = create(:participant, account: account, event: event)

      expect(event.badge_for(participant)).to be_nil
      expect(event.badge_for_category(nil)).to be_nil
    end

    it "prefers a category-specific badge over the event's default" do
      event = create(:event, account: account)
      category = create(:ticket_category, account: account, event: event)
      default_badge = create(:badge, account: account, event: event, ticket_category: nil)
      category_badge = create(:badge, account: account, event: event, ticket_category: category)
      participant = create(:participant, account: account, event: event, ticket_category: category)

      expect(event.badge_for(participant)).to eq(category_badge)
      expect(event.badge_for_category(category)).to eq(category_badge)
      expect(default_badge).to be_persisted # sanity: the default exists but isn't the one picked
    end

    it "falls back to the event's default badge when the category has none of its own" do
      event = create(:event, account: account)
      category = create(:ticket_category, account: account, event: event)
      default_badge = create(:badge, account: account, event: event, ticket_category: nil)
      participant = create(:participant, account: account, event: event, ticket_category: category)

      expect(event.badge_for(participant)).to eq(default_badge)
      expect(event.badge_for_category(category)).to eq(default_badge)
    end

    it "badge_for_category resolves the default badge for a nil category" do
      event = create(:event, account: account)
      default_badge = create(:badge, account: account, event: event, ticket_category: nil)

      expect(event.badge_for_category(nil)).to eq(default_badge)
    end
  end

  # Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6, confirmed with the
  # user): "one quotation -> one event" — every event now requires an approved, not-yet-consumed
  # Quotation on the same account; there are no plan tiers left to distinguish.
  describe "quotation_must_be_approved_and_available" do
    let(:tenant_user) { create(:user) }

    it "blocks creation with no quotation at all" do
      event = build(:event, account: account, quotation: nil)

      expect(event).not_to be_valid
      expect(event.errors[:quotation]).to be_present
    end

    it "blocks creation against a quotation that hasn't been approved yet" do
      quotation = create(:quotation, :sent, account: account, requested_by: tenant_user)
      event = build(:event, account: account, quotation: quotation)

      expect(event).not_to be_valid
      expect(event.errors[:quotation_id]).to be_present
    end

    it "blocks creation against another account's quotation" do
      other_account = create(:account)
      Current.account = other_account
      quotation = create(:quotation, :approved, account: other_account, requested_by: create(:user))
      Current.account = account

      event = build(:event, account: account, quotation: quotation)

      expect(event).not_to be_valid
      expect(event.errors[:quotation_id]).to be_present
    end

    it "unblocks creation immediately once the quotation is approved" do
      quotation = create(:quotation, :approved, account: account, requested_by: tenant_user)
      event = build(:event, account: account, quotation: quotation)

      expect(event).to be_valid
    end

    it "blocks a second event from consuming an already-used quotation" do
      quotation = create(:quotation, :approved, account: account, requested_by: tenant_user)
      create(:event, account: account, quotation: quotation)

      second_event = build(:event, account: account, quotation: quotation)

      expect(second_event).not_to be_valid
      expect(second_event.errors[:quotation_id]).to be_present
    end
  end

  # Phase 0's tenant_scoped_spec.rb: "copy this shape for every real TenantScoped model starting
  # with Event in Phase 4" — same assertions, this time against the real model instead of an
  # anonymous stand-in.
  describe "tenant isolation (requirement.md §4.2)" do
    let(:account_a) { create(:account) }
    let(:account_b) { create(:account) }

    before do
      Current.account = account_a
      create(:event, account: account_a, name: "Account A Event")
      Current.account = account_b
      create(:event, account: account_b, name: "Account B Event")
    end

    it "never returns another tenant's events" do
      Current.account = account_a

      expect(Event.count).to eq(1)
      expect(Event.first.account_id).to eq(account_a.id)
    end

    it "raises with no Current.account and no Current.platform_request set" do
      Current.account = nil

      expect { Event.count }.to raise_error(TenantScoped::MissingTenantContextError)
    end

    it "opens up to every tenant's events under Current.platform_request" do
      Current.account = nil
      Current.platform_request = true

      expect(Event.count).to eq(2)
    end
  end
end
