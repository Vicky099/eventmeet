module SuperAdmin
  # requirement.md revisit: "this page and sidebar link is not required as we have a agency to
  # handle the tenant accounts" — the standalone list/view/edit surface this controller used to be
  # (Phase 2, revisited for the fixed-hierarchy pivot) is gone; a tenant's own details now render
  # as a modal directly on its owning Agency's own show page instead of a separate page navigation.
  # All that's left here is the one piece of real oversight that modal still needs to trigger:
  # suspend/reinstate, kept as plain actions with no page of their own.
  class AccountsController < BaseController
    before_action :set_account, only: [ :suspend, :reinstate ]

    def suspend
      @account.suspended!
      redirect_to redirect_target, notice: "#{@account.name} suspended."
    end

    def reinstate
      @account.active!
      redirect_to redirect_target, notice: "#{@account.name} reinstated."
    end

    private

    def set_account
      @account = Account.find(params[:id])
    end

    # Back to the owning Agency's own show page — that's the only place this action is ever
    # triggered from now. Falls back to the Agencies list for a legacy standalone Account
    # (requirement.md revisit's own "left alone, not migrated" carve-out) — one of those has no
    # Agency page to return to at all.
    def redirect_target
      @account.agency ? platform_agency_path(@account.agency) : platform_agencies_path
    end
  end
end
