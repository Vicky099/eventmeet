import { Controller } from "@hotwired/stimulus"

// requirement.md revisit: "download will open modal and show the progress bar and once 100% done
// then modal will close automatically and xlsx will download." Wraps any download link that
// streams real bytes through this app (Admin::ExportFilesController#download, Admin::
// ImportFilesController#sample) instead of a plain, instant static-asset link. Real byte progress
// via the Fetch API's own streaming body reader (bytes read so far ÷ the response's own
// Content-Length) — not a fake/animated bar. Once the stream finishes, the fetched bytes are
// saved via a synthetic <a download> click (the actual browser "download," distinct from just
// navigating there) and the modal closes itself — data-controller="download-progress" lives once
// on shared/_console_shell's own #layout-wrapper (same shared-ancestor shape confirm-dialog
// already uses), so any download link anywhere in either console can opt in with a plain
// data-action, no per-page wrapper needed.
export default class extends Controller {
  static targets = ["modal", "bar", "percent", "label"]

  async start(event) {
    event.preventDefault()
    const trigger = event.currentTarget
    const url = trigger.href

    this.setProgress(0)
    this.labelTarget.textContent = "Preparing your download…"
    this.modal = bootstrap.Modal.getOrCreateInstance(this.modalTarget)
    this.modal.show()

    try {
      const response = await fetch(url)
      if (!response.ok) throw new Error(`Download failed (${response.status})`)

      const total = parseInt(response.headers.get("Content-Length") || "0", 10)
      const filename = this.filenameFrom(response, trigger)
      const reader = response.body.getReader()
      const chunks = []
      let received = 0

      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        chunks.push(value)
        received += value.length
        if (total > 0) this.setProgress(Math.round((received / total) * 100))
      }

      this.setProgress(100)
      this.labelTarget.textContent = "Download ready"
      this.saveBlob(new Blob(chunks), filename)

      setTimeout(() => this.modal.hide(), 400)
    } catch (error) {
      this.labelTarget.textContent = "Download failed — please try again."
      setTimeout(() => this.modal.hide(), 1500)
    }
  }

  setProgress(percent) {
    this.barTarget.style.width = `${percent}%`
    this.percentTarget.textContent = `${percent}%`
  }

  // The response's own Content-Disposition filename wins (the server already computes the real
  // one — ExportFile's own event-slug-and-date name, or the static sample-template name); the
  // trigger's data attribute is only a fallback for the unexpected case that header is missing.
  filenameFrom(response, trigger) {
    const disposition = response.headers.get("Content-Disposition") || ""
    const match = disposition.match(/filename="?([^";]+)"?/)
    return match?.[1] || trigger.dataset.downloadProgressFilenameParam || "download.xlsx"
  }

  saveBlob(blob, filename) {
    const blobUrl = URL.createObjectURL(blob)
    const link = document.createElement("a")
    link.href = blobUrl
    link.download = filename
    document.body.appendChild(link)
    link.click()
    link.remove()
    URL.revokeObjectURL(blobUrl)
  }
}
