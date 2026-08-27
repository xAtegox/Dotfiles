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

    // If the current page was loaded without &num=, reload once
    // with it added so Google actually returns more per page.
    // Guarded by a URL flag, not sessionStorage, so it only ever
    // fires a single redirect per navigation.
    function ensureNumParam() {
        if (isImagesTab()) return;

        const params = new URLSearchParams(window.location.search);
        if (params.has("num")) return;

        params.set("num", String(RESULTS_PER_PAGE));
        window.location.replace(
            window.location.pathname + "?" + params.toString()
        );
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

    // Google's own "G" wordmark/logo assets, not a search result.
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

    // Excludes small icon/logo assets (Wikipedia's own "W" mark,
    // favicons) by requiring a real photo-sized area, and by
    // src/alt pattern for known logo assets.
    function isLikelyIcon(img) {
        const src = (img.currentSrc || img.src || "").toLowerCase();
        const alt = (img.alt || "").toLowerCase();

        return (
            src.includes("wikipedia-logo") ||
            src.includes("/static/images/icons/") ||
            src.includes("favicon") ||
            alt.includes("wikipedia") && alt.includes("logo")
        );
    }

    function bestImageIn(block) {
        const imgs = [...block.querySelectorAll("img")]
            .filter(img => !isLikelyIcon(img));

        let best = null;
        let bestArea = 0;

        imgs.forEach(img => {
            const w = img.naturalWidth || img.width || 0;
            const h = img.naturalHeight || img.height || 0;
            const area = w * h;

            // Require a real photo-scale image (roughly 150x150+)
            // so small badges never win even if nothing else has loaded yet.
            if (area > bestArea && area >= 22500) {
                bestArea = area;
                best = img;
            }
        });

        return { img: best, area: bestArea };
    }

    function bestDescriptionIn(block, titleText) {
        const candidates = [...block.querySelectorAll("*")]
            .filter(el => el.children.length === 0)
            .map(el => el.textContent.trim())
            .filter(t => t.length > 25 && t !== titleText);

        candidates.sort((a, b) => b.length - a.length);
        return candidates[0] || "";
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
        const titleText = match.textContent.trim();

        let panel = document.getElementById("lambda-kp");

        if (panel) {
            const prevArea = parseInt(panel.dataset.imgArea || "0", 10);
            if (imgSrc && area > prevArea) {
                const imgEl = panel.querySelector(".lambda-kp-img");
                if (imgEl) imgEl.src = imgSrc;
                panel.dataset.imgArea = String(area);
            }

            const descEl = panel.querySelector(".lambda-kp-desc");
            if (descEl && !descEl.textContent.trim()) {
                const desc = bestDescriptionIn(found, titleText);
                if (desc) descEl.textContent = desc;
            }
            return;
        }

        const description = bestDescriptionIn(found, titleText);

        const links = [...found.querySelectorAll("a[href^='http']")];
        const sourceLink = links.find(a => a.href.includes("wikipedia.org")) || links[0];

        panel = document.createElement("div");
        panel.id = "lambda-kp";
        panel.dataset.imgArea = String(area);

        panel.innerHTML = `
            <div class="lambda-kp-title">${titleText}</div>
            ${imgSrc ? `<img class="lambda-kp-img" src="${imgSrc}">` : ""}
            <div class="lambda-kp-desc"></div>
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

// ---- crow-bug patch: loosen match + walk-up, applied after the
// original definitions above by simply overriding buildKnowledgePanel.

function buildKnowledgePanelV2() {
    if (isImagesTab()) return;
    if (document.getElementById("lambda-kp")) {
        // still allow late image/description backfill on existing panel
    }

    const query = getQuery().trim().toLowerCase();
    if (!query) return;

    const headingSelectors = "h1, h2, h3, div[role='heading'], [aria-level]";
    const headings = [...document.querySelectorAll(headingSelectors)]
        .filter(h => !h.closest("#lambda-search-bar, #lambda-tabs, #lambda-content"));

    // Loosened: also accept a heading that CONTAINS the query as a
    // whole word, not just startsWith/equals — catches panels titled
    // e.g. "Crow (bird)" or "Crow — Corvus" for a "crow" query.
    const wordBoundary = new RegExp("\\b" + query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\b", "i");

    const candidates = headings.filter(h => {
        const t = h.textContent.trim();
        return t.length > 0 && t.length < 60 && wordBoundary.test(t);
    });

    if (!candidates.length) return;

    let found = null;
    let match = null;

    for (const h of candidates) {
        let block = h;
        for (let i = 0; i < 12 && block.parentElement; i++) {
            block = block.parentElement;

            const hasImg = block.querySelector("img");
            const text = (block.innerText || "").trim();

            // Loosened from >80 to >40 characters of surrounding text.
            if (hasImg && text.length > 40) {
                found = block;
                match = h;
                break;
            }
        }
        if (found) break;
    }

    if (!found) return;

    const { img, area } = bestImageIn(found);
    const imgSrc = img ? (img.currentSrc || img.src) : "";
    const titleText = match.textContent.trim();

    let panel = document.getElementById("lambda-kp");

    if (panel) {
        const prevArea = parseInt(panel.dataset.imgArea || "0", 10);
        if (imgSrc && area > prevArea) {
            const imgEl = panel.querySelector(".lambda-kp-img");
            if (imgEl) imgEl.src = imgSrc;
            panel.dataset.imgArea = String(area);
        }

        const descEl = panel.querySelector(".lambda-kp-desc");
        if (descEl && !descEl.textContent.trim()) {
            const desc = bestDescriptionIn(found, titleText);
            if (desc) descEl.textContent = desc;
        }
        return;
    }

    const description = bestDescriptionIn(found, titleText);

    const links = [...found.querySelectorAll("a[href^='http']")];
    const sourceLink = links.find(a => a.href.includes("wikipedia.org")) || links[0];

    panel = document.createElement("div");
    panel.id = "lambda-kp";
    panel.dataset.imgArea = String(area);

    // Horizontal layout: image + text side by side in a top row,
    // source line below — matches the reference design.
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

// Swap the observer/activate calls over to the v2 builder.
window.__lambdaBuildKP = buildKnowledgePanelV2;

// ---- crow-bug patch: loosen match + walk-up, applied after the
// original definitions above by simply overriding buildKnowledgePanel.

function buildKnowledgePanelV2() {
    if (isImagesTab()) return;
    if (document.getElementById("lambda-kp")) {
        // still allow late image/description backfill on existing panel
    }

    const query = getQuery().trim().toLowerCase();
    if (!query) return;

    const headingSelectors = "h1, h2, h3, div[role='heading'], [aria-level]";
    const headings = [...document.querySelectorAll(headingSelectors)]
        .filter(h => !h.closest("#lambda-search-bar, #lambda-tabs, #lambda-content"));

    // Loosened: also accept a heading that CONTAINS the query as a
    // whole word, not just startsWith/equals — catches panels titled
    // e.g. "Crow (bird)" or "Crow — Corvus" for a "crow" query.
    const wordBoundary = new RegExp("\\b" + query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\b", "i");

    const candidates = headings.filter(h => {
        const t = h.textContent.trim();
        return t.length > 0 && t.length < 60 && wordBoundary.test(t);
    });

    if (!candidates.length) return;

    let found = null;
    let match = null;

    for (const h of candidates) {
        let block = h;
        for (let i = 0; i < 12 && block.parentElement; i++) {
            block = block.parentElement;

            const hasImg = block.querySelector("img");
            const text = (block.innerText || "").trim();

            // Loosened from >80 to >40 characters of surrounding text.
            if (hasImg && text.length > 40) {
                found = block;
                match = h;
                break;
            }
        }
        if (found) break;
    }

    if (!found) return;

    const { img, area } = bestImageIn(found);
    const imgSrc = img ? (img.currentSrc || img.src) : "";
    const titleText = match.textContent.trim();

    let panel = document.getElementById("lambda-kp");

    if (panel) {
        const prevArea = parseInt(panel.dataset.imgArea || "0", 10);
        if (imgSrc && area > prevArea) {
            const imgEl = panel.querySelector(".lambda-kp-img");
            if (imgEl) imgEl.src = imgSrc;
            panel.dataset.imgArea = String(area);
        }

        const descEl = panel.querySelector(".lambda-kp-desc");
        if (descEl && !descEl.textContent.trim()) {
            const desc = bestDescriptionIn(found, titleText);
            if (desc) descEl.textContent = desc;
        }
        return;
    }

    const description = bestDescriptionIn(found, titleText);

    const links = [...found.querySelectorAll("a[href^='http']")];
    const sourceLink = links.find(a => a.href.includes("wikipedia.org")) || links[0];

    panel = document.createElement("div");
    panel.id = "lambda-kp";
    panel.dataset.imgArea = String(area);

    // Horizontal layout: image + text side by side in a top row,
    // source line below — matches the reference design.
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

// Swap the observer/activate calls over to the v2 builder.
window.__lambdaBuildKP = buildKnowledgePanelV2;
