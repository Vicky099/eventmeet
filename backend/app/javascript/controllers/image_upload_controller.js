import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

// True browser-to-storage-service direct upload (real byte-level progress via an XHR `progress`
// listener), replacing a plain <input type="file"> + full-page-submit relay. Ported from the same
// pattern already proven out in the sibling shopmate-backend project's own
// image_upload_controller.js — a hand-rolled DirectUpload call (not Rails' `direct_upload: true`
// helper, which auto-wires on the *form's* submit rather than the moment a file is picked, and
// offers no hook for progress events at all), kicked off from the file input's own `change`.
//
// Uploads through Admin::DirectUploadsController — this app's own authenticated, tenant-aware
// replacement for the stock ActiveStorage::DirectUploadsController — not the framework default,
// so the resulting blob still lands under this app's tenant-namespaced key (requirement.md §4.2)
// instead of a random token; see that controller's own comment for why the stock one can't do
// that. `data-direct-upload-url` on the file input already carries that controller's URL with the
// right `scope[type]`/`scope[event_id]` baked in server-side (ERB), same as
// `data-blob-field-name` carries the real form field name — this controller doesn't compute
// either, just reads them off whichever input changed.
//
// The file input itself carries NO `name` attribute (file_field ..., name: nil in the view) — the
// raw file is never form-submitted at all; only the signed_id this produces, injected into
// blobContainer below under the real field name once the direct upload finishes, ever reaches the
// server.
export default class extends Controller {
  static targets = ["fileInput", "uploadProgress", "progressBar", "uploadStatus", "blobContainer", "cameraModal", "video", "canvas", "cameraError"]

  disconnect() {
    this.stopCamera()
  }

  // Camera-capture button (currently only wired up next to Photo, admin/participants/
  // _dynamic_fields.html.erb) — opens a live getUserMedia() feed in a modal. Bootstrap's own JS
  // global (window.bootstrap, app/javascript/application.js), same as confirm_dialog_controller.js/
  // download_progress_controller.js already reach for programmatic modal control.
  async openCamera(event) {
    event.preventDefault()
    if (this.hasCameraErrorTarget) this.cameraErrorTarget.hidden = true

    this.cameraModal = bootstrap.Modal.getOrCreateInstance(this.cameraModalTarget)
    this.cameraModal.show()

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "user" } })
      this.videoTarget.srcObject = this.stream
    } catch (error) {
      if (this.hasCameraErrorTarget) {
        this.cameraErrorTarget.textContent = "Couldn't access the camera — check your browser's camera permission for this site."
        this.cameraErrorTarget.hidden = false
      }
    }

    this.cameraModalTarget.addEventListener("hidden.bs.modal", () => this.stopCamera(), { once: true })
  }

  // Draws the current video frame to a hidden canvas, turns it into a File, and feeds it into the
  // same hidden file input a manual file pick uses — dispatching `change` there runs the exact
  // same #fileSelected direct-upload path below, so a captured photo auto-uploads exactly like a
  // chosen one, not a separate code path to keep in sync.
  capturePhoto() {
    const video = this.videoTarget
    if (!video.videoWidth) return

    const canvas = this.canvasTarget
    canvas.width = video.videoWidth
    canvas.height = video.videoHeight
    canvas.getContext("2d").drawImage(video, 0, 0)

    canvas.toBlob((blob) => {
      if (!blob) return

      const file = new File([ blob ], `photo-${Date.now()}.jpg`, { type: "image/jpeg" })
      const dataTransfer = new DataTransfer()
      dataTransfer.items.add(file)
      this.fileInputTarget.files = dataTransfer.files
      this.fileInputTarget.dispatchEvent(new Event("change", { bubbles: true }))

      this.cameraModal.hide()
    }, "image/jpeg", 0.92)
  }

  stopCamera() {
    if (this.stream) {
      this.stream.getTracks().forEach((track) => track.stop())
      this.stream = null
    }
  }

  fileSelected(event) {
    const file = event.target.files[0]
    if (!file) return

    if (this.hasUploadStatusTarget) this.uploadStatusTarget.innerHTML = ""
    if (this.hasUploadProgressTarget) this.uploadProgressTarget.hidden = false
    if (this.hasProgressBarTarget) this.progressBarTarget.style.width = "0%"
    if (this.hasBlobContainerTarget) this.blobContainerTarget.innerHTML = ""

    const uploadUrl = event.target.dataset.directUploadUrl
    const blobFieldName = event.target.dataset.blobFieldName

    const delegate = {
      directUploadWillStoreFileWithXHR: (request) => {
        request.upload.addEventListener("progress", ({ loaded, total }) => {
          const percent = total > 0 ? Math.round((loaded / total) * 100) : 0
          if (this.hasProgressBarTarget) this.progressBarTarget.style.width = `${percent}%`
        })
      },
    }

    const upload = new DirectUpload(file, uploadUrl, delegate)
    upload.create((error, blob) => {
      if (this.hasUploadProgressTarget) this.uploadProgressTarget.hidden = true

      if (error) {
        if (this.hasUploadStatusTarget) {
          this.uploadStatusTarget.innerHTML = `<span class="text-danger small"><i class="bx bx-error-circle me-1"></i>Upload failed — ${error}</span>`
        }
        return
      }

      if (this.hasBlobContainerTarget) {
        this.blobContainerTarget.innerHTML = ""
        const hiddenField = document.createElement("input")
        hiddenField.type = "hidden"
        hiddenField.name = blobFieldName
        hiddenField.value = blob.signed_id
        this.blobContainerTarget.appendChild(hiddenField)
      }
      if (this.hasUploadStatusTarget) {
        this.uploadStatusTarget.innerHTML = `<span class="text-success small"><i class="bx bx-check me-1"></i>Uploaded</span>`
      }
      // The raw File this <input> is holding must not ride along when the form eventually
      // submits — it has no `name` so it wouldn't be sent as `participant[photo]` etc. either
      // way, but clearing it also resets the picker's own displayed filename, which otherwise
      // stays showing a file that was never actually part of the submission.
      event.target.value = ""
    })
  }
}
