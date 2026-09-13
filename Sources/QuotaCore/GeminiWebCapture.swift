import Foundation

public enum GeminiWebCapture {
    public static let script = #"""
    (() => {
        if (location.origin !== 'https://gemini.google.com') return;
        window.__aiQuotaGeminiUsage = null;
        const originalOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(...args) {
            let usage = false;
            try {
                const url = new URL(String(args[1]), location.href);
                usage = url.origin === location.origin && url.pathname === '/_/BardChatUi/data/batchexecute' &&
                    (url.searchParams.get('rpcids') || '').split(',').includes('jSf9Qc');
            } catch (_) {}
            if (usage) this.addEventListener('load', () => {
                if (this.status !== 200 || (this.responseType && this.responseType !== 'text')) return;
                try {
                    for (const line of this.responseText.split('\n')) {
                        if (!line.startsWith('[')) continue;
                        const rows = JSON.parse(line);
                        for (const row of rows) {
                            if (Array.isArray(row) && row[0] === 'wrb.fr' && row[1] === 'jSf9Qc' && typeof row[2] === 'string') {
                                window.__aiQuotaGeminiUsage = { payload: row[2], receivedAt: Date.now() };
                            }
                        }
                    }
                } catch (_) {}
            }, { once: true });
            return originalOpen.apply(this, args);
        };
    })();
    """#
}
