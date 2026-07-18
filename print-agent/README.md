# EventMeet Print Agent

A small Electron app that runs on a front-desk/kiosk machine, pairs with one EventMeet tenant +
event + print station, and silently prints badges as they're pushed from the server — no manual
"Print" click, no browser involved on that machine. See the root
[`README.md`](../README.md#print-agent-electron) for the high-level flow diagram and
[`backend/doc/print-agent-protocol.md`](../backend/doc/print-agent-protocol.md) for the full wire
protocol (JWT claims, message shapes, HTTP endpoints).

## Requirements

- Node.js
- A running EventMeet backend (`cd ../backend && bin/dev`) to pair against

## Run it

```sh
npm install
npm start
```

On first launch (or if there's no saved pairing yet) a small window opens asking for:

- **Server URL** — the tenant's own admin-console host, e.g. `http://acme.lvh.me:3000` in local
  dev, or `https://{tenant_slug}.{platform_domain}` in production. This has to be the *exact* host
  the pairing code was generated on — pairing codes are looked up scoped to whichever tenant the
  request's `Host` header resolves to.
- **Pairing code** — generated from the admin console's **Print Stations** page (10-minute expiry,
  single-use).

Once paired, the app runs headless — no Dock icon, no window. Status lives in a **menu-bar Tray
icon** (top-right on macOS): click it to see connection status, re-pair against a different
server/station ("Re-pair…"), or quit.

If a saved pairing stops working (e.g. an admin revoked the station), the app retries a few times
and then automatically reopens the pairing window with the previous server URL pre-filled — you
shouldn't need to dig through the tray menu or hunt for the config file by hand.

## What's real vs. deferred

Pairing, the persistent Action Cable connection, fetching a rendered badge PDF, and silent
printing via Chromium's native print API all work end-to-end. **Not built yet, deliberately**:

- Packaging (`electron-builder` signed installers per OS)
- Auto-update (`electron-updater`)
- Raw driver-level output for dedicated card/badge printers (Zebra ZPL, Evolis) — this drives
  standard OS-registered printers only

Config (server URL, token, station name) is stored in a plain JSON file under Electron's own
per-OS `userData` directory — nothing to configure by hand beyond the initial pairing.
