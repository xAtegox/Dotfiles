(() => {
    console.log("λSearch Google script loaded!");

    function createLambdaSearch() {
        if (!document.body)
            return;

        if (document.getElementById("lambda-search-bar"))
            return;

        const bar = document.createElement("div");

        bar.id = "lambda-search-bar";

        bar.innerHTML = `
            <div id="lambda-logo">λSearch</div>

            <form id="lambda-form">
                <input
                    id="lambda-input"
                    type="text"
                    autocomplete="off"
                    spellcheck="false"
                >
            </form>
        `;

        document.body.prepend(bar);

        const input = document.getElementById("lambda-input");

        const params =
            new URLSearchParams(window.location.search);

        const query = params.get("q");

        if (query)
            input.value = query;

        document
            .getElementById("lambda-form")
            .addEventListener("submit", event => {
                event.preventDefault();

                const value = input.value.trim();

                if (!value)
                    return;

                window.location.href =
                    "https://www.google.com/search?q=" +
                    encodeURIComponent(value);
            });

        /*
         * DO NOT focus the input automatically.
         */
    }

    if (document.readyState === "loading") {
        document.addEventListener(
            "DOMContentLoaded",
            createLambdaSearch,
            { once: true }
        );
    } else {
        createLambdaSearch();
    }
})();
