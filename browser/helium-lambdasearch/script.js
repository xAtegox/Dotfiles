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

// A single delayed focus() call was losing the race against
// Chrome's own omnibox-focus behavior on override pages.
// Poll for up to ~1.5s and re-assert focus whenever it isn't
// already on the input.
let attempts = 0;

function tryFocus() {
  attempts++;

  if (document.activeElement !== input) {
    input.focus();
  }

  if (document.activeElement !== input && attempts < 30) {
    requestAnimationFrame(() =>
      setTimeout(tryFocus, 50)
    );
  }
}

window.addEventListener("load", tryFocus);
window.addEventListener("focus", () => input.focus());
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) input.focus();
});
