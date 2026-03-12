(function () {
    function track(eventName, params) {
        if (typeof window.gtag !== "function") {
            return;
        }
        window.gtag("event", eventName, params);
    }

    function classifyLink(href) {
        if (!href) {
            return null;
        }

        if (href.includes("releases/latest/download/Star.Video.Downloader.zip")) {
            return "download_click";
        }
        if (href.includes("firaskam.gumroad.com/l/xxmkcc")) {
            return "buy_pro_click";
        }
        if (href === "/pricing" || href.startsWith("/pricing#")) {
            return "pricing_click";
        }
        if (href === "/help" || href.startsWith("/help#")) {
            return "help_click";
        }
        if (href.startsWith("mailto:support@starvideoapp.com")) {
            return "support_click";
        }
        return null;
    }

    document.addEventListener("click", function (event) {
        var link = event.target.closest("a[href]");
        var href;
        var eventName;
        var label;

        if (!link) {
            return;
        }

        href = link.getAttribute("href") || "";
        eventName = classifyLink(href);
        if (!eventName) {
            return;
        }

        label = (link.textContent || "").replace(/\s+/g, " ").trim().slice(0, 80);
        track(eventName, {
            link_url: href,
            link_text: label || "(no text)",
            page_path: window.location.pathname
        });
    }, { passive: true });
}());
