import { Controller } from "@hotwired/stimulus"
import { jsQR } from "jsqr"

// Camera-based badge scanning — a check-in desk without a hardware barcode/RFID scanner (the
// device scan_input_controller's own keyboard-wedge flow assumes) still needs a way to scan a
// badge: a phone/tablet's own camera. Opt-in via a button, not started on page load — getUserMedia
// immediately prompts for camera permission the moment it's called, and forcing that prompt on
// every kiosk load would be hostile to a desk that's using a hardware scanner instead.
//
// Prefers the native BarcodeDetector API (covers both this app's badge formats — $QRCODE$ and
// $BARCODE$/Code 128, BadgeReformService's own two token kinds — with no bundle needed) where the
// browser has it; falls back to jsQR (QR-only, but works everywhere getUserMedia does — notably
// Safari/iOS, which doesn't ship BarcodeDetector). $QRCODE$ is the one format every badge is
// guaranteed to carry, so the jsQR fallback still covers the common case.
//
// Lives on the same <form> element as scan_input_controller (multiple Stimulus controllers on one
// element) and shares its identifier text field as a second target — a successful decode fills
// that field and submits the very same form, so direction/session/print selections already made
// on the page apply exactly as they would to a typed or hardware-scanned identifier.
//
// requirement.md revisit: "once it scan then close the camera immediately" — a decode stops the
// camera outright (not just a pause-and-resume debounce) rather than staying open for a next shot;
// scanning another badge is a deliberate second tap of the same toggle button. That also removes
// double-submit risk for free — with no stream left running, there's nothing left to re-decode the
// same badge from.
const SCAN_INTERVAL_MS = 200

export default class extends Controller {
  static targets = ["panel", "video", "canvas", "status", "toggleButton", "identifierInput"]

  connect() {
    this.stream = null
    this.rafId = null
    this.detector = null
    this.busy = false
    this.lastAttempt = 0
  }

  disconnect() {
    this.stop()
  }

  async toggle() {
    if (this.stream) {
      this.stop()
    } else {
      await this.start()
    }
  }

  async start() {
    this.panelTarget.hidden = false
    this.toggleButtonTarget.classList.add("is-active")
    this.setStatus("Starting camera…")

    if ("BarcodeDetector" in window) {
      try {
        this.detector = new BarcodeDetector({ formats: [ "qr_code", "code_128" ] })
      } catch {
        this.detector = null
      }
    }

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: "environment" } } })
    } catch {
      this.setStatus("Camera unavailable — check permission and try again.")
      this.panelTarget.hidden = true
      this.toggleButtonTarget.classList.remove("is-active")
      return
    }

    this.videoTarget.srcObject = this.stream
    await this.videoTarget.play()
    this.setStatus("Point the camera at the badge's QR code.")
    this.scanLoop()
  }

  stop() {
    if (this.rafId) cancelAnimationFrame(this.rafId)
    this.rafId = null
    if (this.stream) this.stream.getTracks().forEach((track) => track.stop())
    this.stream = null
    if (this.hasVideoTarget) this.videoTarget.srcObject = null
    if (this.hasPanelTarget) this.panelTarget.hidden = true
    if (this.hasToggleButtonTarget) this.toggleButtonTarget.classList.remove("is-active")
    this.setStatus("")
  }

  scanLoop() {
    this.rafId = requestAnimationFrame(() => this.scanFrame())
  }

  scanFrame() {
    this.scanLoop()
    if (this.busy) return
    if (this.videoTarget.readyState !== this.videoTarget.HAVE_ENOUGH_DATA) return

    const now = performance.now()
    if (now - this.lastAttempt < SCAN_INTERVAL_MS) return
    this.lastAttempt = now

    const width = this.videoTarget.videoWidth
    const height = this.videoTarget.videoHeight
    if (!width || !height) return

    this.canvasTarget.width = width
    this.canvasTarget.height = height
    const context = this.canvasTarget.getContext("2d")
    context.drawImage(this.videoTarget, 0, 0, width, height)

    this.busy = true
    this.detect(context, width, height).then((identifier) => {
      this.busy = false
      if (identifier) this.handleResult(identifier)
    })
  }

  async detect(context, width, height) {
    if (this.detector) {
      try {
        const barcodes = await this.detector.detect(this.canvasTarget)
        return barcodes[0]?.rawValue || null
      } catch {
        return null
      }
    }

    const imageData = context.getImageData(0, 0, width, height)
    return jsQR(imageData.data, width, height)?.data || null
  }

  handleResult(identifier) {
    this.identifierInputTarget.value = identifier
    this.element.requestSubmit()
    this.stop()
  }

  setStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
