require "rails_helper"

# Phase 3 DoD: "Component/view spec for the shared stat-widget partial (renders label + value +
# optional trend)." Companion partials (shared/_card, shared/_empty_state) aren't separately
# spec'd — they're exercised indirectly through every request spec that renders a page composing
# them (e.g. spec/requests/dashboards_spec.rb), which is what actually matters for markup this
# simple; the stat-widget is the one DoD calls out explicitly.
RSpec.describe "shared/_stat_widget", type: :view do
  it "renders the label and value" do
    render partial: "shared/stat_widget", locals: { label: "Events", value: 0, icon: "bx-calendar-event" }
    page = Capybara.string(rendered)

    expect(page).to have_css("h6", text: "Events")
    expect(page).to have_css("h4", text: "0")
  end

  it "renders an optional trend, direction and text" do
    render partial: "shared/stat_widget", locals: {
      label: "Sales", value: "$12,253", icon: "bx-store-alt", trend: { direction: :up, text: "2.64%" }
    }

    expect(rendered).to include("2.64%")
    expect(rendered).to include("mdi-arrow-up")
    expect(rendered).to include("text-success")
  end

  it "omits the trend markup entirely when none is given" do
    render partial: "shared/stat_widget", locals: { label: "Events", value: 0, icon: "bx-calendar-event" }

    expect(rendered).not_to include("mdi-arrow")
  end

  it "defaults to the primary color when none is given" do
    render partial: "shared/stat_widget", locals: { label: "Events", value: 0, icon: "bx-calendar-event" }

    expect(rendered).to include("bg-primary-subtle")
    expect(rendered).to include("text-primary")
  end

  it "uses the given color instead of the default" do
    render partial: "shared/stat_widget", locals: { label: "Participants", value: 42, icon: "bx-group", color: "success" }

    expect(rendered).to include("bg-success-subtle")
    expect(rendered).to include("text-success")
  end
end
