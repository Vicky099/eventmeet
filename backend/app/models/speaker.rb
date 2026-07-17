# Event-scoped — one speaker roster per event, not shared across events (confirmed with user,
# reversing Phase 11's original "account-wide reusable library" design). Same event-scoped shape
# Session/Schedule already have.
class Speaker < ApplicationRecord
  include TenantScoped
  include TenantScopedAttachment
  include HasCountryFields

  belongs_to :event
  has_one_attached :photo
  # restrict_with_error, not destroy — a speaker's talk history is real agenda content, not
  # disposable metadata; same "protect scan/attendance history" reasoning
  # Participant#scan_events/#attendances already established for a different kind of history.
  has_many :schedules, dependent: :restrict_with_error

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  def attach_photo(uploaded_file)
    attach_tenant_scoped(:photo, uploaded_file, "speakers", :photo)
  end
end
