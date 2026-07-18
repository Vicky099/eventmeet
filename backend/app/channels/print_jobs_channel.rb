# Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1, §4.9 item 3). The first
# hand-rolled Channel in this app — every other bit of real-time behavior (Phase 9's live
# dashboards) rides on turbo-rails' own Turbo::StreamsChannel via `turbo_stream_from`, but that's
# a browser-facing, signed-stream-name mechanism with no equivalent for a non-browser agent
# authenticating with a JWT instead of a page-scoped signed name.
#
# One stream per PrintStation (`stream_for` encodes the station via GlobalID) — a station's
# currently-connected agent is whoever most recently subscribed; PrintTriggerService pushes jobs
# with `PrintJobsChannel.broadcast_to(station, ...)`, the paired counterpart to `stream_for`
# below.
#
# `heartbeat`/`job_update` are real public actions, not branches inside a single #receive — Action
# Cable's own dispatch (Channel::Base#perform_action) reads the incoming message's own "action"
# key and calls a method of that exact name, only falling back to #receive when no "action" key is
# present at all; naming the agent's own payload field "action" (doc/print-agent-protocol.md's own
# wire shape, chosen before this was discovered live) means these two have to be real actions to
# ever be dispatched to at all — confirmed live via a spec that sent one and asserted the
# resulting PrintJob status, which silently never updated until this was fixed.
class PrintJobsChannel < ApplicationCable::Channel
  def subscribed
    agent = current_print_agent
    return reject if agent.nil? || agent.revoked?

    # Current.account resets per Action Cable invocation (each channel action runs in its own
    # Rails executor wrap, unlike a single Devise-session HTTP request) — every action here that
    # touches a TenantScoped association (print_station, print_jobs) must set it fresh, mirroring
    # how ParticipantExportJob sets it fresh at the top of #perform for the same reason.
    Current.account = agent.account
    stream_for agent.print_station
    agent.update!(connected: true, last_seen_at: Time.current)
  end

  def unsubscribed
    return if current_print_agent.nil?

    Current.account = current_print_agent.account
    current_print_agent.update!(connected: false)
  end

  # Keeps PrintStation#online? accurate between jobs — Cable's own subscribed/unsubscribed toggle
  # isn't reliable enough on its own (a killed process/dropped network doesn't always fire
  # unsubscribed cleanly).
  def heartbeat(_data)
    touch_agent!
  end

  # How the agent reports back after actually calling webContents.print — the only write path
  # for PrintJob#status beyond PrintTriggerService's own initial pending/sent transition, since
  # only the agent itself knows whether the OS print spooler actually succeeded.
  def job_update(data)
    touch_agent!

    job = current_print_agent.print_station.print_jobs.find_by(id: data["job_id"])
    return if job.nil?

    case data["status"]
    when "succeeded"
      job.update!(status: :succeeded, completed_at: Time.current)
    when "failed"
      job.update!(status: :failed, completed_at: Time.current, error_message: data["error"])
    end
  end

  private

  def touch_agent!
    return if current_print_agent.nil?

    Current.account = current_print_agent.account
    current_print_agent.update!(last_seen_at: Time.current)
  end
end
