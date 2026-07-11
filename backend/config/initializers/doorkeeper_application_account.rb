# frozen_string_literal: true

# requirement.md §4.9 item 4: one Doorkeeper::Application per Account, auto-created by the Super
# Admin at tenant-provisioning time (Phase 2, app/services/account_provisioning.rb). Doorkeeper's
# own Application model has no notion of a tenant — reopening it here (rather than generating a
# subclass and pointing `Doorkeeper.configure { application_class }` at it) keeps every existing
# Doorkeeper internal reference (access grants/tokens, the token endpoint) pointed at the one real
# class, since none of those go through a custom subclass. `to_prepare` re-runs this on every
# class reload in development, the same way Rails expects gem-model reopening to be done.
Rails.application.config.to_prepare do
  Doorkeeper::Application.belongs_to :account
end
