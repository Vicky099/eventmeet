module SuperAdmin
  # The Platform Console's authenticated landing page (requirement.md §4.7, §5.14/§5.15, Phase 3)
  # — supersedes the Phase 0 SmokeController at platform_staff_root_path.
  class DashboardController < BaseController
    def index
      # Real data — Account has existed since Phase 0/provisioned since Phase 2, nothing stubbed
      # about this count.
      @tenant_count = Account.count
      # Fixed-hierarchy pivot (requirement.md revisit): replaces the old "Pending Approvals" stat
      # (a permanently-stubbed 0 — that workflow is gone entirely now) with a real count of the
      # entity that's now actually central to provisioning.
      @agency_count = Agency.count
      # Event is TenantScoped — this dashboard has no Current.account of its own (Current.platform_request
      # is what's set here), same reasoning every other cross-tenant platform-level count in this
      # app already needs .unscoped_across_tenants for (see AgencyConsole::DashboardController's
      # own comment for the fuller mechanism this mirrors).
      @event_count = Event.unscoped_across_tenants { Event.count }
      # Phase 9 (requirement.md §5.15) — read on demand for first paint, same "cache read now,
      # broadcast on change" split EventLiveStats already uses; LiveDashboard.broadcast_platform_pulse
      # keeps every already-open dashboard's copy fresh after that.
      @live_pulse = LiveDashboard.platform_pulse

      # requirement.md revisit: "generate the proper analytics for super admin, earning and all."
      # Grouped by currency (Currency::CODES — an agency can pick USD/EUR/GBP, not just the INR
      # default), never blended into one number: summing across currencies would just be wrong,
      # not merely imprecise.
      @revenue_by_currency = Invoice.paid.group(:currency).sum(:amount)
      @outstanding_by_currency = Invoice.where(status: [ :awaiting_payment, :under_review ]).group(:currency).sum(:amount)

      # Revenue by Agency — grouped by the agency itself, not by currency, so this sidesteps the
      # cross-currency-sum problem entirely: every Invoice a given Agency ever generates
      # (Invoice.generate_for/.generate_for_agency_contract, both read agency.currency at
      # generation time) is already in that one Agency's own currency throughout, so a single sum
      # per agency is safe to compute and safe to render in agency.currency.
      paid_invoices = Invoice.paid.includes(:agency, account: :agency)
      @revenue_by_agency = paid_invoices
        .group_by { |invoice| invoice.agency || invoice.account&.agency }
        .compact # a legacy standalone Account (no Agency, requirement.md revisit's own "left alone, not migrated" carve-out) resolves to no agency at all — nothing to attribute that row to, so it's dropped rather than crashing the view
        .transform_values { |invoices| invoices.sum(&:amount) }
        .sort_by { |_agency, total| -total }
        .first(5)

      # "Due invoices need actions" — the Super Admin's own action queue, not merely a count:
      # `draft` needs #deliver (send), `under_review` needs #verify/#reject. Deliberately excludes
      # `awaiting_payment` — that status is waiting on the agency to pay, nothing for the Super
      # Admin to actually do about it yet, so it stays out of an "actions needed" list (still
      # visible via the full /platform/invoices index if wanted). Ordered so drafts (status 0)
      # surface before under_review (status 2) — the newest, most actionable ones first within
      # each.
      @invoices_needing_action = Invoice.where(status: [ :draft, :under_review ])
        .includes(:event, :agency, account: :agency)
        .order(:status, created_at: :desc)
        .limit(10)

      # requirement.md revisit: "as whatsApp is paid i want to track the usage and the approx
      # amount" — platform-wide, so no per-agency/per-event scoping (unlike
      # SuperAdmin::AgenciesController#show's own identical count one tier down, whose comment has
      # the full "why status: :sent, not merely created" reasoning). No .unscoped_across_tenants
      # needed — same as @revenue_by_currency above, this already runs under
      # Current.platform_request. @whatsapp_approx_spend is deliberately an estimate, not a real
      # Gupshup invoice reconciliation (config/initializers/multi_tenancy.rb's own comment on the
      # stakeholder-set placeholder rate behind it).
      @whatsapp_message_count = Notification.where(channel: :whatsapp, status: :sent).count
      @whatsapp_approx_spend = @whatsapp_message_count * Rails.application.config.x.whatsapp_message_cost
    end
  end
end
