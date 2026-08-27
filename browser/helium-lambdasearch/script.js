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

// autofocus alone loses to Chrome's omnibox on override pages —
// force it after load, with a short delay since focus() called
// too early can still lose the race.
function forceFocus() {
  input.focus();
}

window.addEventListener("load", () => {
  forceFocus();
  setTimeout(forceFocus, 50);
});

window.addEventListener("focus", forceFocus);
