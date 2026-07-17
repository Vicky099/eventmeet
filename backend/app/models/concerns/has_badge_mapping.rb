# Phase 8 — Badge Design & Printing (requirement.md §3.6). Shared between Badge and BadgeTemplate
# — both carry the same `content`/`mapping`/`output_type`/size shape (a Badge is just a
# per-event, editable-independently copy of a BadgeTemplate). `mapping` is how the generic
# $OTHER1$/$OTHER2$/$OTHER3$ tokens (requirement.md §3.6) become meaningful: an organizer picks
# which Participant attribute each slot actually shows, from a fixed allowlist rather than an
# arbitrary method name — BadgeReformService only ever calls `participant.public_send` against a
# key that passed this validation.
module HasBadgeMapping
  extend ActiveSupport::Concern

  MAPPABLE_FIELDS = %w[
    name title first_name last_name email contact_num company department position nationality country
    govt_id rf_id client_participant_id hex_id
  ].freeze

  OTHER_TOKEN_KEYS = %w[OTHER1 OTHER2 OTHER3].freeze

  included do
    enum :output_type, { badge: 0, wristband: 1 }

    validates :name, presence: true
    validates :content, presence: true
    validates :width_cm, :height_cm, numericality: { greater_than: 0 }
    # The editor's "(unused)" option (app/views/admin/shared/_badge_editor.html.erb) submits an
    # empty string for a slot the organizer deliberately left unmapped — strip those out before
    # validating rather than treating a blank value as "mapped to an unknown field."
    before_validation :drop_blank_mapping_values
    validate :mapping_keys_and_values_are_known
  end

  # Both Badge and BadgeTemplate declare `has_one_attached :background_image` themselves (not
  # this concern, since neither needs the other attachment-related bits centralized) — this is
  # just the one piece of logic every consumer of that attachment needs identically: a base64
  # `data:` URI, self-contained enough to survive being embedded into a standalone render with no
  # session/auth context of its own (BadgePdfService's Grover/Puppeteer call, Admin::BadgesController
  # #preview's iframe document) — a plain `rails_blob_path`/`_url` would work in an ordinary
  # browser tab but not in either of those.
  def background_image_data_uri
    return nil unless background_image.attached?

    data = Base64.strict_encode64(background_image.download)
    "data:#{background_image.blob.content_type};base64,#{data}"
  end

  private

  def drop_blank_mapping_values
    return if mapping.blank?

    self.mapping = mapping.reject { |_key, value| value.blank? }
  end

  def mapping_keys_and_values_are_known
    return if mapping.blank?

    mapping.each do |key, value|
      unless OTHER_TOKEN_KEYS.include?(key)
        errors.add(:mapping, "has an unknown token key: #{key}")
        next
      end
      errors.add(:mapping, "maps #{key} to an unknown field: #{value}") unless MAPPABLE_FIELDS.include?(value)
    end
  end
end
