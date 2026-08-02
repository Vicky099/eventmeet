# requirement.md revisit (direct user instruction): "keep the template number in serial. 1,2,3,4"
# — after the old Template 4 (auction/marketplace design) was removed entirely with no data to
# migrate (nothing was ever assigned it), this app's own former Template 5 was renumbered down to
# Template 4 (EventPage#template_key's own enum: template_4: 3, was template_5: 4) to close the
# gap. Rails enums store the raw integer, not the symbol, so any row already holding the old value
# 4 needs updating in place or it becomes an unmapped integer the moment the model reloads with
# the new enum — reversible the same way, back to 4.
class RenumberEventPageTemplate5To4 < ActiveRecord::Migration[8.0]
  def up
    execute "UPDATE event_pages SET template_key = 3 WHERE template_key = 4"
  end

  def down
    execute "UPDATE event_pages SET template_key = 4 WHERE template_key = 3"
  end
end
