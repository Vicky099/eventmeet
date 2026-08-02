# requirement.md revisit (direct user instruction): "Remove template 3 completely. as it is not
# fit with event. and keep the numbering serial again" — mirrors the earlier Template 4 removal
# (db/migrate/20260802153714), but this time an event was actually assigned the template being
# removed (unlike template_4 before, which nothing used), so this can't be a plain enum-key
# deletion: any row on the old `template_3` (integer 2) needs somewhere else to land before that
# value's meaning changes out from under it. Reassigned to the design replacing it in this same
# migration — the old `template_4` (integer 3, "Events Conference") — then that gets renumbered
# down to fill the now-empty `template_3` slot (integer 2), same as template_5→4 did last time.
#
# Two UPDATEs, run in this order, on purpose:
#   1. template_key 2 -> 3   (evacuate the doomed old template_3 rows onto old template_4's slot)
#   2. template_key 3 -> 2   (renumber old template_4, *including the row just moved in step 1*,
#                             down onto the vacated template_3 slot)
# Net effect on a row that started at 2: 2 -> 3 -> 2 — same integer, but now decodes under the new
# enum (template_3: 2 renamed from template_4) as the Events Conference design, not the removed
# nightclub one. A row that started at 3 (old template_4) just rides step 2 alone: 3 -> 2.
class RemoveTemplate3RenumberTemplate4To3 < ActiveRecord::Migration[8.0]
  def up
    execute "UPDATE event_pages SET template_key = 3 WHERE template_key = 2"
    execute "UPDATE event_pages SET template_key = 2 WHERE template_key = 3"
  end

  # Best-effort only: if rows had existed at *both* 2 and 3 before `up` ran, this migration merges
  # them onto the same final value (2), so `down` can't tell which of today's `2`s were originally
  # `2` vs `3` — it restores everything to the old template_4 slot (3), which is correct for the
  # common case (nothing was actually on old template_3 when this ran) but not a lossless inverse
  # in general. Not a concern for this app's actual data at migration time (confirmed: exactly one
  # row, sitting on the value being evacuated).
  def down
    execute "UPDATE event_pages SET template_key = 3 WHERE template_key = 2"
  end
end
