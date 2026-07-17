class AddUniquenessFieldsToRegistrationForms < ActiveRecord::Migration[8.0]
  def change
    add_column :registration_forms, :uniqueness_fields, :jsonb, null: false, default: []
  end
end
