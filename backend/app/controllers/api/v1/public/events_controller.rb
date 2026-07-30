module Api
  module V1
    module Public
      # Phase 25 — Public Event Site API (doc/public_event_site_options.md). The one public read
      # endpoint (requirement.md §4.9 item 2's "event show," confirmed in this doc's own plan as a
      # single response, not a second JSON-only endpoint behind it): `content_html` (this event's
      # own EventPage#html, Phase 25.5 — returned exactly as stored, no sentinel, no substitution,
      # no sanitization), `published` (what Next.js branches on for its own default-page fallback —
      # a draft event still resolves here, 200, `published: false`, rather than 404ing), and
      # `registration_schema` (one entry per TicketCategory, the same effective_catalog_fields/
      # custom_fields/uniqueness_fields data the admin manual-entry form already renders from —
      # `<RegistrationForm />`'s data source, no new schema invented for the public site).
      class EventsController < BaseController
        def show
          event = Current.account.events.friendly.find(params[:slug])

          render json: event_show_json(event)
        rescue ActiveRecord::RecordNotFound
          head :not_found
        end

        private

        def event_show_json(event)
          {
            name: event.name,
            description: event.description,
            starts_at: event.starts_at,
            ends_at: event.ends_at,
            address: event.address,
            meeting_link: event.meeting_link,
            published: event.published?,
            content_html: event.event_page&.html,
            seats_remaining: seats_remaining(event),
            registration_schema: event.ticket_categories.map { |ticket_category| ticket_category_json(ticket_category) }
          }
        end

        # nil when nothing on this event tracks capacity at all (every category unlimited) — same
        # "no ceiling to report" reasoning TicketCategory#unlimited? already gives for a single
        # category, just rolled up to the whole event for generateMetadata/a header ticker to show.
        def seats_remaining(event)
          tracked = event.ticket_categories.reject(&:unlimited?)
          return nil if tracked.empty?

          tracked.sum { |ticket_category| ticket_category.remain_count.to_i }
        end

        def ticket_category_json(ticket_category)
          catalog_fields = ticket_category.effective_catalog_fields.merge("first_name" => true)
          ordered_fields = ticket_category.ordered_catalog_fields.select { |field| catalog_fields[field] }

          {
            id: ticket_category.id,
            name: ticket_category.name,
            unlimited: ticket_category.unlimited?,
            total_count: ticket_category.total_count,
            remain_count: ticket_category.remain_count,
            catalog_fields: ordered_fields,
            uniqueness_fields: ticket_category.effective_uniqueness_fields || RegistrationForm::UNIQUENESS_FIELDS,
            custom_fields: (ticket_category.registration_form&.custom_fields || []).map { |custom_field| custom_field_json(custom_field) }
          }
        end

        def custom_field_json(custom_field)
          {
            id: custom_field.id,
            label: custom_field.label,
            field_type: custom_field.field_type,
            options: custom_field.options_list,
            required: custom_field.required
          }
        end
      end
    end
  end
end
