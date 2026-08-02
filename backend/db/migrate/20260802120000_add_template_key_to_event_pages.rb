# doc/event_page_templates_plan.md, Stage 1 — nullable, no default: nil keeps meaning exactly
# what it means for every existing row today, "Custom HTML" (EventPage#html), not a new state.
class AddTemplateKeyToEventPages < ActiveRecord::Migration[8.0]
  def change
    add_column :event_pages, :template_key, :integer
  end
end
