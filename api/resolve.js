export default async function handler(req, res) {
    const { url } = req.query;

    if (!url) {
        return res.status(400).json({ error: 'url param required' });
    }

    let parsed;
    try {
        parsed = new URL(url);
    } catch {
        return res.status(400).json({ error: 'Invalid URL' });
    }

    if (!['http:', 'https:'].includes(parsed.protocol)) {
        return res.status(400).json({ error: 'Only http/https URLs supported' });
    }

    // Basic SSRF protection — block private/loopback ranges
    const { hostname } = parsed;
    if (
        hostname === 'localhost' ||
        /^127\./.test(hostname) ||
        /^10\./.test(hostname) ||
        /^192\.168\./.test(hostname) ||
        /^172\.(1[6-9]|2\d|3[01])\./.test(hostname) ||
        hostname === '::1'
    ) {
        return res.status(400).json({ error: 'Private URLs not allowed' });
    }

    try {
        const response = await fetch(url, {
            redirect: 'follow',
            headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.9',
            },
            signal: AbortSignal.timeout(10000),
        });

        const finalUrl = response.url;
        let title = null;

        const contentType = response.headers.get('content-type') || '';
        if (contentType.includes('text/html')) {
            const text = await response.text();
            const match = text.slice(0, 15000).match(/<title[^>]*>([^<]*)<\/title>/i);
            if (match) title = match[1].trim() || null;
        }

        return res.json({ finalUrl, title });
    } catch {
        return res.status(500).json({ error: 'Failed to resolve URL' });
    }
}
