# Phase 4 (requirement.md §5.1 new item): per-event staff assignment — data model only, no
# assignment UI yet (a later phase adds it). See Event#assigned_staff / #event_staff_assignments.
class EventStaffAssignment < ApplicationRecord
  include TenantScoped

  belongs_to :event
  belongs_to :user

  validates :user_id, uniqueness: { scope: :event_id }
end
