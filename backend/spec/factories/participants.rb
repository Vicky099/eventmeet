FactoryBot.define do
  factory :participant do
    transient do
      # photo/document joined Event::PARTICIPANT_FIELD_CATALOG in the v12 revisit ("add photo and
      # document in the default form") — attached by default (below) so a factory-built
      # participant stays valid regardless of which catalog fields end up effectively required,
      # same reasoning as the other catalog-field defaults. Transient flags, not a bare "attach
      # unless already attached?" check with no opt-out — a handful of specs specifically test the
      # *unattached* fallback behavior (BadgeReformService's $PHOTO$ blank-pixel substitution,
      # Participant's own document-required validation), and those need a real way to say "don't,"
      # not just an explicit `photo: nil` override — has_one_attached's own `photo=` setter does
      # accept nil to mean "detach," but an unconditional after(:build) callback would silently
      # re-attach right past it anyway.
      attach_photo { true }
      attach_document { true }
    end

    association :event
    account { event.account }
    title { "Mr." }
    sequence(:first_name) { |n| "Participant#{n}" }
    last_name { "Test" }
    sequence(:email) { |n| "participant#{n}@example.com" }
    # Phase 7.5 (requirement.md §5.4 v12) — RegistrationForm::BUILTIN_DEFAULT_CATALOG now requires
    # every Event::PARTICIPANT_FIELD_CATALOG entry (title/first_name/last_name/photo/document
    # included as of the v12 revisits that joined them to the catalog itself), not just email, for
    # a ticket_category with no configured form at all — the common case for a factory-built
    # participant, since most specs don't set up a RegistrationForm at all. Filled in here so
    # `create(:participant, ...)` stays valid by default regardless of which catalog fields end up
    # effectively required, the same way ticket_category's own factory already defaults
    # total_count so it's valid whether or not the spec cares about seat limits. contact_num is
    # sequenced, not a fixed literal like the others — it's one of Participant.duplicate_match's
    # own tiers (govt_id -> email+name -> email -> phone), so a fixed value would make every second
    # factory-built participant in the same event collide as a phone-number duplicate the moment
    # two exist together (several specs build several in one event/dashboard-load test).
    sequence(:contact_num) { |n| format("9%09d", n) }
    company { "Acme Inc" }
    department { "Engineering" }
    position { "Manager" }
    nationality { "Indian" }
    country { "India" }

    # after(:build), not just after(:create) — so `build(:participant, ...)` validity checks see
    # them too. Same StringIO-attach pattern already used elsewhere (badge_reform_service_spec.rb,
    # participant_import_job_spec.rb) rather than a real fixture file on disk.
    after(:build) do |participant, evaluator|
      if evaluator.attach_photo && !participant.photo.attached?
        participant.photo.attach(io: StringIO.new("fake photo"), filename: "photo.png", content_type: "image/png")
      end
      if evaluator.attach_document && !participant.document.attached?
        participant.document.attach(io: StringIO.new("fake document"), filename: "document.pdf", content_type: "application/pdf")
      end
    end
  end
end
