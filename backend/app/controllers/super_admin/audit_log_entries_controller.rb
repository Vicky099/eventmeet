module SuperAdmin
  # Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md). Read-only —
  # no #show/edit/destroy, same "an audit log that can be modified isn't one" reasoning
  # AuditLogEntry's own migration comment already states. Every action every SuperAdmin::
  # controller performs against tenant/agency data routes through AuditLog.record! (this table's
  # only writer), so this is purely a viewer.
  class AuditLogEntriesController < BaseController
    def index
      @entries = AuditLogEntry.includes(:actor, :target).order(created_at: :desc)

      @actor_filter = params[:actor_id].presence
      @entries = @entries.where(actor_id: @actor_filter) if @actor_filter

      @action_filter = params[:action_name].to_s.strip.presence
      @entries = @entries.where(action: @action_filter) if @action_filter

      @target_type_filter = params[:target_type].presence_in(AuditLogEntry.distinct.pluck(:target_type).compact)
      @entries = @entries.where(target_type: @target_type_filter) if @target_type_filter

      @from_date = params[:from_date].presence && Date.parse(params[:from_date])
      @entries = @entries.where(created_at: @from_date.beginning_of_day..) if @from_date

      @to_date = params[:to_date].presence && Date.parse(params[:to_date])
      @entries = @entries.where(created_at: ..@to_date.end_of_day) if @to_date

      # Filter dropdown options — every actor/action/target_type that has ever appeared, not a
      # fixed list, since new action strings are added freely at each retrofit call site (this
      # table's own migration comment: "new actions don't need a migration").
      @actors = User.where(id: AuditLogEntry.distinct.pluck(:actor_id)).order(:email)
      @actions = AuditLogEntry.distinct.order(:action).pluck(:action)
      @target_types = AuditLogEntry.distinct.pluck(:target_type).compact.sort

      @pagy, @entries = pagy(@entries, items: 25)
    rescue ArgumentError
      redirect_to platform_audit_log_entries_path, alert: "Enter valid dates."
    end
  end
end
