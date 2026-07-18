// Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1, §4.9 item 3).
//
// Deliberately minimal: pair with a tenant, hold one Action Cable connection open, silent-print
// whatever badge PDF a print_job message points at, report back. No packaging/electron-builder/
// electron-updater/code-signing in this pass — see doc/print-agent-protocol.md in the backend
// repo for what's real here vs. what's a separate ops/release-engineering track.
"use strict";

const { app, BrowserWindow, Tray, Menu, ipcMain } = require("electron");
const WebSocket = require("ws");
const fs = require("fs");
const path = require("path");
const os = require("os");

const CONFIG_PATH = path.join(app.getPath("userData"), "print-agent-config.json");
const HEARTBEAT_INTERVAL_MS = 30_000;

let tray = null;
let pairingWindow = null;
let cable = null;
let connected = false;

function loadConfig() {
  try {
    return JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8"));
  } catch {
    return null;
  }
}

function saveConfig(config) {
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
}

function setTrayStatus(label) {
  if (!tray) return;
  tray.setToolTip(`EventMeet Print Agent — ${label}`);
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: `Status: ${label}`, enabled: false },
      { type: "separator" },
      // The only way back into the pairing window once a config already exists (e.g. re-pairing
      // against a different station/server) — without this, doing so meant deleting the config
      // file by hand.
      { label: "Re-pair…", click: () => openPairingWindow() },
      { label: "Quit", click: () => app.quit() }
    ])
  );
}

function openPairingWindow(options = {}) {
  if (pairingWindow) {
    pairingWindow.show();
    pairingWindow.focus();
    return;
  }

  pairingWindow = new BrowserWindow({
    width: 420,
    height: 320,
    resizable: false,
    webPreferences: { preload: path.join(__dirname, "pairing_preload.js") }
  });
  pairingWindow.loadFile("pairing.html", { query: options });
  pairingWindow.on("closed", () => { pairingWindow = null; });
  // With no Dock icon (app.dock.hide() above), the OS has nothing to raise this window with —
  // app.focus({ steal: true }) is what actually brings a Dock-less app's window to the front on
  // macOS instead of it silently opening behind whatever's already focused.
  app.focus({ steal: true });
  pairingWindow.focus();
}

// Action Cable's own JSON-over-WebSocket wire protocol (no @rails/actioncable dependency — it
// assumes a browser environment; this is a plain `ws` connection speaking the same documented
// protocol directly): welcome -> client sends {command: "subscribe", identifier} -> server
// confirms with {type: "confirm_subscription"} -> normal messages arrive as {identifier, message}.
const CHANNEL_IDENTIFIER = JSON.stringify({ channel: "PrintJobsChannel" });

// Confirmed live: a stale saved config (e.g. a revoked station, per requirement.md's own
// "immediately invalidating its JWT") reconnects into an identical, immediate rejection on every
// single retry — nothing here can tell a permanently-bad credential apart from a momentary
// network blip on the first failure alone, but a *revoked* connection never recovers no matter
// how many times it retries, unlike a real blip. RECONNECT_FAILURE_THRESHOLD is the number of
// consecutive failures before giving up on "just retry" and surfacing the pairing window instead
// — otherwise this was a genuinely invisible failure: the tray icon quietly said "retrying…"
// forever with no indication anything needed the operator's attention, and the ONLY way back into
// pairing was a tray menu item nothing prompted them to look for.
const RECONNECT_FAILURE_THRESHOLD = 3;
let consecutiveFailures = 0;

function connectCable(config) {
  const url = `${config.cableUrl}?token=${encodeURIComponent(config.token)}`;
  // Rails' Action Cable rejects any connection whose Origin doesn't match either an explicitly
  // configured allow-list or the request's own Host (`allow_same_origin_as_host`, Rails' own
  // default) — confirmed live: with no Origin header at all (Node's `ws` sends none by default,
  // unlike a browser), the server closed every attempt with a bare "Page not found" 404, logged
  // client-side as a silent reconnect loop with no useful error. Sending Origin = serverUrl makes
  // this agent look like a same-origin request, which the server already trusts.
  cable = new WebSocket(url, { headers: { Origin: config.serverUrl } });

  cable.on("open", () => {
    cable.send(JSON.stringify({ command: "subscribe", identifier: CHANNEL_IDENTIFIER }));
  });

  cable.on("message", (raw) => {
    const data = JSON.parse(raw.toString());
    if (data.type === "confirm_subscription") {
      connected = true;
      consecutiveFailures = 0;
      setTrayStatus(`Connected (${config.stationName})`);
      startHeartbeat(config);
    } else if (data.type === "disconnect") {
      connected = false;
      setTrayStatus("Disconnected");
    } else if (data.message) {
      handleChannelMessage(config, data.message);
    }
  });

  cable.on("close", () => {
    connected = false;
    consecutiveFailures += 1;

    if (consecutiveFailures >= RECONNECT_FAILURE_THRESHOLD) {
      setTrayStatus("Needs re-pairing");
      openPairingWindow({
        serverUrl: config.serverUrl,
        reason: "Lost connection repeatedly — this station's pairing may have been revoked. Enter a fresh code below."
      });
      return; // stop retrying until the operator re-pairs (or the app is quit/restarted)
    }

    setTrayStatus("Disconnected — retrying…");
    setTimeout(() => connectCable(config), 5_000);
  });

  cable.on("error", () => {
    // 'close' fires right after — the retry loop lives there, not here.
  });
}

function startHeartbeat(config) {
  setInterval(() => {
    if (connected) sendChannelMessage({ action: "heartbeat" });
  }, HEARTBEAT_INTERVAL_MS);
}

function sendChannelMessage(payload) {
  cable.send(JSON.stringify({ command: "message", identifier: CHANNEL_IDENTIFIER, data: JSON.stringify(payload) }));
}

async function handleChannelMessage(config, message) {
  if (message.action !== "print_job") return;

  try {
    const pdfPath = await fetchBadgePdf(config, message.job_id);
    await printPdf(pdfPath, config.printerName);
    sendChannelMessage({ action: "job_update", job_id: message.job_id, status: "succeeded" });
  } catch (error) {
    sendChannelMessage({ action: "job_update", job_id: message.job_id, status: "failed", error: String(error.message || error) });
  }
}

async function fetchBadgePdf(config, jobId) {
  const response = await fetch(`${config.serverUrl}/print_agent/print_jobs/${jobId}/badge`, {
    headers: { Authorization: `Bearer ${config.token}` }
  });
  if (!response.ok) throw new Error(`badge fetch failed: HTTP ${response.status}`);

  const buffer = Buffer.from(await response.arrayBuffer());
  const filePath = path.join(os.tmpdir(), `eventmeet-badge-${jobId}.pdf`);
  fs.writeFileSync(filePath, buffer);
  return filePath;
}

// Chromium's native silent-print API (requirement.md §5.5.1: "webContents.print({ silent: true,
// deviceName, printBackground: true }) against a hidden window loading the rendered badge PDF") —
// the one piece of this app that's genuinely OS-native rather than a plain HTTP/WebSocket client.
function printPdf(pdfPath, deviceName) {
  return new Promise((resolve, reject) => {
    const printWindow = new BrowserWindow({ show: false });
    printWindow.loadFile(pdfPath);

    printWindow.webContents.on("did-finish-load", () => {
      const options = { silent: true, printBackground: true };
      if (deviceName) options.deviceName = deviceName;

      printWindow.webContents.print(options, (success, failureReason) => {
        printWindow.close();
        if (success) {
          resolve();
        } else {
          reject(new Error(failureReason || "print failed"));
        }
      });
    });
  });
}

ipcMain.handle("pair", async (_event, { serverUrl, pairingCode }) => {
  const response = await fetch(`${serverUrl}/print_agent/pair`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ pairing_code: pairingCode })
  });
  const body = await response.json();
  if (!response.ok) return { error: body.error || "Pairing failed." };

  const config = {
    serverUrl,
    token: body.token,
    cableUrl: body.cable_url,
    stationName: body.station_name,
    eventName: body.event_name,
    printerName: null
  };
  saveConfig(config);

  pairingWindow?.close();
  connectCable(config);
  return { ok: true };
});

app.whenReady().then(() => {
  // This is a menu-bar-only utility, not a Dock app — requirement.md §5.5.1's own framing
  // ("a system-tray/menu-bar presence"), not a window an operator alt-tabs to. Without this,
  // macOS still gives it a Dock icon by default (every Electron app does), which is exactly what
  // was confusing live: a Dock icon with nothing behind it once already paired, since the only
  // real UI is the Tray icon up in the menu bar. `app.dock` doesn't exist on Windows/Linux.
  app.dock?.hide();

  tray = new Tray(path.join(__dirname, "assets", "tray-icon.png"));
  setTrayStatus("Not paired");

  const config = loadConfig();
  if (config) {
    connectCable(config);
  } else {
    openPairingWindow();
  }
});

app.on("window-all-closed", (event) => {
  // A print-station daemon stays alive in the tray even with no windows open — quitting is
  // explicit (the tray menu's own Quit item), not implied by closing the pairing window.
  event.preventDefault();
});
