# Stores the Google Maps location URL organizers paste in for on_site/hybrid events — plain
# string, no format validation, since it's just carried through for the future Next.js frontend
# to render a map from (requirement.md doesn't yet spec map rendering, this is the data column
# ahead of that work).
class AddMapUrlToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :map_url, :string
  end
end
