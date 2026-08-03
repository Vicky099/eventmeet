module Admin
  # requirement.md revisit: "at client portal show the new sidebar menu as team and inside it list
  # down the admin and staff name and against staff show the action as suspended" — this Account's
  # own admin/staff roster, read-only for everyone, plus a Suspend/Reinstate action against each
  # admin_staff row. Deliberately separate from AgencyConsole::AccountMembershipsController (that
  # one lets the *Agency* invite/remove a client's admins on their behalf); this is the client's
  # own self-service view of the same roster, scoped to Current.account rather than an
  # agency-selected :account_id.
  class TeamController < BaseController
    before_action :set_membership, only: [ :suspend, :reinstate ]
    # before_action (not a plain in-action call) — redirect_to here must actually halt the
    # filter chain before #suspend/#reinstate's own `@membership.suspended!`/`#active!` runs, which
    # a bare method call from inside the action wouldn't do on its own.
    before_action :require_event_admin!, only: [ :suspend, :reinstate ]

    def index
      @account_memberships = Current.account.account_memberships.includes(:user).order(:role, :created_at)
    end

    # Only an event_admin may suspend a teammate — admin_staff has no create/edit/destroy rights
    # anywhere else in this app (AccountMembership's own role-split comment), and event_admin
    # itself (the tenant's own full-control owner tier) is never a valid target: #set_membership
    # scopes to admin_staff? only, same "fail closed on an impossible/disallowed target" shape
    # #reinstate below takes too.
    def suspend
      @membership.suspended!
      redirect_to admin_team_path, notice: "#{@membership.user.email} suspended."
    end

    def reinstate
      @membership.active!
      redirect_to admin_team_path, notice: "#{@membership.user.email} reinstated."
    end

    private

    def set_membership
      @membership = Current.account.account_memberships.admin_staff.find(params[:id])
    end

    def require_event_admin!
      membership = current_user.account_membership_for(Current.account)
      return if membership&.event_admin?

      redirect_to admin_team_path, alert: "Only an Admin can suspend a teammate."
    end
  end
end
