require "rails_helper"

# Phase 8 — Badge Design & Printing (requirement.md §3.6, §5.5).
RSpec.describe "Admin Console badges", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }

  before { host! "acme.example.com" }

  def sign_in_with_role(role)
    user = create(:user, email: "#{role}@acme.example", password: "password123!")
    create(:account_membership, user: user, account: account, role: role)
    sign_in user, scope: :user
  end

  def create_event(**attrs)
    Current.account = account
    create(:event, account: account, **attrs)
  end

  describe "PATCH /admin/badge_templates/:id (library)" do
    before { sign_in_with_role(:owner) }

    it "creates a blank template then saves canvas content/mapping to it" do
      post admin_badge_templates_path, params: { badge_template: { name: "Standard", width_cm: "8.5", height_cm: "5.4" } }
      Current.account = account
      template = account.badge_templates.sole
      expect(response).to redirect_to(edit_admin_badge_template_path(template))

      patch admin_badge_template_path(template), params: {
        badge_template: { content: "<div>$NAME$</div>", mapping: { "OTHER1" => "company" } }
      }

      expect(response).to redirect_to(admin_badge_templates_path)
      Current.account = account
      template.reload
      expect(template.content).to eq("<div>$NAME$</div>")
      expect(template.mapping).to eq({ "OTHER1" => "company" })
    end
  end

  describe "PATCH /admin/events/:event_id/badges (per-event, requirement.md §5.5 conditional layouts)" do
    before { sign_in_with_role(:owner) }

    it "rejects creating a second default badge for the same event" do
      event = create_event
      Current.account = account
      create(:badge, account: account, event: event, ticket_category: nil)

      post admin_event_badges_path(event), params: { badge: { name: "Second Default", width_cm: "8.5", height_cm: "5.4" } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "allows a default badge and a category-specific badge on the same event" do
      event = create_event
      Current.account = account
      category = create(:ticket_category, account: account, event: event)
      create(:badge, account: account, event: event, ticket_category: nil)

      expect {
        post admin_event_badges_path(event), params: { badge: { name: "VIP", ticket_category_id: category.id, width_cm: "8.5", height_cm: "5.4" } }
      }.to change { Event.unscoped_across_tenants { Badge.count } }.by(1)

      expect(response).to have_http_status(:redirect)
    end

    it "creates a badge from a template, copying its content in" do
      event = create_event
      Current.account = account
      template = create(:badge_template, account: account, content: "<div>$NAME$</div>")

      post admin_event_badges_path(event), params: { badge_template_id: template.id, badge: { name: "From Template", width_cm: "8.5", height_cm: "5.4" } }

      Current.account = account
      badge = Badge.sole
      expect(badge.content).to eq("<div>$NAME$</div>")
      expect(badge.badge_template).to eq(template)
    end
  end

  describe "PATCH/DELETE /admin/events/:event_id/badges/:id (redirect back to the wizard step, not the standalone index)" do
    before { sign_in_with_role(:owner) }

    it "redirects to the Badge wizard step after saving" do
      event = create_event
      Current.account = account
      badge = create(:badge, account: account, event: event, ticket_category: nil, name: "Original")

      patch admin_event_badge_path(event, badge), params: { badge: { name: "Renamed" } }

      expect(response).to redirect_to(edit_admin_event_path(event, step: "badge"))
    end

    it "redirects to the Badge wizard step after removing" do
      event = create_event
      Current.account = account
      badge = create(:badge, account: account, event: event, ticket_category: nil)

      delete admin_event_badge_path(event, badge)

      expect(response).to redirect_to(edit_admin_event_path(event, step: "badge"))
    end
  end

  describe "POST /admin/events/:event_id/badges/:id/copy (requirement.md §5.5: reuse a designed badge across ticket categories)" do
    before { sign_in_with_role(:owner) }

    it "copies content/mapping/size onto a new badge for the target ticket category and lands on its editor" do
      event = create_event
      Current.account = account
      category = create(:ticket_category, account: account, event: event, name: "VIP")
      source = create(:badge, account: account, event: event, ticket_category: nil, name: "Default Badge",
        content: "<div>$NAME$</div>", mapping: { "OTHER1" => "company" }, width_cm: 8.5, height_cm: 5.4)

      expect {
        post copy_admin_event_badge_path(event, source), params: { ticket_category_id: category.id }
      }.to change { Event.unscoped_across_tenants { Badge.count } }.by(1)

      copy = Event.unscoped_across_tenants { Badge.order(:created_at).last }
      expect(response).to redirect_to(edit_admin_event_badge_path(event, copy))
      expect(copy.ticket_category_id).to eq(category.id)
      expect(copy.content).to eq(source.content)
      expect(copy.mapping).to eq(source.mapping)
      expect(copy.width_cm).to eq(source.width_cm)
    end

    it "names the copy after the target ticket category, not the source badge's own name" do
      event = create_event
      Current.account = account
      category = create(:ticket_category, account: account, event: event, name: "VIP")
      source = create(:badge, account: account, event: event, ticket_category: nil, name: "Default Badge")

      post copy_admin_event_badge_path(event, source), params: { ticket_category_id: category.id }

      copy = Event.unscoped_across_tenants { Badge.order(:created_at).last }
      expect(copy.name).to eq("VIP")
    end

    it "copies onto the Default slot when no ticket_category_id is given, naming it \"Default\"" do
      event = create_event
      Current.account = account
      category = create(:ticket_category, account: account, event: event)
      source = create(:badge, account: account, event: event, ticket_category: category, name: "VIP Badge")

      post copy_admin_event_badge_path(event, source)

      copy = Event.unscoped_across_tenants { Badge.where.not(id: source.id).sole }
      expect(copy.ticket_category_id).to be_nil
      expect(copy.name).to eq("Default")
    end

    it "rejects copying onto a slot that already has its own badge" do
      event = create_event
      Current.account = account
      category = create(:ticket_category, account: account, event: event)
      source = create(:badge, account: account, event: event, ticket_category: nil)
      create(:badge, account: account, event: event, ticket_category: category)

      expect {
        post copy_admin_event_badge_path(event, source), params: { ticket_category_id: category.id }
      }.not_to change { Event.unscoped_across_tenants { Badge.count } }

      expect(response).to redirect_to(edit_admin_event_path(event, step: "badge"))
    end
  end

  describe "GET /admin/events/:event_id/participants/:id/badge.pdf (requirement.md §3.6: on-demand single-badge download)" do
    before { sign_in_with_role(:owner) }

    it "returns a PDF sized to the badge's configured physical dimensions" do
      event = create_event
      Current.account = account
      create(:badge, account: account, event: event, ticket_category: nil, width_cm: 8.5, height_cm: 5.4,
        content: "<div style=\"width:100%;height:100%;\">$NAME$</div>")
      participant = create(:participant, account: account, event: event, name: "Alice Smith")

      get badge_admin_event_participant_path(event, participant)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")

      reader = PDF::Reader.new(StringIO.new(response.body))
      media_box = reader.pages.first.attributes[:MediaBox]
      points_per_cm = 28.3465
      expect(media_box[2] / points_per_cm).to be_within(0.2).of(8.5)
      expect(media_box[3] / points_per_cm).to be_within(0.2).of(5.4)
    end

    it "prefers the participant's own ticket-category badge over the event's default" do
      event = create_event
      Current.account = account
      category = create(:ticket_category, account: account, event: event)
      create(:badge, account: account, event: event, ticket_category: nil, width_cm: 8.5, height_cm: 5.4, content: "<div>default</div>")
      create(:badge, account: account, event: event, ticket_category: category, width_cm: 10, height_cm: 7, content: "<div>vip</div>")
      participant = create(:participant, account: account, event: event, ticket_category: category)

      get badge_admin_event_participant_path(event, participant)

      reader = PDF::Reader.new(StringIO.new(response.body))
      media_box = reader.pages.first.attributes[:MediaBox]
      points_per_cm = 28.3465
      expect(media_box[2] / points_per_cm).to be_within(0.2).of(10)
    end

    it "redirects with an alert instead of a broken download when no badge is configured" do
      event = create_event
      Current.account = account
      participant = create(:participant, account: account, event: event)

      get badge_admin_event_participant_path(event, participant)

      expect(response).to redirect_to(admin_event_participants_path(event))
      follow_redirect!
      expect(response.body).to include("No badge has been designed")
    end
  end

  # requirement.md revisit: "a participant show page where we can show ... his badge with all
  # filled data." participant_id repoints this at that real participant's own data instead of
  # the sample one — Admin::ParticipantsController#show's own iframe.
  describe "GET /admin/events/:event_id/badges/:id/preview" do
    it "renders sample data by default, and requires owner/event_manager (design-time preview)" do
      event = create_event
      Current.account = account
      badge = create(:badge, account: account, event: event, ticket_category: nil, content: "<div>$NAME$</div>")
      sign_in_with_role(:checkin_staff)

      get preview_admin_event_badge_path(event, badge)

      expect(response).to redirect_to(user_root_path)
    end

    # Bug: sample_participant (Admin::BadgesController, the design-time preview's synthetic
    # participant) never set title/first_name/last_name, so a badge using $TITLE$/$FIRST_NAME$/
    # $LAST_NAME$ (all real, standalone tokens — see BadgeReformService) rendered those blank in
    # the preview modal even though the tokens were correctly saved and visible back in the
    # GrapesJS editor — the editor just shows the token block itself, not substituted data, so the
    # missing sample value only ever showed up in the preview, not while designing.
    it "fills in every token, including title/first name/last name, for the sample preview" do
      event = create_event
      Current.account = account
      badge = create(:badge, account: account, event: event, ticket_category: nil,
        content: "<div>$TITLE$ $FIRST_NAME$ $LAST_NAME$</div>")
      sign_in_with_role(:owner)

      get preview_admin_event_badge_path(event, badge)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to match(/<div>\s*<\/div>/)
      expect(response.body).to include("Mr.")
      expect(response.body).to include("Sample")
      expect(response.body).to include("Participant")
    end

    it "renders the given participant's own real data when participant_id is given" do
      event = create_event
      Current.account = account
      badge = create(:badge, account: account, event: event, ticket_category: nil, content: "<div>$NAME$</div>")
      participant = create(:participant, account: account, event: event, first_name: "Alice", last_name: "Smith")
      sign_in_with_role(:owner)

      get preview_admin_event_badge_path(event, badge, participant_id: participant.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Alice Smith")
    end

    # requirement.md revisit: any AccountMembership role can view a participant's own show page —
    # the real-participant badge preview it embeds must be reachable by the same roles, even
    # though the sample/design-time preview above stays owner/event_manager-only.
    it "allows checkin_staff to preview a real participant's own badge" do
      event = create_event
      Current.account = account
      badge = create(:badge, account: account, event: event, ticket_category: nil, content: "<div>$NAME$</div>")
      participant = create(:participant, account: account, event: event, first_name: "Bob")
      sign_in_with_role(:checkin_staff)

      get preview_admin_event_badge_path(event, badge, participant_id: participant.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Bob")
    end
  end
end
