# Shared by Participant and Speaker — both carry the same plain `nationality`/`country`
# `character varying` columns (no enum/FK either side) and both back their Nationality/Country
# form fields with the same fixed, correctly-spelled option list instead of freeform text: the
# `countries` gem's ISO 3166 data.
module HasCountryFields
  extend ActiveSupport::Concern

  class_methods do
    def countries
      ISO3166::Country.all.map { |country| country.common_name.presence || country.iso_short_name }.sort
    end

    # A couple of entries (e.g. Antarctica, Bouvet Island) carry an empty-string `nationality`
    # rather than nil — reject(&:blank?), not just the filter_map compact, or the option list
    # ends up with a second, redundant blank entry alongside the <select>'s own include_blank one.
    def nationalities
      ISO3166::Country.all.filter_map(&:nationality).reject(&:blank?).uniq.sort
    end
  end
end
