/**
 * Fetches a company's public logo server-side, for the Customize panel's
 * brand-color lookup -- deliberately not done as a direct browser fetch to
 * one of these hosts. A browser reading raw pixel data from a cross-origin
 * image requires that image's server to send an Access-Control-Allow-Origin
 * header; none of these free logo/favicon services reliably do (confirmed:
 * unavatar.io loads and displays fine but still fails a canvas pixel read).
 * Apex callouts have no concept of CORS -- it's a browser-only rule -- so
 * fetching here and handing the LWC the raw bytes as a data: URI sidesteps
 * the problem structurally instead of hoping a vendor adds the header.
 *
 * `with sharing`, rep-only: not guest-reachable, matches
 * GtmSavedConfigurationController's access model for the rest of the
 * Customize panel.
 */
public with sharing class GtmBrandLookupController {
    private static final Integer TIMEOUT_MS = 8000;

    @AuraEnabled
    public static String fetchLogoDataUri(String domain) {
        if (String.isBlank(domain)) {
            throw new AuraHandledException('No domain given.');
        }
        String encoded = EncodingUtil.urlEncode(domain.trim(), 'UTF-8');
        List<String> sources = new List<String>{
            'https://unavatar.io/' + encoded,
            'https://www.google.com/s2/favicons?sz=128&domain=' + encoded,
            'https://icons.duckduckgo.com/ip3/' + encoded + '.ico'
        };

        for (String url : sources) {
            String dataUri = tryFetch(url);
            if (dataUri != null) {
                return dataUri;
            }
        }
        return null;
    }

    private static String tryFetch(String url) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(url);
            req.setMethod('GET');
            req.setTimeout(TIMEOUT_MS);

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                return null;
            }
            String contentType = res.getHeader('Content-Type');
            if (String.isBlank(contentType) || !contentType.toLowerCase().startsWith('image/')) {
                return null;
            }
            Blob body = res.getBodyAsBlob();
            if (body == null || body.size() == 0) {
                return null;
            }
            // Strip any charset/parameters off the content type (e.g.
            // "image/png; charset=binary") -- only the mime type belongs
            // in the data: URI.
            String mime = contentType.split(';')[0].trim();
            return 'data:' + mime + ';base64,' + EncodingUtil.base64Encode(body);
        } catch (Exception e) {
            // Network error, timeout, or a malformed response -- try the
            // next source rather than fail the whole lookup.
            return null;
        }
    }
}
