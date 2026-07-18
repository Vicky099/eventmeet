# Print Agent Protocol (Phase 10)

The stable contract between Rails and the Electron print agent (`print-agent/` at the repo
root, a separate package/deliverable track — see its own `package.json`). Referenced from
`doc/implementation.md` Phase 10.

## 1. Pairing

`POST {server}/print_agent/pair`

```json
{ "pairing_code": "AB12CD34" }
```

The `server` is the tenant's own admin-console host (e.g. `https://acme.eventmeet.example`) —
the same host the pairing code was generated on (`Admin::PrintStationsController#generate_pairing_code`,
10-minute expiry, single-use — invalidated the moment it's redeemed). Response:

```json
{
  "token": "<JWT>",
  "cable_url": "wss://acme.eventmeet.example/cable",
  "station_name": "Front Desk 1",
  "event_name": "Annual Meetup 2026"
}
```

`400/422` with `{ "error": "..." }` on an invalid/expired code.

## 2. JWT

Signed HS256 with the Rails app's `secret_key_base`. Claims:

```json
{ "account_id": "...", "event_id": "...", "station_id": "...", "agent_id": "...", "jti": "...", "exp": 1234567890 }
```

24-hour expiry, but **not** the actual revocation mechanism — an admin revoking a station
(`Admin::PrintStationsController#revoke`) sets `PrintAgent#revoked_at` and force-disconnects any
live Action Cable connection immediately; every token verification (`PrintAgentToken.decode`)
re-checks `revoked_at` live against the database on every use, never trusting the token's own
expiry alone.

## 3. Action Cable connection

`GET {cable_url}?token=<JWT>` — plain Action Cable JSON-over-WebSocket wire protocol (no
`@rails/actioncable` dependency needed; `print-agent/main.js` speaks it directly via `ws`).

1. Server sends `{"type":"welcome"}`.
2. Agent subscribes: `{"command":"subscribe","identifier":"{\"channel\":\"PrintJobsChannel\"}"}`.
3. Server confirms: `{"type":"confirm_subscription","identifier":"..."}`, or rejects the
   connection outright if the token doesn't resolve to a live, non-revoked `PrintAgent`.

## 4. Server → agent: a print job

Pushed via `PrintJobsChannel.broadcast_to(station, ...)` (`PrintTriggerService`), arrives as:

```json
{ "identifier": "{\"channel\":\"PrintJobsChannel\"}", "message": { "action": "print_job", "job_id": "...", "participant_name": "Jane Doe" } }
```

The agent then fetches the rendered PDF:

`GET {server}/print_agent/print_jobs/{job_id}/badge` with `Authorization: Bearer <token>` — reuses
`BadgePdfService` unchanged, same renderer the admin console's own on-demand download uses.

## 5. Agent → server messages

Sent as `{"command":"message","identifier":"...","data":"<JSON string>"}`:

- Heartbeat (every 30s while idle): `{"action":"heartbeat"}` — keeps `PrintStation#online?`
  accurate between jobs (Cable's own subscribed/unsubscribed toggle alone isn't reliable enough —
  a killed process or dropped network doesn't always fire `unsubscribed` cleanly).
- Job result: `{"action":"job_update","job_id":"...","status":"succeeded"}` or
  `{"action":"job_update","job_id":"...","status":"failed","error":"..."}`.

## 6. Printer targeting

`webContents.print({ silent: true, printBackground: true, deviceName })` — `deviceName` is
whatever the admin typed into the station's `printer_name` field (free text, OS-specific); blank
means "use the OS default printer."

## 7. Explicitly out of scope for this pass

`electron-builder` packaging, code signing, `electron-updater` auto-update, and raw
Zebra/Evolis card-printer driver support — real per-OS ops/release-engineering work, flagged as a
separate follow-up track rather than silently skipped. `print-agent/` runs via `npm start`
(`electron .`) in dev today.
