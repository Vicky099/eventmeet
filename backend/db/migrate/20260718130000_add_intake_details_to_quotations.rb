# Confirmed with the user: "when super admin receive the quotation, he don't know about no of
# participants and other requests such as invitation sent by email or whatsapp or both and
# support." The Super Admin was pricing blind — this is what the tenant fills in on the request
# form (Admin::QuotationsController#new/#create) so the amount sent back actually reflects the
# real ask. `additional_notes` is a free-text catch-all for anything not itemized below.
class AddIntakeDetailsToQuotations < ActiveRecord::Migration[8.0]
  def change
    add_column :quotations, :expected_participant_count, :integer
    add_column :quotations, :invite_via_email, :boolean, null: false, default: true
    add_column :quotations, :invite_via_whatsapp, :boolean, null: false, default: false
    add_column :quotations, :support_requested, :boolean, null: false, default: false
    add_column :quotations, :additional_notes, :text
  end
end
