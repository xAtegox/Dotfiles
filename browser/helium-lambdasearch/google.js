(() => {
    document.documentElement.classList.add("lambda-loading");

    const RESULTS_PER_PAGE = 30;

    function getQuery() {
        return new URLSearchParams(window.location.search).get("q") || "";
    }

    function isImagesTab() {
        const params = new URLSearchParams(window.location.search);
        return params.get("tbm") === "isch" || params.get("udm") === "2";
    }

    function withNum(url) {
        const u = new URL(url, window.location.href);
        if (!u.searchParams.has("num")) u.searchParams.set("num", String(RESULTS_PER_PAGE));
        return u.href;
    }

    function ensureNumParam() {
        if (isImagesTab()) return;

        const params = new URLSearchParams(window.location.search);
        if (params.has("num")) return;

        params.set("num", String(RESULTS_PER_PAGE));
        window.location.replace(window.location.pathname + "?" + params.toString());
    }

    function logoUrl() {
        try {
            return chrome.runtime.getURL("images.png");
        } catch {
            return "images.png";
        }
    }

    function createBar() {
        if (document.getElementById("lambda-search-bar"))
            return;

        const bar = document.createElement("div");
        bar.id = "lambda-search-bar";

        bar.innerHTML = `
            <img id="lambda-logo" src="${logoUrl()}" alt="λSearch">
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

                window.location.href = withNum(
                    "https://www.google.com/search?q=" + encodeURIComponent(value)
                );
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
            <a href="${withNum("https://www.google.com/search?q=" + q)}"
               class="${!images ? "active" : ""}">All</a>
            <a href="https://www.google.com/search?q=${q}&udm=2"
               class="${images ? "active" : ""}">Images</a>
        `;

        document
            .getElementById("lambda-search-bar")
            .insertAdjacentElement("afterend", tabs);
    }

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

    function createMainColumn() {
        let col = document.getElementById("lambda-main-col");
        if (col) return col;

        col = document.createElement("div");
        col.id = "lambda-main-col";

        createContent().appendChild(col);

        return col;
    }

    function createResultsContainer() {
        let results = document.getElementById("lambda-results");
        if (results) return results;

        results = document.createElement("div");
        results.id = "lambda-results";

        createMainColumn().appendChild(results);

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

    function buildPagination() {
        if (document.getElementById("lambda-pagination")) return;
        if (isImagesTab()) return;

        const links = [...document.querySelectorAll("a[href*='start=']")]
            .filter(a => !a.closest("#lambda-search-bar, #lambda-tabs, #lambda-content"));

        const byStart = new Map();

        links.forEach(a => {
            let url;
            try { url = new URL(a.href); }
            catch { return; }

            const start = parseInt(url.searchParams.get("start") || "0", 10);
            if (!byStart.has(start)) byStart.set(start, withNum(a.href));
        });

        const currentStart = parseInt(
            new URLSearchParams(window.location.search).get("start") || "0", 10
        );

        if (!byStart.has(currentStart)) {
            byStart.set(currentStart, withNum(window.location.href));
        }

        if (byStart.size < 2) return;

        const perPage = RESULTS_PER_PAGE;
        const starts = [...byStart.keys()].sort((a, b) => a - b);

        const bar = document.createElement("div");
        bar.id = "lambda-pagination";

        starts.forEach(start => {
            const page = Math.round(start / perPage) + 1;
            const a = document.createElement("a");
            a.href = byStart.get(start);
            a.textContent = String(page);
            if (start === currentStart) a.className = "active";
            bar.appendChild(a);
        });

        document.getElementById("lambda-results").insertAdjacentElement("afterend", bar);
    }

    const seenImageSrcs = new Set();

    function isBrandAsset(img) {
        const src = (img.currentSrc || img.src || "").toLowerCase();
        const alt = (img.alt || "").toLowerCase();

        return (
            alt === "google" ||
            src.includes("googlelogo") ||
            src.includes("/logos/") ||
            src.includes("gstatic.com/images/branding")
        );
    }

    // Single source of truth for "what page did this image come
    // from" — used for BOTH the displayed hostname and the actual
    // click-through link. Previously these used different logic,
    // which is why clicking opened the raw thumbnail instead of
    // the source site.
    function getSourceHref(img) {
        const link = img.closest("a[href^='http']");
        if (link) return link.href;

        const dataHost = img.closest("[data-lpage], [data-ru], [data-docid]");
        if (dataHost) {
            const raw = dataHost.getAttribute("data-lpage") || dataHost.getAttribute("data-ru");
            if (raw) {
                try { return decodeURIComponent(raw); }
                catch { return raw; }
            }
        }

        return null;
    }

    function findImageHost(href) {
        if (!href) return "";
        try { return new URL(href).hostname.replace(/^www\./, ""); }
        catch { return ""; }
    }

    function buildImageResults() {
        const results = createResultsContainer();
        results.classList.add("lambda-image-grid");

        const imgs = [...document.querySelectorAll("img")]
            .filter(img => {
                if (img.closest("#lambda-search-bar, #lambda-tabs, #lambda-content"))
                    return false;

                if (isBrandAsset(img)) return false;

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

            const href = getSourceHref(img) || src;

            const card = document.createElement("a");
            card.className = "lambda-image-card";
            card.href = href;
            card.target = "_blank";
            card.rel = "noopener";

            card.innerHTML = `
                <img src="${src}" alt="">
                <div class="lambda-image-title"></div>
                <div class="lambda-image-url"></div>
            `;

            card.querySelector(".lambda-image-title").textContent = img.alt || "";
            card.querySelector(".lambda-image-url").textContent = findImageHost(href);

            results.appendChild(card);
        });
    }

    function buildKnowledgePanel() {
        if (isImagesTab()) return;
        if (document.getElementById("lambda-kp")) return;

        const titleEl = document.querySelector('[data-attrid="title"]');
        if (!titleEl) return;

        const titleText = titleEl.textContent.trim();
        if (!titleText) return;

        let container = titleEl;
        let panelImg = null;

        for (let i = 0; i < 15 && container.parentElement; i++) {
            container = container.parentElement;
            panelImg = container.querySelector('img[id^="dimg_"]');
            if (panelImg) break;
        }

        if (!container) return;

        const imgSrc = panelImg ? (panelImg.currentSrc || panelImg.src) : "";

        const spans = [...container.querySelectorAll("span")]
            .filter(s => s.children.length === 0)
            .map(s => s.textContent.trim())
            .filter(t => t.length > 40 && t !== titleText);

        spans.sort((a, b) => b.length - a.length);
        const description = spans[0] || "";

        const links = [...container.querySelectorAll("a[href^='http']")];
        const sourceLink = links.find(a => a.href.includes("wikipedia.org")) || links[0];

        const panel = document.createElement("div");
        panel.id = "lambda-kp";

        panel.innerHTML = `
            <div class="lambda-kp-title">${titleText}</div>
            <div class="lambda-kp-body">
                ${imgSrc ? `<img class="lambda-kp-img" src="${imgSrc}">` : ""}
                <div class="lambda-kp-desc"></div>
            </div>
            ${sourceLink ? `<div class="lambda-kp-source">Source: <a href="${sourceLink.href}">${new URL(sourceLink.href).hostname.replace(/^www\./, "")}</a></div>` : ""}
        `;

        panel.querySelector(".lambda-kp-desc").textContent = description;

        createContent().appendChild(panel);
    }

    function activate() {
        ensureNumParam();

        createBar();
        createTabs();
        createContent();

        document.body.classList.add("lambda-mode");
        document.documentElement.classList.remove("lambda-loading");
        document.documentElement.classList.add("lambda-ready");

        const build = isImagesTab() ? buildImageResults : buildOrganicResults;

        build();
        buildKnowledgePanel();
        buildPagination();

        const observer = new MutationObserver(() => {
            build();
            buildKnowledgePanel();
            buildPagination();
        });
        observer.observe(document.body, { childList: true, subtree: true });
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", activate, { once: true });
    } else {
        activate();
    }
})();
