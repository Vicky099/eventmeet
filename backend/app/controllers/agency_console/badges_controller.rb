module AgencyConsole
  # #show's own Badges card (AgencyConsole::EventsController#show) — the eye-icon preview modal's
  # iframe target, this console's own copy of Admin::BadgesController#preview (same "own copy"
  # pattern AgencyConsole::DirectUploadsController already takes on Admin::DirectUploadsController's
  # route). Always sample-participant data, never a real one — there's no participant_id path here
  # the way the tenant-side action has, since this namespace has no participant roster to pick from
  # at all. Everything (account/event/badge lookups, the background_image blob read) runs inside
  # Event.unscoped_across_tenants — same trap AgencyConsole::EventsController#show's own comment
  # already found: TenantScoped's default_scope has no Current.account to recognize here.
  class BadgesController < BaseController
    def preview
      @account = Current.agency.accounts.find(params[:account_id])

      Event.unscoped_across_tenants do
        event = @account.events.friendly.find(params[:event_id])
        badge = event.badges.find(params[:id])
        content = BadgeReformService.render(badge: badge, participant: sample_participant(event), sample: true)
        render html: wrap_preview_html(badge, content).html_safe
      end
    end

    private

    # Same synthetic, never-persisted Participant Admin::BadgesController#preview builds — a
    # plausible value for every field a badge's $OTHER1$/$OTHER2$/$OTHER3$ mapping could point at,
    # never touching the DB.
    def sample_participant(event)
      Participant.new(
        event: event, name: "Sample Participant", title: "Mr.", first_name: "Sample", last_name: "Participant",
        email: "sample.participant@example.com",
        contact_num: "+1 555 0100", company: "Acme Corp", department: "Engineering",
        position: "Attendee", nationality: "Sample", country: "Sampleland",
        govt_id: "SAMPLE-GOVT-ID", rf_id: "SAMPLE-RFID", client_participant_id: "SAMPLE-001",
        hex_id: "SAMPLE-HEX-ID"
      )
    end

    # Same shape as Admin::BadgesController#wrap_preview_html/BadgePdfService's own wrap_html —
    # real CSS "cm" units (not a px conversion) so this is a true "what would print" answer, and
    # `position: relative` on body so the badge's own absolutely-positioned token blocks have a
    # positioned ancestor to anchor to.
    def wrap_preview_html(badge, fragment)
      <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="utf-8">
            <style>
              html, body { margin: 0; padding: 0; }
              body { position: relative; width: #{badge.width_cm}cm; height: #{badge.height_cm}cm; overflow: hidden; #{background_style(badge)} }
            </style>
          </head>
          <body>#{fragment}</body>
        </html>
      HTML
    end

    def background_style(badge)
      data_uri = badge.background_image_data_uri
      return "" unless data_uri

      "background-image:url(#{data_uri});background-size:cover;background-position:center;"
    end
  end
end
