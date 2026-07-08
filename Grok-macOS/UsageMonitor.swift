//
//  UsageMonitor.swift
//  Grok-macOS
//
//  Rate-limit tracking for the usage pill. An injected script passively
//  observes grok.com's own POST /rest/rate-limits traffic (learning the
//  current model names from it) and re-polls the endpoint while the pill
//  is visible, posting {requestBody, response} to the "usage" handler.
//

import SwiftUI

struct ModelRateLimit: Equatable {
    var remainingQueries: Int?
    var totalQueries: Int?
    var windowSizeSeconds: Int?
    var waitTimeSeconds: Int?        // present when exhausted; seconds until refill
    var lowEffortRemaining: Int?
    var highEffortRemaining: Int?
    var fetchedAt: Date

    var fraction: Double? {
        guard let remaining = remainingQueries, let total = totalQueries, total > 0 else { return nil }
        return Double(remaining) / Double(total)
    }

    // Same thresholds as Grok-Desktop: red at <=10% remaining, orange at <=25%.
    var statusColor: Color? {
        guard let fraction else { return nil }
        if fraction <= 0.10 { return .red }
        if fraction <= 0.25 { return .orange }
        return nil
    }

    // Ticks down locally between refreshes; nil once elapsed.
    func refillRemaining(at date: Date) -> Int? {
        guard let wait = waitTimeSeconds, wait > 0 else { return nil }
        let remaining = wait - Int(date.timeIntervalSince(fetchedAt))
        return remaining > 0 ? remaining : nil
    }
}

enum UsageMonitor {

    // The endpoint is internal and undocumented, so parsing is lenient:
    // every field is optional and a shape change just yields nil.
    static func parse(messageBody: Any) -> (model: String, info: ModelRateLimit)? {
        guard let dict = messageBody as? [String: Any],
              let response = dict["response"] as? [String: Any] else { return nil }
        let request = dict["requestBody"] as? [String: Any]
        let model = (request?["modelName"] as? String) ?? "default"

        func int(_ any: Any?) -> Int? {
            if let number = any as? NSNumber { return number.intValue }
            if let string = any as? String { return Int(string) }
            return nil
        }

        var info = ModelRateLimit(fetchedAt: Date())
        info.remainingQueries = int(response["remainingQueries"])
        info.totalQueries = int(response["totalQueries"])
        info.windowSizeSeconds = int(response["windowSizeSeconds"])
        info.waitTimeSeconds = int(response["waitTimeSeconds"])
        if let low = response["lowEffortRateLimits"] as? [String: Any] {
            info.lowEffortRemaining = int(low["remainingQueries"])
            // Some response shapes nest the primary numbers per effort level.
            if info.remainingQueries == nil { info.remainingQueries = int(low["remainingQueries"]) }
            if info.totalQueries == nil { info.totalQueries = int(low["totalQueries"]) }
            if info.waitTimeSeconds == nil { info.waitTimeSeconds = int(low["waitTimeSeconds"]) }
        }
        if let high = response["highEffortRateLimits"] as? [String: Any] {
            info.highEffortRemaining = int(high["remainingQueries"])
        }

        guard info.remainingQueries != nil
                || info.lowEffortRemaining != nil
                || info.waitTimeSeconds != nil else { return nil }
        return (model, info)
    }

    // Injected at document start (unlike the sidebar watcher) so window.fetch
    // is wrapped before any page script captures a reference to it. The
    // hostname guard keeps polling off OAuth popup pages, which inherit this
    // script through the configuration WebKit hands to createWebViewWith.
    static let script = """
    (function () {
        if (window.__nativeUsageInstalled) { return; }
        window.__nativeUsageInstalled = true;

        const ENDPOINT = '/rest/rate-limits';
        const POLL_MS = 15000;
        const observedBodies = {};
        let pollTimer = null;
        let activityTimer = null;

        function onGrok() {
            const h = location.hostname;
            return h === 'grok.com' || h.endsWith('.grok.com');
        }

        function post(requestBody, responseJson) {
            try {
                if (requestBody && requestBody.modelName) {
                    observedBodies[requestBody.modelName] = requestBody;
                }
                window.webkit.messageHandlers.usage.postMessage(
                    { requestBody: requestBody || null, response: responseJson });
            } catch (e) {}
        }

        function captureResponse(promise, body) {
            promise.then(function (res) {
                if (res && res.ok) {
                    res.clone().json().then(function (json) { post(body, json); })
                        .catch(function () {});
                }
            }).catch(function () {});
        }

        // Chat activity consumes quota; refresh shortly after any other
        // API POST completes so the pill tracks usage, not just the clock.
        function scheduleActivityRefresh() {
            if (!pollTimer || activityTimer) { return; }
            activityTimer = setTimeout(function () {
                activityTimer = null;
                refresh();
            }, 2000);
        }

        // Passive path: the page queries the endpoint itself on load and
        // after each message; cloning those responses needs no extra traffic.
        const origFetch = window.fetch;
        window.fetch = function (input, init) {
            const p = origFetch.apply(this, arguments);
            try {
                const url = (typeof input === 'string') ? input : ((input && input.url) || '');
                if (url.indexOf(ENDPOINT) !== -1) {
                    if (init && typeof init.body === 'string') {
                        let body = null;
                        try { body = JSON.parse(init.body); } catch (e) {}
                        captureResponse(p, body);
                    } else if (input && typeof input.clone === 'function') {
                        input.clone().text().then(function (t) {
                            let body = null;
                            try { body = JSON.parse(t); } catch (e) {}
                            captureResponse(p, body);
                        }).catch(function () { captureResponse(p, null); });
                    } else {
                        captureResponse(p, null);
                    }
                } else if (url.indexOf('/rest/') !== -1) {
                    const method = ((init && init.method) || (input && input.method) || 'GET').toUpperCase();
                    if (method === 'POST') {
                        p.then(function () { scheduleActivityRefresh(); }).catch(function () {});
                    }
                }
            } catch (e) {}
            return p;
        };

        // XHR fallback in case the site switches transports.
        const origOpen = XMLHttpRequest.prototype.open;
        const origSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function (method, url) {
            this.__usageURL = String(url || '');
            return origOpen.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function (body) {
            if (this.__usageURL && this.__usageURL.indexOf(ENDPOINT) !== -1) {
                let parsed = null;
                try { parsed = JSON.parse(body); } catch (e) {}
                this.addEventListener('load', function () {
                    try {
                        if (this.status === 200) { post(parsed, JSON.parse(this.responseText)); }
                    } catch (e) {}
                });
            }
            return origSend.apply(this, arguments);
        };

        // Active path: re-issue request bodies learned from the page's own
        // traffic through the original fetch (skipping our own wrapper).
        // Same-origin, so cookies attach. Nothing learned yet means nothing
        // to poll — the page queries the endpoint itself on every load.
        function refresh() {
            if (!onGrok()) { return; }
            Object.keys(observedBodies).forEach(function (k) {
                const b = observedBodies[k];
                origFetch.call(window, ENDPOINT, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    credentials: 'include',
                    body: JSON.stringify(b)
                }).then(function (res) {
                    if (res.ok) {
                        res.json().then(function (json) { post(b, json); })
                            .catch(function () {});
                    }
                }).catch(function () {});
            });
        }

        // Called from native on pill toggle and after each page load.
        window.__nativeUsageSetVisible = function (visible) {
            if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
            if (visible) {
                refresh();
                pollTimer = setInterval(function () {
                    if (!document.hidden) { refresh(); }
                }, POLL_MS);
            }
        };
    })();
    """
}
