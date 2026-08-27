(() => {
    function getQuery() {
        return new URLSearchParams(window.location.search).get("q") || "";
    }

    function isImagesTab() {
        const params = new URLSearchParams(window.location.search);
        return params.get("tbm") === "isch" || params.get("udm") === "2";
    }

    function createBar() {
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
        input.value = getQuery();

        document
            .getElementById("lambda-form")
            .addEventListener("submit", event => {
                event.preventDefault();

                const value = input.value.trim();
                if (!value) return;

                window.location.href =
                    "https://www.google.com/search?q=" +
                    encodeURIComponent(value);
            });
    }

    function createTabs() {
        if (document.getElementById("lambda-tabs"))
            return;

        const q = encodeURIComponent(getQuery());
        const images = isImagesTab();

        const tabs = document.createElement("div");
        tabs.id = "lambda-tabs";

        tabs.innerHTML = `
            <a href="https://www.google.com/search?q=${q}"
               class="${!images ? "active" : ""}">All</a>
            <a href="https://www.google.com/search?q=${q}&udm=2"
               class="${images ? "active" : ""}">Images</a>
        `;

        const bar = document.getElementById("lambda-search-bar");
        bar.insertAdjacentElement("afterend", tabs);
    }

    function createResultsContainer() {
        let results = document.getElementById("lambda-results");
        if (results) return results;

        results = document.createElement("div");
        results.id = "lambda-results";

        document
            .getElementById("lambda-tabs")
            .insertAdjacentElement("afterend", results);

        return results;
    }

    /*
     * Snippet extraction: walk up from the title anchor,
     * and at each level check the ancestor's own visible
     * text (innerText, so hidden nodes are excluded) for
     * a line that isn't the title/breadcrumb and is long
     * enough to plausibly be a description. Not leaf-only,
     * since Google nests snippet text inside spans.
     */
    function extractSnippet(anchor, titleText, breadcrumbText) {
        let block = anchor;

        for (let i = 0; i < 6 && block.parentElement; i++) {
            block = block.parentElement;

            const raw = block.innerText || block.textContent || "";

            const lines = raw
                .split("\n")
                .map(l => l.trim())
                .filter(Boolean);

            const candidate = lines.find(l =>
                l.length > 40 &&
                l !== titleText &&
                !l.includes(breadcrumbText) &&
                !breadcrumbText.includes(l)
            );

            if (candidate) return candidate;
        }

        return "";
    }

    const seenTitles = new Set();

    function buildOrganicResults() {
        const results = createResultsContainer();

        const headings = [...document.querySelectorAll("h3")]
            .filter(h3 => !h3.closest("#lambda-search-bar, #lambda-tabs, #lambda-results"));

        headings.forEach(h3 => {
            const anchor = h3.closest("a[href^='http']");
            if (!anchor) return;

            const titleText = h3.textContent.trim();
            if (!titleText || seenTitles.has(titleText)) return;

            let url;
            try {
                url = new URL(anchor.href);
            } catch {
                return;
            }

            const breadcrumb =
                url.hostname.replace(/^www\./, "") +
                (url.pathname !== "/" ? " › " + url.pathname.split("/").filter(Boolean).join(" › ") : "");

            const snippet = extractSnippet(anchor, titleText, breadcrumb);

            const card = document.createElement("div");
            card.className = "lambda-result";

            card.innerHTML = `
                <a class="lambda-result-url" href="${anchor.href}">${breadcrumb}</a>
                <a class="lambda-result-title" href="${anchor.href}">${titleText}</a>
                <div class="lambda-result-snippet"></div>
            `;

            card.querySelector(".lambda-result-snippet").textContent = snippet;

            results.appendChild(card);
            seenTitles.add(titleText);
        });
    }

    const seenImageSrcs = new Set();

    function buildImageResults() {
        const results = createResultsContainer();
        results.classList.add("lambda-image-grid");

        const imgs = [...document.querySelectorAll("img")]
            .filter(img => {
                if (img.closest("#lambda-search-bar, #lambda-tabs, #lambda-results")) return false;

                const src = img.currentSrc || img.src || img.dataset.src || img.dataset.iurl;
                if (!src || !src.startsWith("http")) return false;
                if (seenImageSrcs.has(src)) return false;

                // Don't gate on naturalWidth — lazy-loaded images report
                // 0 until decoded. Fall back to declared attributes.
                const w = img.naturalWidth || img.width || parseInt(img.getAttribute("width") || "0", 10);
                return w === 0 || w > 60;
            });

        imgs.forEach(img => {
            const src = img.currentSrc || img.src || img.dataset.src || img.dataset.iurl;
            if (!src || seenImageSrcs.has(src)) return;

            seenImageSrcs.add(src);

            const alt = img.alt || "";
            const link = img.closest("a[href^='http']");

            const card = document.createElement("div");
            card.className = "lambda-image-card";

            card.innerHTML = `
                <img src="${src}" alt="">
                <div class="lambda-image-title"></div>
                <div class="lambda-image-url"></div>
            `;

            card.querySelector(".lambda-image-title").textContent = alt;

            let host = "";
            if (link) {
                try { host = new URL(link.href).hostname.replace(/^www\./, ""); }
                catch {}
            }
            card.querySelector(".lambda-image-url").textContent = host;

            results.appendChild(card);
        });
    }

    function activate() {
        createBar();
        createTabs();
        document.body.classList.add("lambda-mode");

        const build = isImagesTab() ? buildImageResults : buildOrganicResults;

        build();

        // Google renders results progressively / lazily —
        // keep re-scanning on DOM changes instead of a fixed
        // number of polls, so late content still gets picked up.
        const observer = new MutationObserver(() => build());
        observer.observe(document.body, { childList: true, subtree: true });
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", activate, { once: true });
    } else {
        activate();
    }
})();
