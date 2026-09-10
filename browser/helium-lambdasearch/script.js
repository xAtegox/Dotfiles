const form = document.getElementById("search");
const input = document.getElementById("query");

form.addEventListener("submit", (event) => {
  event.preventDefault();

  const query = input.value.trim();

  if (!query)
    return;

  window.location.href =
    "https://www.google.com/search?q=" +
    encodeURIComponent(query);
});


// ============================================================
// pywal live reload
// ============================================================
//
// wal-colors.css is a symlink to ~/.cache/wal/colors.css. When
// pywal regenerates the palette the file is rewritten on disk, but
// the <link> in index.html was loaded once at page load. Poll it
// with a cache-busting query string and keep a <style> element
// (appended after the <link>, so it wins the cascade) in sync so
// the colours hot-swap without closing the tab.

const WAL_POLL_MS = 2000;
let walStyle = null;

async function loadWalColors() {
  try {
    const res = await fetch("wal-colors.css?t=" + Date.now());
    if (!res.ok) return;

    const css = await res.text();

    if (!walStyle) {
      walStyle = document.createElement("style");
      walStyle.id = "wal-live-colors";
      document.head.appendChild(walStyle);
    }

    if (walStyle.textContent !== css) {
      walStyle.textContent = css;
    }
  } catch {
    // Keep whatever colours we already have.
  }
}

loadWalColors();
setInterval(loadWalColors, WAL_POLL_MS);


// ============================================================
// Focus handling
// ============================================================
//
// Chromium focuses the omnibox when a new tab opens and re-asserts
// it after the page's own focus() calls, so a one-shot attempt loses
// the race. Keep re-asserting focus on the search input for the whole
// life of the page while the tab is visible — once the browser stops
// fighting, the input stays focused and we just idle (no-op) each tick.

function stealFocus() {
  if (document.visibilityState === "visible" &&
      document.activeElement !== input) {
    input.focus();
  }
}

window.addEventListener("focus", stealFocus);
document.addEventListener("visibilitychange", stealFocus);
setInterval(stealFocus, 100);