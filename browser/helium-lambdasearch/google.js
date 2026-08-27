(() => {
    // Hide the real page immediately — before DOMContentLoaded —
    // so there's no flash of raw Google styling while we build.
    document.documentElement.classList.add("lambda-loading");

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

        document
            .getElementById("lambda-search-bar")
            .insertAdjacentElement("afterend", tabs);
    }

    // Flex wrapper holding results + knowledge panel side by side,
    // so leftover width gets distributed instead of sitting empty.
    function createContent() {
        let content = document.getElementById("lambda-content");
        if (content) return content;

        content = document.createElement("div");
        content.id = "lambda-content";

        document
            .getElementById("lambda-tabs")
            .insertAdjacentElement("afterend", content);

        return content;
    }

    function createResultsContainer() {
        let results = document.getElementById("lambda-results");
        if (results) return results;

        results = document.createElement("div");
        results.id = "lambda-results";

        createContent().appendChild(results);

        return results;
    }

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
            .filter(h3 => !h3.closest("#lambda-search-bar, #lambda-tabs, #lambda-content"));

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

    function findImageHost(img) {
        const link = img.closest("a[href^='http']");
        if (link) {
            try { return new URL(link.href).hostname.replace(/^www\./, ""); }
            catch {}
        }

        const dataHost = img.closest("[data-lpage], [data-ru], [data-docid]");
        if (dataHost) {
            const raw = dataHost.getAttribute("data-lpage") || dataHost.getAttribute("data-ru");
            if (raw) {
                try { return new URL(raw).hostname.replace(/^www\./, ""); }
                catch {}
            }
        }

        return "";
    }

    function buildImageResults() {
        const results = createResultsContainer();
        results.classList.add("lambda-image-grid");

        const imgs = [...document.querySelectorAll("img")]
            .filter(img => {
                if (img.closest("#lambda-search-bar, #lambda-tabs, #lambda-content"))
                    return false;

                const src = img.currentSrc || img.src || img.dataset.src || img.dataset.iurl;
                if (!src || !src.startsWith("http")) return false;
                if (seenImageSrcs.has(src)) return false;

                const w = img.naturalWidth || img.width || parseInt(img.getAttribute("width") || "0", 10);
                return w === 0 || w > 60;
            });

        imgs.forEach(img => {
            const src = img.currentSrc || img.src || img.dataset.src || img.dataset.iurl;
            if (!src || seenImageSrcs.has(src)) return;

            seenImageSrcs.add(src);

            const card = document.createElement("div");
            card.className = "lambda-image-card";

            card.innerHTML = `
                <img src="${src}" alt="">
                <div class="lambda-image-title"></div>
                <div class="lambda-image-url"></div>
            `;

            card.querySelector(".lambda-image-title").textContent = img.alt || "";
            card.querySelector(".lambda-image-url").textContent = findImageHost(img);

            results.appendChild(card);
        });
    }

    // Knowledge panel keeps re-checking for a bigger/better image
    // even after building, since Google's real thumbnail resolves
    // in behind a placeholder icon after the initial paint.
    function bestImageIn(block) {
        const imgs = [...block.querySelectorAll("img")];

        let best = null;
        let bestArea = 0;

        imgs.forEach(img => {
            const w = img.naturalWidth || img.width || 0;
            const h = img.naturalHeight || img.height || 0;
            const area = w * h;

            if (area > bestArea) {
                bestArea = area;
                best = img;
            }
        });

        return { img: best, area: bestArea };
    }

    function buildKnowledgePanel() {
        if (isImagesTab()) return;

        const query = getQuery().trim().toLowerCase();
        if (!query) return;

        const headings = [...document.querySelectorAll("h2, h3, div[role='heading']")]
            .filter(h => !h.closest("#lambda-search-bar, #lambda-tabs, #lambda-content"));

        const match = headings.find(h => {
            const t = h.textContent.trim().toLowerCase();
            return t.length > 0 && (t === query || t.startsWith(query) || query.startsWith(t));
        });

        if (!match) return;

        let block = match;
        let found = null;

        for (let i = 0; i < 8 && block.parentElement; i++) {
            block = block.parentElement;

            const hasImg = block.querySelector("img");
            const text = (block.innerText || "").trim();

            if (hasImg && text.length > 80) {
                found = block;
                break;
            }
        }

        if (!found) return;

        const { img, area } = bestImageIn(found);
        const imgSrc = img ? (img.currentSrc || img.src) : "";

        let panel = document.getElementById("lambda-kp");

        if (panel) {
            // Already built — only touch the image, and only if
            // we've now found something meaningfully bigger.
            const prevArea = parseInt(panel.dataset.imgArea || "0", 10);
            if (imgSrc && area > prevArea && area > 2500) {
                const imgEl = panel.querySelector(".lambda-kp-img");
                if (imgEl) imgEl.src = imgSrc;
                panel.dataset.imgArea = String(area);
            }
            return;
        }

        const paragraphs = [...found.querySelectorAll("*")]
            .filter(el => el.children.length === 0)
            .map(el => el.textContent.trim())
            .filter(t => t.length > 60);

        const description = paragraphs[0] || "";

        const links = [...found.querySelectorAll("a[href^='http']")];
        const sourceLink = links.find(a => a.href.includes("wikipedia.org")) || links[0];

        panel = document.createElement("div");
        panel.id = "lambda-kp";
        panel.dataset.imgArea = String(area);

        panel.innerHTML = `
            <div class="lambda-kp-title">${match.textContent.trim()}</div>
            ${imgSrc ? `<img class="lambda-kp-img" src="${imgSrc}">` : ""}
            <div class="lambda-kp-desc"></div>
            ${sourceLink ? `<div class="lambda-kp-source">Source: <a href="${sourceLink.href}">${new URL(sourceLink.href).hostname.replace(/^www\./, "")}</a></div>` : ""}
        `;

        panel.querySelector(".lambda-kp-desc").textContent = description;

        createContent().appendChild(panel);
    }

    function activate() {
        createBar();
        createTabs();
        createContent();

        document.body.classList.add("lambda-mode");
        document.documentElement.classList.remove("lambda-loading");
        document.documentElement.classList.add("lambda-ready");

        const build = isImagesTab() ? buildImageResults : buildOrganicResults;

        build();
        buildKnowledgePanel();

        const observer = new MutationObserver(() => {
            build();
            buildKnowledgePanel();
        });
        observer.observe(document.body, { childList: true, subtree: true });
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", activate, { once: true });
    } else {
        activate();
    }
})();
