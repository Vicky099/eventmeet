module Admin
  # Tenant Admin Console login (requirement.md §4.9 item 1) — the :user Warden scope. Authorization
  # (must hold an AccountMembership on Current.account, Account must be active) is enforced at the
  # model layer (User#active_for_authentication?), not here — this controller only owns the
  # temp-password forced-reset redirect. Views resolve to app/views/admin/sessions/* by plain
  # Rails convention (Devise's own _prefixes only diverges from that when scoped_views is enabled,
  # which it isn't here — see DeviseController#_prefixes).
  class SessionsController < Devise::SessionsController
    # Must be reachable while signed out — Admin::BaseController's authenticate_user! (inherited
    # via config.parent_controller = "Admin::BaseController", config/initializers/devise.rb) would
    # otherwise make the login page itself require being already logged in.
    skip_before_action :authenticate_user!

    layout "auth"

    def create
      super do |resource|
        if resource.must_reset_password?
          # Devise's own create (the super call above) already sign_in'd resource before yielding
          # here — but Admin::PasswordsController#edit/#update both prepend_before_action
          # :require_no_authentication, which would bounce an already-signed-in user straight back
          # out. Sign out first so the reset-password form is reachable; Devise signs them back in
          # for real once they actually set a new password (#update, sign_in_after_reset_password).
          #
          # sign_out(resource_name) — NOT sign_out(resource) — deliberately: :user and
          # :platform_staff both map to this same User class (class_name:, §4.9 item 1), so
          # Devise::Mapping.find_scope! can't unambiguously infer the scope from the resource
          # instance alone; resource_name is this controller's own scope (:user), always unambiguous.
          sign_out(resource_name)

          # set_reset_password_token is protected on Devise::Models::Recoverable — it's the same
          # method send_reset_password_instructions calls internally before mailing a token;
          # calling it directly gets us a valid token without sending an email (already here).
          raw_token = resource.send(:set_reset_password_token)
          redirect_to edit_user_password_path(reset_password_token: raw_token),
            notice: "Set a new password to continue." and return
        end
      end
    end

    # Devise defaults to root_path (the dashboard) after sign-out; sends them back to the login
    # form instead, which is what an admin console actually wants (root itself now requires
    # authenticate_user! — see Admin::BaseController — so this also avoids an extra redirect hop).
    def after_sign_out_path_for(resource_or_scope)
      new_user_session_path
    end

    # Same Devise::Mapping.find_scope! ambiguity as sign_out above, a different call site: the
    # default after_sign_in_path_for/signed_in_root_path infers the scope from the bare resource,
    # which always resolves to :user (registered first in config/routes.rb) regardless of which
    # Warden scope actually signed in. That's silently correct here (this *is* the :user
    # controller) but was actively wrong the one time it mattered — SuperAdmin::SessionsController
    # inherited the exact same default and it sent platform_staff logins to /admin instead of
    # /platform, invisible while both scopes' root happened to be "/" and only surfaced once they
    # became genuinely different paths. Overriding explicitly here too so neither controller's
    # correctness depends on devise_for registration order. stored_location_for is preserved —
    # e.g. hitting a protected admin URL while signed out still returns you there after login,
    # only the *fallback* (no stored location) is pinned to this scope's own root.
    def after_sign_in_path_for(resource_or_scope)
      stored_location_for(resource_or_scope) || user_root_path
    end
  end
end
