module Api
  module V1
    module Public
      # Phase 25 — Public Event Site API (doc/public_event_site_options.md, requirement.md §4.9
      # item 2's "register participant"). Reuses exactly the same Participant validations/
      # callbacks the Admin Console's own manual-entry form already goes through
      # (Admin::ParticipantsController#create) — dedupe (Participant#not_a_duplicate),
      # required-field enforcement (TicketCategory#effective_catalog_fields/required custom
      # fields), approval-gated status (Event#default_participant_status), the confirmation email
      # (Participant's own after_create_commit) — no rules re-implemented here. The one thing this
      # controller adds that the admin form doesn't need: a hard per-category capacity check (see
      # #capacity_exhausted? below) — self-registration has to reject once a category is full;
      # manual admin entry never had to.
      class ParticipantsController < BaseController
        def create
          event = Current.account.events.friendly.find(params[:slug])
          ticket_category = event.ticket_categories.find(participant_params[:ticket_category_id])

          if capacity_exhausted?(event, ticket_category)
            render json: { error: "sold_out", message: "#{ticket_category.name} is sold out." }, status: :unprocessable_content
            return
          end

          participant = event.participants.build(fixed_field_params.merge(source: :client_api, status: event.default_participant_status))
          apply_uploads(participant)

          if participant.save
            # `hex_id` included so the Next.js BFF can build a download link for #invitation below
            # immediately after a successful registration, with no session/lookup round-trip of
            # its own — same globally-unique, already-public-facing token
            # Participant#find_by_identifier/QR-scanning already treat as sufficient to identify
            # one participant (see that method's own comment), not a new trust decision.
            render json: { id: participant.id, status: participant.status, hex_id: participant.hex_id }, status: :created
          else
            render json: { error: "validation_failed", errors: participant.errors.to_hash(full_messages: true) }, status: :unprocessable_content
          end
        rescue ActiveRecord::RecordNotFound
          head :not_found
        end

        # requirement.md revisit: "post registration show ... a download button. That button will
        # download the invitation PDF, which we are sending when we register participant" — the
        # exact same PDF `ParticipantMailer#confirmation` already attaches to the confirmation
        # email (`RegistrationPdfService`-rendered HTML, `registration-#{hex_id}.pdf`), just never
        # previously retrievable outside that one email send. Deliberately reuses the mailer
        # itself rather than re-implementing "which HTML/template applies" (custom EmailTemplate
        # vs. the built-in view) a second time: `ParticipantMailer.confirmation(participant).message`
        # builds the real `Mail::Message` (running the exact same branch, attaching the exact same
        # PDF bytes) without delivering it — no email is sent by hitting this endpoint, confirmed
        # against ActionMailer::Base's own `MessageDelivery#message` (renders/builds only, `#deliver_now`/
        # `#deliver_later` are separate, never-called steps here).
        def invitation
          event = Current.account.events.friendly.find(params[:slug])
          participant = event.participants.find_by!(hex_id: params[:hex_id].to_s.upcase)

          message = ParticipantMailer.confirmation(participant).message
          pdf = message.attachments["registration-#{participant.hex_id}.pdf"].body.raw_source

          send_data pdf, filename: "invitation-#{participant.hex_id}.pdf", type: "application/pdf", disposition: "attachment"
        rescue ActiveRecord::RecordNotFound
          head :not_found
        end

        private

        # Individual public self-registration has no existing capacity concept to reuse —
        # TicketCategory#remain_count/sold_count track TicketReservation bulk/group holds only
        # (TicketReservationService's own comment), a wholly separate mechanism from both admin
        # manual entry (which enforces no capacity limit at all today) and this endpoint. A
        # straight count against total_count is the correct, honest floor here: it prevents
        # overselling without borrowing (and thereby corrupting) the reservation system's own
        # counters. Deliberately no waitlist — Participant has no such status (only pending/
        # confirmed); a real FIFO waitlist-and-promote flow for individual registrants would need
        # new modeling (TicketReservation's own model comment already flags per-seat claim-link
        # consumption as separate, not-yet-built territory), not something this endpoint should
        # improvise. A "sold out" rejection is the honest behavior for what exists today.
        def capacity_exhausted?(event, ticket_category)
          return false if ticket_category.unlimited?

          event.participants.where(ticket_category: ticket_category).count >= ticket_category.total_count
        end

        # Same permitted-field shape as Admin::ParticipantsController#participant_params —
        # deliberately not shared as a concern: the two controllers differ in enough of what
        # wraps this (capacity check, source/status assignment, auth model) that extracting just
        # the params list would save little and couple an OAuth-token-authenticated public
        # controller to a Devise-session admin one for no real gain.
        def participant_params
          params.require(:participant).permit(
            :ticket_category_id, :title, :first_name, :last_name, :email, :contact_num, :company, :department, :position,
            :nationality, :country, :govt_id, :rf_id, :photo, :document,
            custom_field_values: {}
          )
        end

        def fixed_field_params
          participant_params.except(:custom_field_values, :photo, :document)
        end

        # photo/document accept either a signed_id String (a pre-uploaded blob, same
        # TenantScopedAttachment#attach_tenant_scoped shape the admin console's own JS
        # direct-upload flow produces) or a real multipart file — Next.js's own `/api/register`
        # route handler is a thin proxy (doc/public_event_site_options.md's own description), so a
        # plain multipart FormData submission from the browser relays straight through and just
        # works, no separate public direct-upload endpoint required for MVP.
        def apply_uploads(participant)
          photo = participant_params[:photo]
          participant.attach_tenant_scoped(:photo, photo, "participants", participant.event_id, :photo) if photo.present?

          document = participant_params[:document]
          participant.attach_tenant_scoped(:document, document, "participants", participant.event_id, :document) if document.present?

          apply_custom_field_values(participant)
        end

        def apply_custom_field_values(participant)
          custom_fields = participant.ticket_category&.registration_form&.custom_fields
          return if custom_fields.blank?

          custom_fields.find_each do |field|
            raw = participant_params.dig(:custom_field_values, field.id.to_s)
            next if raw.nil?

            case field.field_type
            when "file"
              participant.attach_custom_field_file(field.id, raw) if raw.respond_to?(:original_filename)
            when "checkbox"
              participant.custom_field_values[field.id.to_s] = ActiveModel::Type::Boolean.new.cast(raw)
            else
              participant.custom_field_values[field.id.to_s] = raw
            end
          end
        end
      end
    end
  end
end
