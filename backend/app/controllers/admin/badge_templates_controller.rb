module Admin
  # Phase 8 — Badge Design & Printing (requirement.md §5.5): "badge template library with
  # reusable/sharable templates across events within a tenant." Account-level, not nested under
  # any Event — #edit hosts the same GrapesJS canvas Admin::BadgesController#edit does (shared
  # partial, app/views/admin/shared/_badge_editor.html.erb), just saving back to a BadgeTemplate
  # instead of a Badge. No #show — #edit is the workspace, same "no separate read-only page"
  # shortcut every other builder-style resource in this app takes.
  class BadgeTemplatesController < BaseController
    # The quick "start a template" form (#new/#create) only asks for name/type/size — content is
    # only ever meaningfully edited on the GrapesJS canvas (#edit), but `content` is required
    # (HasBadgeMapping), so a brand-new row needs *something* non-blank to save at all.
    BLANK_CANVAS = "<div style=\"width:100%;height:100%;\"></div>".freeze

    before_action :set_badge_template, only: [ :edit, :update, :destroy ]

    def index
      authorize BadgeTemplate
      @pagy, @badge_templates = pagy(Current.account.badge_templates.order(created_at: :desc), limit: 25)
    end

    def new
      @badge_template = Current.account.badge_templates.build(width_cm: 8.5, height_cm: 5.4, content: BLANK_CANVAS)
      authorize @badge_template
    end

    def create
      @badge_template = Current.account.badge_templates.build(badge_template_params)
      @badge_template.content = BLANK_CANVAS if @badge_template.content.blank?
      authorize @badge_template

      if @badge_template.save
        apply_uploads(@badge_template)
        redirect_to edit_admin_badge_template_path(@badge_template), notice: "#{@badge_template.name} created."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      authorize @badge_template
    end

    def update
      authorize @badge_template

      if @badge_template.update(badge_template_params)
        apply_uploads(@badge_template)
        redirect_to admin_badge_templates_path, notice: "#{@badge_template.name} saved."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @badge_template
      @badge_template.destroy
      redirect_to admin_badge_templates_path, notice: "#{@badge_template.name} removed."
    end

    private

    def set_badge_template
      @badge_template = Current.account.badge_templates.find(params[:id])
    end

    def badge_template_params
      params.require(:badge_template).permit(:name, :content, :output_type, :width_cm, :height_cm, mapping: {})
    end

    def apply_uploads(badge_template)
      bg = params.dig(:badge_template, :background_image)
      badge_template.attach_background_image(bg) if bg.present?

      logo = params.dig(:badge_template, :logo)
      badge_template.attach_logo(logo) if logo.present?
    end
  end
end
