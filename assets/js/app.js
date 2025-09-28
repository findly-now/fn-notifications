// LiveView JavaScript setup
import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: {}
})

// Show progress bar on live navigation and form submits - using Findly Now colors
topbar.config({
  barColors: {
    0: "#4F46E5",     // Indigo 600 (primary)
    ".5": "#10B981",  // Emerald 500 (secondary)
    "1.0": "#FBBF24"  // Amber 400 (accent)
  },
  shadowColor: "rgba(79, 70, 229, .3)"
})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Connect if there are any LiveViews on the page
liveSocket.connect()

// Expose liveSocket on window for web console debug logs and latency simulation
window.liveSocket = liveSocket