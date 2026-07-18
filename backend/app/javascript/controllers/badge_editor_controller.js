import { Controller } from "@hotwired/stimulus"
import grapesjs from "grapesjs"
import grapesjsPresetWebpage from "grapesjs-preset-webpage"
import grapesjsBlocksBasic from "grapesjs-blocks-basic"

// Phase 8 — Badge Design & Printing (requirement.md §4.10, §5.5): "GrapesJS integration wrapped
// in a single Stimulus controller ... no React island." grapesjs-preset-webpage supplies the
// layer manager/style manager/code-view/undo-redo panel chrome out of the box (per requirement.md
// §5.5's own reasoning for choosing GrapesJS at all — reinventing that UI would be pure effort);
// grapesjs-blocks-basic adds generic text/image/container blocks. The only genuinely custom part
// is the token block set below, one per placeholder BadgeReformService substitutes
// (app/services/badge_reform_service.rb) — dragging one onto the canvas is how an organizer
// places $NAME$/$PHOTO$/etc. without typing a token string by hand.
// $PHOTO$/$QRCODE$/$BARCODE$ are never real, loadable image URLs at design time — only
// BadgeReformService (app/services/badge_reform_service.rb) turns them into real `data:` URIs,
// server-side, when rendering an actual participant's badge. Putting the bare token string
// straight into an <img src="..."> means the *browser* also tries to load it as a URL and shows
// its native broken-image icon — confirmed live, this is genuinely what a saved/reloaded badge
// with a Photo or QR Code token looks like on the canvas: a broken-image glyph, not a design.
// These inline SVGs stand in for that at design time only; the real token always goes back into
// `src` before saving (see #restoreTokensBeforeExtract) or BadgeReformService would have nothing
// to substitute.
const TOKEN_PLACEHOLDER_SVGS = {
  "$PHOTO$": svgDataUri(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">' +
      '<rect width="100" height="100" fill="#e9ecef"/>' +
      '<circle cx="32" cy="30" r="11" fill="#adb5bd"/>' +
      '<path d="M8 82 L38 48 L58 68 L74 52 L92 82 Z" fill="#adb5bd"/>' +
      '<text x="50" y="94" font-size="11" text-anchor="middle" fill="#868e96" font-family="sans-serif">PHOTO</text>' +
    "</svg>"
  ),
  "$QRCODE$": svgDataUri(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">' +
      '<rect width="100" height="100" fill="#fff" stroke="#adb5bd" stroke-width="3"/>' +
      '<g fill="#343a40">' +
        '<rect x="10" y="10" width="22" height="22"/><rect x="16" y="16" width="10" height="10" fill="#fff"/>' +
        '<rect x="68" y="10" width="22" height="22"/><rect x="74" y="16" width="10" height="10" fill="#fff"/>' +
        '<rect x="10" y="68" width="22" height="22"/><rect x="16" y="74" width="10" height="10" fill="#fff"/>' +
        '<rect x="40" y="14" width="8" height="8"/><rect x="55" y="26" width="8" height="8"/>' +
        '<rect x="40" y="42" width="18" height="18"/><rect x="70" y="46" width="8" height="8"/>' +
        '<rect x="70" y="68" width="20" height="8"/><rect x="46" y="70" width="8" height="18"/>' +
      "</g>" +
    "</svg>"
  ),
  "$LOGO$": svgDataUri(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">' +
      '<rect width="100" height="100" fill="#e9ecef"/>' +
      '<circle cx="50" cy="42" r="20" fill="none" stroke="#adb5bd" stroke-width="4"/>' +
      '<text x="50" y="80" font-size="12" text-anchor="middle" fill="#868e96" font-family="sans-serif">LOGO</text>' +
    "</svg>"
  ),
  "$BARCODE$": svgDataUri(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 60">' +
      '<rect width="160" height="60" fill="#fff" stroke="#adb5bd" stroke-width="2"/>' +
      '<g fill="#343a40">' +
        [ 10, 16, 26, 32, 40, 47, 58, 64, 73, 80, 90, 96, 104, 111, 122, 128, 137, 144 ]
          .map((x, i) => `<rect x="${x}" y="10" width="${[ 3, 6, 2, 4 ][i % 4]}" height="40"/>`)
          .join("") +
      "</g>" +
    "</svg>"
  ),
}
// $QRCODE_GOVT_ID$/$QRCODE_ORG_ID$/$BARCODE_GOVT_ID$/$BARCODE_ORG_ID$ (requirement gap-fill:
// dedicated govt-ID/org-ID scan codes, distinct from $QRCODE$/$BARCODE$'s fixed hex_id/govt_id
// meaning) reuse the exact same design-time placeholder graphic as their generic counterpart —
// visually a QR code is a QR code regardless of what data it encodes, only the block palette
// label tells the organizer which is which; no separate SVG art needed.
TOKEN_PLACEHOLDER_SVGS["$QRCODE_GOVT_ID$"] = TOKEN_PLACEHOLDER_SVGS["$QRCODE$"]
TOKEN_PLACEHOLDER_SVGS["$QRCODE_ORG_ID$"] = TOKEN_PLACEHOLDER_SVGS["$QRCODE$"]
TOKEN_PLACEHOLDER_SVGS["$BARCODE_GOVT_ID$"] = TOKEN_PLACEHOLDER_SVGS["$BARCODE$"]
TOKEN_PLACEHOLDER_SVGS["$BARCODE_ORG_ID$"] = TOKEN_PLACEHOLDER_SVGS["$BARCODE$"]
// The plain "QR Code"/"Barcode" blocks (generic $QRCODE$/$BARCODE$ — always hex_id/govt_id,
// regardless of what the organizer meant) were dropped from the palette in #registerTokenBlocks
// below — Govt ID/Org ID are the only scan-code meanings organizers actually want to place, so
// offering an unlabeled generic one too was just a confusing, redundant third option. Their
// $QRCODE$/$BARCODE$ placeholder entries stay in this map regardless: BadgeReformService's own
// substitution for those two tokens is unchanged (see its own comment — existing badges/check-in
// scanning still depend on them), so a badge designed before this change still needs
// #applyPlaceholdersToLoadedContent to find a placeholder graphic for them on reopen.

function svgDataUri(svg) {
  return `data:image/svg+xml,${encodeURIComponent(svg)}`
}

// The exact CSS px-per-cm ratio Chrome (and every browser) uses to resolve a physical "cm" CSS
// unit — a fixed spec constant (96 CSS px per inch, 2.54cm per inch), not something that varies.
// This has to be the *same* ratio BadgePdfService's Grover call implicitly uses when it sets the
// PDF page to `"#{width_cm}cm"` — a token positioned at `top: 100px` only ends up in the same
// relative spot on the printed badge as it appears on this canvas if both are measured against
// identical real px dimensions. Any other on-screen scale (e.g. a fixed "70vh" canvas, unrelated
// to the badge's actual size) would make the editor genuinely lie about the printable area — a
// token placed "in the middle" of a much larger canvas than the real badge would print far
// outside the actual badge, or not print at all.
const CM_TO_PX = 96 / 2.54

// Only bottom-right/bottom-center/center-right resize handles — every one grows a token without
// ever moving its top-left corner. See the comment on #clampLiveResize for why the other five
// handles (which legitimately need to move the anchor as part of a correct resize) are disabled
// rather than supported: GrapesJS's own live coordinate math for those turned out to be unreliable
// in this canvas, and top-left is knowable without trusting it at all if it just never moves.
const RESIZABLE_HANDLES = { tl: false, tc: false, tr: false, cl: false, bl: false, bc: true, cr: true, br: true }

export default class extends Controller {
  static targets = ["canvas", "contentField", "widthInput", "heightInput", "backgroundInput"]
  static values = { widthCm: Number, heightCm: Number, backgroundImageUrl: String }

  connect() {
    this.editor = grapesjs.init({
      container: this.canvasTarget,
      height: "70vh",
      fromElement: false,
      storageManager: false,
      plugins: [grapesjsPresetWebpage, grapesjsBlocksBasic],
      pluginsOpts: {
        [grapesjsPresetWebpage]: { modalImportTitle: "Import HTML/CSS" },
        [grapesjsBlocksBasic]: {},
      },
    })

    this.registerTokenBlocks()

    // Confirmed live: without this, dragging a resize handle (or moving a token) past the
    // canvas edge is completely unconstrained — a token can grow or move to any size/position,
    // even one that dwarfs the entire badge. That's not just a cosmetic overflow: a token sized
    // to cover the whole canvas sits on top of every other token in the same screen region and
    // intercepts every click there, so the *next* token underneath it becomes unselectable and
    // undraggable too ("goes out of the defined size ... then I am not able to drag that item
    // into blank template" — there's no longer any blank, click-through canvas left under it).
    // `component:styleUpdate` fires once per gesture, after GrapesJS has already committed the
    // drag/resize's final top/left/width/height to the component's style (confirmed live via a
    // counter — one event per mouse-up, not one per intermediate mouse-move) — the right moment
    // to correct it back within bounds, for both resize (changes width/height, and top/left when
    // resizing from a top/left handle) and move (changes only top/left) alike, since both write
    // through the same style-setting path.
    this.editor.on("component:styleUpdate", (component) => this.clampTokenToCanvas(component))

    // The above only corrects the *final* size/position, once, after the mouse is released —
    // confirmed live that this left a visible glitch during an actual resize drag: GrapesJS's own
    // resize preview (the blue selection/handle outline, plus the token itself) tracks the live,
    // uncapped size while the mouse is still down, so growing a token past the canvas edge shows
    // it (and its selection box) sitting outside the badge for the whole gesture, only snapping
    // back at the very end. `component:resize:update` fires repeatedly *during* the gesture
    // (confirmed live: ~20 times across one drag, once per mouse-move step, unlike
    // `component:styleUpdate`'s single end-of-gesture firing) and hands over an `updateStyle`
    // function specifically meant to let a listener override the size GrapesJS was about to apply
    // for that step — calling it here with the already-clamped values keeps the live preview
    // itself pinned to the canvas edge the whole time a token is being resized, not just after.
    //
    // `component:resize:init` fires once, right when a resize gesture starts, before GrapesJS has
    // written anything back to the component yet — the one point where `component.getStyle()` is
    // still guaranteed correct. See `clampLiveResize` for why this captured anchor, not anything
    // GrapesJS reports mid-gesture, is what every tick clamps against.
    this.editor.on("component:resize:init", (data) => {
      const style = data.component.getStyle()
      this.resizeAnchor = { top: parseFloat(style.top) || 0, left: parseFloat(style.left) || 0 }
    })
    this.editor.on("component:resize:update", (data) => this.clampLiveResize(data))

    // Bug report: "Basic elements should behave same as Badge tokens. I am able to drag and
    // drop element but [not] able to drag anywhere — it should work same as badge tokens."
    // grapesjs-blocks-basic's own blocks (Text, 1 Column, Quote, Link, ...) carry none of
    // #registerTokenBlocks' `dmode: "absolute"` treatment — GrapesJS's default Sorter behavior
    // for those is "insert into document flow near what you're hovering over" (right for a
    // webpage, wrong here), so once dropped they can never be freely repositioned again the way
    // a token can. `block:drag:stop` fires once per drop with the just-placed component (per
    // GrapesJS's own BlockManager source — the second, block-model argument isn't needed here);
    // converting it to the exact same free-floating shape every token block already has is what
    // makes every block in the palette, not just "Badge Tokens," behave identically after drop.
    this.editor.on("block:drag:stop", (component) => this.freeFloatComponent(Array.isArray(component) ? component[0] : component))

    // `grapesjs.init()` returns before the canvas iframe's own document has actually finished
    // loading (a real, unavoidably-async browser operation — creating and loading an iframe is
    // never synchronous) — confirmed live: calling setComponents()/find("img") immediately after
    // init() appeared to silently do nothing on a fresh page load specifically (no exception,
    // just zero effect — while the exact same call re-run manually moments later worked fine,
    // because by then the canvas had long since finished loading on its own). `onReady` is
    // GrapesJS's own race-condition-proof hook for this: it fires the callback immediately if the editor
    // (including the canvas frame — `readyCanvas`, not just general init) is already ready, or
    // waits for the same `load` event otherwise, so it's correct whether the canvas happens to be
    // ready yet or not by the time this runs.
    this.editor.onReady(() => {
      // Constrains the canvas to the badge's real physical size. Deliberately *not* done via
      // GrapesJS's own Device Manager (register a "Badge" device, `editor.setDevice(...)`) —
      // confirmed live that this actively breaks things: Device Manager is built for responsive
      // *web* design (preview the same one document at different simulated viewport widths), so
      // any style set while a custom device is active gets wrapped in a `@media (max-width:
      // ...)` query scoped to that device's width instead of applying globally — the wrapper's
      // own `position: relative` below silently stopped applying outside that query, and in one
      // run `setComponents()` right after `setDevice()` left the wrapper completely empty.
      // Resizing the raw iframe DOM element directly avoids the Style Manager (and its
      // responsive-breakpoint machinery) entirely — it's not a GrapesJS "style," just the actual
      // element's own width/height, exactly like setting them on any other iframe.
      this.sizeFrameToBadge()

      // Absolutely-positioned children (every token block above, and anything else made
      // absolute via the Style Manager) position relative to their nearest positioned ancestor —
      // without this, that's the iframe's own root, not the badge canvas itself, which still
      // *looks* right in the editor (there's nothing else on the page) but would silently break
      // the instant this canvas is nested in anything else. The wrapper is the actual badge
      // surface (BadgePdfService renders exactly what this exports), so it's the correct anchor.
      this.editor.getWrapper().setStyle({ position: "relative" })

      // Seeds the canvas with whatever background is already attached (rails_blob_path — this
      // page is an ordinary authenticated browser tab, so a signed redirect URL resolves fine
      // here, unlike the standalone-render contexts #applyBackgroundPreview's own comment
      // describes). Skipped when there's nothing attached yet — an empty string would just no-op
      // inside #applyBackgroundPreview anyway, but there's nothing to seed either way.
      if (this.backgroundImageUrlValue) this.applyBackgroundPreview(this.backgroundImageUrlValue)

      // The hidden field's own `value` already carries the object's current `content` (Rails
      // populates it from the model, same as any other f.hidden_field) — read it back rather
      // than duplicating the same, potentially large, HTML+CSS blob a second time as a data
      // attribute.
      const initialContent = this.contentFieldTarget.value
      if (initialContent) {
        this.editor.setComponents(initialContent)
        this.applyPlaceholdersToLoadedContent()
        this.applyComponentDefaultsToLoadedContent()
      }
    })
  }

  disconnect() {
    this.editor?.destroy()
  }

  // Sets the actual iframe element's own width/height — not a GrapesJS "device" or "style," just
  // the element's real CSS box, exactly as if it were any other iframe on the page. Anything
  // inside sized as a percentage (the token blocks' own `width:100%;height:100%` root wrapper)
  // naturally conforms to this from the browser's own normal layout, no further wiring needed.
  sizeFrameToBadge() {
    const frameEl = this.editor.Canvas.getFrameEl()
    frameEl.style.width = `${Math.round(this.widthCmValue * CM_TO_PX)}px`
    frameEl.style.height = `${Math.round(this.heightCmValue * CM_TO_PX)}px`
  }

  // Wired to the Width (cm)/Height (cm) number fields (input->badge-editor#resizeCanvas) — the
  // organizer shouldn't have to save and reopen the page just to see the canvas reflect a size
  // change they just made.
  resizeCanvas() {
    const width = parseFloat(this.widthInputTarget.value)
    const height = parseFloat(this.heightInputTarget.value)
    if (!width || !height) return

    const frameEl = this.editor.Canvas.getFrameEl()
    frameEl.style.width = `${Math.round(width * CM_TO_PX)}px`
    frameEl.style.height = `${Math.round(height * CM_TO_PX)}px`
  }

  // **Bug fix**: the Background image file field saved and attached correctly (Admin::
  // BadgesController#apply_uploads) and printed correctly (BadgePdfService), but the canvas
  // itself never reflected it at all — no code path set anything from it, so an organizer
  // uploading a background saw literally no visible change and reasonably concluded it wasn't
  // working. Reads the freshly-picked file straight off the input via FileReader — no need to
  // save and reopen the page first to see it, same "what's visible while designing is what
  // actually prints" standard every other sizing/positioning behavior in this controller holds
  // to.
  previewBackgroundImage() {
    const file = this.backgroundInputTarget.files[0]
    if (!file) return

    const reader = new FileReader()
    reader.onload = () => this.applyBackgroundPreview(reader.result)
    reader.readAsDataURL(file)
  }

  // Sets the background as a plain, untracked style directly on the canvas iframe's own <body>
  // DOM element — deliberately NOT through GrapesJS's component style system (e.g. the
  // wrapper's `addStyle`, used elsewhere in this file), which would serialize it into
  // `getCss()`'s output and so into the saved `content` string itself. That would be actively
  // wrong here: a freshly-picked file's preview URL is a `data:` URI good only for this one
  // browser tab, and even the persisted attachment's own `rails_blob_path` is a signed,
  // session-relative redirect that has no business being embedded into `content` permanently —
  // BadgePdfService/the preview modal already composite the real background independently, from
  // the attachment itself (#background_image_data_uri, HasBadgeMapping), every time either
  // renders. This is purely a such-that-you-can-see-it-while-designing convenience, same
  // reasoning `sizeFrameToBadge` already uses for going straight to the raw iframe element
  // rather than through GrapesJS's Device Manager.
  applyBackgroundPreview(url) {
    const body = this.editor.Canvas.getBody()
    if (!body) return

    body.style.backgroundImage = url ? `url(${url})` : ""
    body.style.backgroundSize = "cover"
    body.style.backgroundPosition = "center"
  }

  // Keeps a token's rendered box fully within the badge's real printable area after any drag or
  // resize. Uses the element's actual rendered `offsetWidth`/`offsetHeight` rather than parsing
  // `style.width`/`height` directly — a token dropped from a text block (Name, Other Field 1-3)
  // never gets an explicit width/height style at all until it's manually resized, so its true
  // on-canvas size only exists as rendered layout, not as a CSS value this could parse. Width/
  // height are clamped first (so an oversized resize shrinks back to fit), then left/top against
  // that already-clamped size — one pass, not two separate corrections a user would see as a
  // double snap.
  clampTokenToCanvas(component) {
    const style = component.getStyle()
    if (style.position !== "absolute") return

    const el = component.getEl()
    if (!el) return

    const canvasWidth = Math.round(this.widthCmValue * CM_TO_PX)
    const canvasHeight = Math.round(this.heightCmValue * CM_TO_PX)
    const nextStyle = {}

    let width = el.offsetWidth
    if (width > canvasWidth) {
      nextStyle.width = `${canvasWidth}px`
      width = canvasWidth
    }

    let height = el.offsetHeight
    if (height > canvasHeight) {
      nextStyle.height = `${canvasHeight}px`
      height = canvasHeight
    }

    const top = parseFloat(style.top) || 0
    const left = parseFloat(style.left) || 0
    const clampedLeft = Math.min(Math.max(left, 0), Math.max(canvasWidth - width, 0))
    const clampedTop = Math.min(Math.max(top, 0), Math.max(canvasHeight - height, 0))
    if (clampedLeft !== left) nextStyle.left = `${clampedLeft}px`
    if (clampedTop !== top) nextStyle.top = `${clampedTop}px`

    if (Object.keys(nextStyle).length > 0) component.addStyle(nextStyle)
  }

  // Live counterpart to #clampTokenToCanvas, run on every `component:resize:update` tick instead
  // of once at the end — without this, the resize handle you're dragging (and its blue selection
  // outline) visibly leaves the canvas for the whole gesture and only jumps back once the mouse is
  // released.
  //
  // **Found and fixed three times while building this** — worth spelling out since the final shape
  // looks stranger than the problem sounds. First: an early version read `data.el.style.top/left/
  // width/height` directly and got empty strings on every tick — GrapesJS positions components
  // through a generated CSS rule (`#<id>{top:...}` in the canvas's own stylesheet), not the
  // element's inline `style` attribute. Second: switched to trusting `component.getStyle()` (the
  // model's committed style) merged with `data.style` for position — looked right, but a *modest,
  // entirely in-bounds* resize still snapped a token's left edge clear across the canvas. Traced it
  // tick-by-tick: for a plain bottom-right-handle drag — which never moves the anchor corner, by
  // definition — `data.style.left` held a large, constant, obviously-bogus offset (e.g. `-239px`)
  // from the very first tick, and — this is the part that broke the second fix — GrapesJS itself
  // (not this listener) writes that bogus value straight into the component's *committed* style
  // before the second tick even fires, confirmed by logging `component.getStyle()` at the top of
  // this handler and watching it read the correct original position on tick 1, then the same wrong
  // `-239px` on every tick after. So `component.getStyle()` mid-gesture isn't a reliable fallback
  // either, once GrapesJS has already smeared bad data into it. Root cause: sizing the badge's
  // iframe by setting its raw DOM element's `style.width`/`height` directly (`sizeFrameToBadge`/
  // `resizeCanvas` — needed to avoid the Device Manager's own, worse breakage, see the comment on
  // that method) never goes through GrapesJS's own resize/device-change flow, so its Canvas
  // module's internal cached frame offset goes stale and its coordinate math for top/left
  // specifically comes out wrong — `data.style.width`/`.height` stayed correct in every test, only
  // position math was affected.
  //
  // Given GrapesJS's own top/left computation can't be trusted at all here, the fix stops trying to
  // read a live position from anywhere and instead pins it: `component:resize:init` (registered in
  // `connect`) captures the component's real top/left once, the instant the gesture starts —
  // before GrapesJS has written anything bad — into `this.resizeAnchor`. Every `resize:update` tick
  // then forces top/left back to that captured value and only lets width/height change, clamped to
  // whatever room is actually left between the anchor and the canvas edge. The one behavior change
  // this implies — resizing always grows from the token's original top-left corner, never from
  // whichever corner handle was actually dragged — is deliberate, not a leftover limitation:
  // `registerTokenBlocks` below restricts every token to only the bottom-right/bottom-center/
  // center-right handles, so top-left never needing to move is true by construction, not just true
  // often enough to get away with ignoring the other handles.
  clampLiveResize(data) {
    const { component, el } = data
    if (!component || !el || !this.resizeAnchor) return

    const canvasWidth = Math.round(this.widthCmValue * CM_TO_PX)
    const canvasHeight = Math.round(this.heightCmValue * CM_TO_PX)
    const { top, left } = this.resizeAnchor

    const width = parseFloat(data.style.width) || el.offsetWidth
    const height = parseFloat(data.style.height) || el.offsetHeight
    const maxWidth = Math.max(canvasWidth - left, 0)
    const maxHeight = Math.max(canvasHeight - top, 0)

    data.updateStyle({
      ...data.style,
      top: `${top}px`,
      left: `${left}px`,
      width: `${Math.min(width, maxWidth)}px`,
      height: `${Math.min(height, maxHeight)}px`,
    })
  }

  // Converts a just-dropped component (any block, not only Badge Tokens — see the
  // `block:drag:stop` listener registered in `connect`) into the same absolute, freely
  // draggable/resizable shape #registerTokenBlocks already declares up front for token blocks.
  // Anchored to the component's own current rendered position (`offsetTop`/`offsetLeft` — already
  // wherever GrapesJS just placed it, in-flow or otherwise) so converting it doesn't visibly move
  // or jump the element the organizer just dropped; only *future* drags/resizes change from here.
  // A no-op in practice for a token block (dmode/resizable/position are already exactly this, and
  // dmode:"absolute" already made GrapesJS drop it at the cursor position, so reading that back
  // and writing it straight through changes nothing) — applied unconditionally rather than
  // special-cased by block id/category so nothing in the palette is exempt.
  freeFloatComponent(component) {
    if (!component || !component.getEl) return

    const el = component.getEl()
    const top = el ? el.offsetTop : 0
    const left = el ? el.offsetLeft : 0

    component.set("dmode", "absolute")
    component.set("resizable", RESIZABLE_HANDLES)
    component.addStyle({ position: "absolute", top: `${top}px`, left: `${left}px` })
  }

  // Every block's `content` is a component definition object, not a raw HTML string — that's
  // what's needed for the two behaviors a badge canvas actually needs and a webpage canvas
  // doesn't: `style: { position: "absolute", ... }` is what makes GrapesJS's own drag-and-drop
  // Sorter switch from "insert into document flow near what you're hovering over" (its default,
  // right for a webpage) to "place it exactly where the cursor released" (right for a badge/
  // wristband, where every element sits at a fixed spot on a fixed physical canvas). The CSS
  // `position: absolute` alone does NOT do this — confirmed live, a component with that style but
  // no `dmode` still dropped at its block-defined default top/left, ignoring where it was
  // actually released. `dmode: "absolute"` (GrapesJS's own component-level drag-mode flag,
  // distinct from the CSS position property) is what actually makes the drop position — and
  // later, moving an already-placed component — follow the cursor.
  //
  // `resizable` adds the corner/edge resize handles GrapesJS shows on a selected component — off
  // by default for a plain text/span component (text normally auto-sizes to its content), which is
  // why it has to be set explicitly here rather than relying on a built-in default. Deliberately
  // *not* `true` (which would offer all 8 handles): only `br`/`bc`/`cr` — bottom-right,
  // bottom-center, center-right — are enabled, every one of which grows a token without ever
  // moving its top-left corner. See the long comment on #clampLiveResize for why: GrapesJS's own
  // live coordinate math for a handle that *does* move the anchor (top-left, top-right,
  // bottom-left) turned out to be unreliable in this canvas (sized by direct DOM manipulation
  // rather than GrapesJS's own Device flow), and every fix attempt that still trusted it produced
  // its own new corruption. Restricting to anchor-preserving handles sidesteps needing to trust
  // that math at all — top-left is knowable without asking GrapesJS anything.
  registerTokenBlocks() {
    const textBlock = (id, label, token, top) => ({
      id,
      label,
      category: "Badge Tokens",
      attributes: { class: "fa fa-tag" },
      content: {
        tagName: "span",
        type: "text",
        content: token,
        style: { position: "absolute", top: `${top}px`, left: "20px", "font-size": "16px", "white-space": "nowrap" },
        dmode: "absolute",
        resizable: RESIZABLE_HANDLES,
        draggable: true,
      },
    })

    // `src` is the design-time placeholder graphic, never the token itself — a real <img src>
    // holding a bare "$PHOTO$" string is what the browser tries (and fails) to load, showing its
    // native broken-image icon. `data-badge-token` carries the real token; #restoreTokensBeforeExtract
    // swaps it back into `src` right before every save, so BadgeReformService still substitutes
    // exactly the same token string it always has.
    const imageBlock = (id, label, token, top, width, height) => ({
      id,
      label,
      category: "Badge Tokens",
      attributes: { class: "fa fa-tag" },
      content: {
        tagName: "img",
        attributes: { src: TOKEN_PLACEHOLDER_SVGS[token], "data-badge-token": token },
        style: { position: "absolute", top: `${top}px`, left: "20px", width: `${width}px`, height: `${height}px`, "object-fit": "cover" },
        dmode: "absolute",
        resizable: RESIZABLE_HANDLES,
        draggable: true,
      },
    })

    const blocks = [
      textBlock("token-title", "Title", "$TITLE$", 20),
      textBlock("token-name", "Full Name", "$NAME$", 45),
      textBlock("token-first-name", "First Name", "$FIRST_NAME$", 70),
      textBlock("token-last-name", "Last Name", "$LAST_NAME$", 95),
      textBlock("token-designation", "Designation", "$DESIGNATION$", 120),
      textBlock("token-org-id", "Org ID", "$ORG_ID$", 145),
      textBlock("token-govt-id", "Govt ID", "$GOVT_ID$", 170),
      imageBlock("token-photo", "Photo", "$PHOTO$", 60, 100, 100),
      // Kept in the palette even though the per-badge Logo upload field is gone (removed from
      // app/views/admin/shared/_badge_editor.html.erb, below Background image) — $LOGO$ is still
      // a real, wanted token; it's just not organizer-uploaded per badge anymore. Planned to be
      // filled from the tenant's own account-level logo instead once that exists, the same way
      // $PHOTO$ is filled from the participant's own upload — not touching Badge#logo/
      // #attach_logo or BadgeReformService's own $LOGO$ substitution yet, since neither this
      // block nor that future tenant-logo wiring needs them removed to work.
      imageBlock("token-logo", "Logo", "$LOGO$", 60, 80, 80),
      imageBlock("token-qrcode-govt-id", "QR Code (Govt ID)", "$QRCODE_GOVT_ID$", 60, 90, 90),
      imageBlock("token-qrcode-org-id", "QR Code (Org ID)", "$QRCODE_ORG_ID$", 60, 90, 90),
      imageBlock("token-barcode-govt-id", "Barcode (Govt ID)", "$BARCODE_GOVT_ID$", 60, 160, 50),
      imageBlock("token-barcode-org-id", "Barcode (Org ID)", "$BARCODE_ORG_ID$", 60, 160, 50),
      textBlock("token-other1", "Other Field 1", "$OTHER1$", 195),
      textBlock("token-other2", "Other Field 2", "$OTHER2$", 220),
      textBlock("token-other3", "Other Field 3", "$OTHER3$", 245),
    ]

    blocks.forEach((block) => this.editor.BlockManager.add(block.id, block))
  }

  // A previously-saved badge's `content` (loaded via setComponents above) has the *real* token in
  // every image's `src` — that's what got persisted (see #restoreTokensBeforeExtract). Swap each
  // one to its design-time placeholder graphic here too, or reopening an existing badge is just
  // as broken-icon-covered as a freshly-dropped one would be without this.
  applyPlaceholdersToLoadedContent() {
    this.editor.getWrapper().find("img").forEach((imgComponent) => {
      const token = imgComponent.getAttributes().src
      const placeholder = TOKEN_PLACEHOLDER_SVGS[token]
      if (placeholder) {
        imgComponent.addAttributes({ src: placeholder, "data-badge-token": token })
      }
    })
  }

  // `dmode: "absolute"` and `RESIZABLE_HANDLES` above only reach a token dropped fresh from the
  // block palette — parsing *saved* HTML/CSS back into components (what
  // `setComponents(initialContent)` just did) isn't aware of either at all, since both are
  // GrapesJS component-model properties with no HTML/CSS representation to round-trip through.
  //
  // **Found and fixed after a user report**: "not able to drag" a token — but only ever a
  // *reopened* one; a freshly-dropped token dragged fine. Confirmed by reading the component's own
  // `dmode` right after `setComponents()`: `""` on every reloaded component, vs. `"absolute"` on
  // one just dropped from the palette. `dmode: "absolute"` is what makes GrapesJS's Sorter follow
  // the cursor for an already-placed component being moved (not just its initial drop, per the
  // comment on `registerTokenBlocks`) — without it, dragging a reloaded token silently does
  // nothing, no error, the toolbar's move handle just doesn't move anything. `resizable` has the
  // same gap for a different reason: a reopened image token would fall back to that tag type's own
  // built-in default (`resizable: { ratioDefault: 1 }` — *all* 8 handles, including the ones
  // #clampLiveResize depends on never being offered at all) and a reopened text token would have no
  // resize handles whatsoever (plain text has none by default). Reapplying both here keeps a
  // reloaded badge exactly as drag-and-resize-constrained as a freshly-designed one.
  applyComponentDefaultsToLoadedContent() {
    this.editor.getWrapper().components().forEach((component) => {
      component.set("dmode", "absolute")
      component.set("resizable", RESIZABLE_HANDLES)
    })
  }

  // Inverse of the above — every image's `src` on the canvas is a design-time placeholder, not
  // the real token, so it has to be restored before extracting HTML or BadgeReformService would
  // have a placeholder SVG data URI to substitute against instead of "$PHOTO$"/"$QRCODE$"/
  // "$BARCODE$", and every badge would render blank. `data-badge-token` itself is removed rather
  // than left in the saved content — BadgeReformService's substitution is a plain string replace
  // across the whole content, so leaving it in would mean every occurrence of the token (the
  // `data-badge-token` attribute *and* `src`) gets the substituted base64 data duplicated into
  // the final HTML, not just once.
  restoreTokensBeforeExtract() {
    this.editor.getWrapper().find("img[data-badge-token]").forEach((imgComponent) => {
      const token = imgComponent.getAttributes()["data-badge-token"]
      imgComponent.addAttributes({ src: token })
      imgComponent.removeAttributes([ "data-badge-token" ])
    })
  }

  // Combines the canvas's HTML + CSS into the one `content` string BadgeReformService substitutes
  // tokens into and Grover renders — a plain Rails form submit from here on, no fetch/JS save.
  save(event) {
    event.preventDefault()
    this.restoreTokensBeforeExtract()
    const html = this.editor.getHtml()
    const css = this.editor.getCss()
    this.contentFieldTarget.value = `${html}<style>${css}</style>`
    this.element.closest("form").requestSubmit()
  }
}
