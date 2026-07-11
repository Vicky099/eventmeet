import { Controller } from "@hotwired/stimulus"

// Auto-dismisses each flash toast (shared/_flash.html.erb) after its data-timeout (default 6s),
// fading out first rather than just vanishing mid-read. The close button
// (data-action="flash#dismiss") dismisses on demand the same way, so there's one removal path
// whether the toast timed out or was closed manually.
export default class extends Controller {
  static targets = ["toast"]

  connect() {
    this.toastTargets.forEach((toast) => this.schedule(toast))
  }

  schedule(toast) {
    const timeout = parseInt(toast.dataset.timeout, 10) || 6000
    setTimeout(() => this.remove(toast), timeout)
  }

  dismiss(event) {
    this.remove(event.target.closest('[data-flash-target="toast"]'))
  }

  remove(toast) {
    if (!toast || !toast.isConnected) return
    toast.classList.add("flash-toast-leaving")
    toast.addEventListener("animationend", () => toast.remove(), { once: true })
  }
}
