module SuperAdmin
  # Phase 2 — Tenant Provisioning (requirement.md §4.1, §4.3, §4.7): creating an Account here is
  # the *only* way a tenant comes into existence (no self-serve sign-up, §4.1). Every action is
  # already gated to platform_staff by BaseController — no further Pundit check needed, there's no
  # role variation within the Platform Console the way there is within a tenant's own Account.
  class AccountsController < BaseController
    before_action :set_account, only: [ :show, :edit, :update, :suspend, :reinstate ]

    def index
      @status_filter = params[:status].to_s.presence_in(Account.statuses.keys)
      @query = params[:q].to_s.strip

      @accounts = Account.order(created_at: :desc)
      @accounts = @accounts.where(status: @status_filter) if @status_filter
      @accounts = @accounts.where("name ILIKE :q OR subdomain_slug ILIKE :q", q: "%#{@query}%") if @query.present?
    end

    def show
    end

    def new
      @account = Account.new
    end

    # AccountProvisioning (app/services/account_provisioning.rb) does the actual work — Account +
    # owner User + AccountMembership + Doorkeeper::Application in one transaction, welcome email
    # on success. This action only translates its Result into a redirect or a re-rendered form.
    def create
      attrs = account_params
      result = AccountProvisioning.call(account_attributes: attrs.except(:admin_email), admin_email: attrs[:admin_email])

      if result.success?
        redirect_to platform_account_path(result.account),
          notice: "#{result.account.name} provisioned — welcome email sent to #{result.admin_user.email}."
      else
        @account = result.account
        @admin_email = result.admin_user.email # not a real Account attribute — repopulated separately for the re-rendered form
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    # :admin_email is create-only (provisions a new owner User, AccountProvisioning) — the edit
    # form never renders that field (_form.html.erb), but strong params doesn't know that; excluded
    # explicitly rather than trusting the form to never send it, same as #create does.
    def update
      if @account.update(account_params.except(:admin_email))
        redirect_to platform_account_path(@account), notice: "#{@account.name} updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def suspend
      @account.suspended!
      redirect_to platform_account_path(@account), notice: "#{@account.name} suspended."
    end

    def reinstate
      @account.active!
      redirect_to platform_account_path(@account), notice: "#{@account.name} reinstated."
    end

    # requirement.md §4.3: reserved-word/uniqueness check against the slug as the Super Admin
    # types it, rendered into the Turbo Frame the new/edit form's slug field targets — see
    # app/javascript/controllers/slug_check_controller.js for the debounce that drives this.
    # exclude_id (edit form only, _form.html.erb) keeps an unchanged slug from flagging as
    # "taken" against the very record being edited.
    def check_slug
      slug = params[:subdomain_slug].to_s.strip.downcase
      render partial: "slug_availability",
        locals: { slug: slug, availability: slug_availability(slug, exclude_id: params[:exclude_id]) }
    end

    private

    def set_account
      @account = Account.find(params[:id])
    end

    def account_params
      params.require(:account).permit(:name, :subdomain_slug, :admin_email)
    end

    def slug_availability(slug, exclude_id: nil)
      return :blank if slug.blank?
      return :invalid unless slug.match?(/\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/) && slug.length.between?(3, 63)
      return :reserved if Account::RESERVED_SLUGS.include?(slug)

      taken = Account.where("lower(subdomain_slug) = ?", slug)
      taken = taken.where.not(id: exclude_id) if exclude_id.present?
      return :taken if taken.exists?

      :available
    end
  end
end
