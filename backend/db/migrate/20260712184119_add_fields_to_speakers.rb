# Speaker gap-fill against the reference event_management system's field list.
class AddFieldsToSpeakers < ActiveRecord::Migration[8.0]
  def change
    add_column :speakers, :country, :string
    add_column :speakers, :nationality, :string
    add_column :speakers, :contact_num, :string
    add_column :speakers, :email, :string
    add_column :speakers, :company_details, :text
  end
end
