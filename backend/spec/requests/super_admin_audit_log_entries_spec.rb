require "rails_helper"

# Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md). Read-only viewer —
# every entry is created elsewhere (spec/services/audit_log_spec.rb, and every retrofitted
# SuperAdmin:: controller spec); this just covers listing/filtering/pagination.
RSpec.describe "Platform Console audit log", type: :request do
  let!(:staff) { create(:user, :platform_staff) }

  before { host! "example.com" }

  describe "access control" do
    it "redirects a signed-out request to the Platform Console login" do
      get platform_audit_log_entries_path
      expect(response).to redirect_to(new_platform_staff_session_path)
    end
  end

  describe "GET /platform/audit_log_entries" do
    before { sign_in staff, scope: :platform_staff }

    it "lists every entry, most recent first" do
      agency = create(:agency)
      older = AuditLog.record!(actor: staff, action: "agency.suspend", target: agency)
      older.update_column(:created_at, 1.day.ago)
      newer = AuditLog.record!(actor: staff, action: "agency.reinstate", target: agency)

      get platform_audit_log_entries_path

      expect(response).to have_http_status(:ok)
      rows = response.body.scan(/agency\.\w+/)
      expect(rows.index("agency.reinstate")).to be < rows.index("agency.suspend")
    end

    it "filters by action" do
      agency = create(:agency)
      AuditLog.record!(actor: staff, action: "agency.suspend", target: agency)
      AuditLog.record!(actor: staff, action: "agency.reinstate", target: agency)

      get platform_audit_log_entries_path, params: { action_name: "agency.suspend" }

      # Scoped to the results table, not the whole body — the filter dropdown's own <option>
      # list legitimately includes every action ever seen, including the one just filtered out.
      actions = Nokogiri::HTML(response.body).css("table tbody tr code").map(&:text)
      expect(actions).to eq([ "agency.suspend" ])
    end

    it "filters by actor" do
      other_staff = create(:user, :platform_staff)
      agency = create(:agency)
      AuditLog.record!(actor: staff, action: "agency.suspend", target: agency)
      AuditLog.record!(actor: other_staff, action: "agency.suspend", target: agency)

      get platform_audit_log_entries_path, params: { actor_id: other_staff.id }

      doc = Nokogiri::HTML(response.body)
      emails = doc.css("table tbody tr").map { |row| row.css("td")[1]&.text&.strip }
      expect(emails).to eq([ other_staff.email ])
    end

    it "filters by date range" do
      agency = create(:agency)
      AuditLog.record!(actor: staff, action: "agency.suspend", target: agency)
      out_of_range = AuditLog.record!(actor: staff, action: "agency.reinstate", target: agency)
      out_of_range.update_column(:created_at, 10.days.ago)

      get platform_audit_log_entries_path, params: { from_date: 1.day.ago.to_date.iso8601, to_date: Date.current.iso8601 }

      actions = Nokogiri::HTML(response.body).css("table tbody tr code").map(&:text)
      expect(actions).to eq([ "agency.suspend" ])
    end

    it "redirects with an alert on an invalid date instead of 500ing" do
      get platform_audit_log_entries_path, params: { from_date: "not-a-date" }

      expect(response).to redirect_to(platform_audit_log_entries_path)
      follow_redirect!
      expect(response.body).to include("Enter valid dates")
    end
  end
end
