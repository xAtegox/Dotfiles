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

input.focus();
