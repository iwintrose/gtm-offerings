/**
 * How a model-proposed change becomes new readout HTML. Pure computation: no
 * SOQL, no DML, no callouts, no record Ids. It is handed the current draft and
 * a proposed fragment and returns the resulting document — which is what makes
 * every rule in here unit-testable without an org.
 *
 * ── Why sections rather than whole documents ──────────────────────────────
 * The generated draft is a flat sequence of <h2>/<h3> headings and blocks
 * (GtmReadoutController.buildReadoutHtml). Asking the model to re-emit the whole
 * document to change one paragraph is how scores silently drift: the numbers
 * are in the same string it is rewriting. So the default mode is
 * replace_section, which swaps the content under ONE heading and leaves every
 * other byte — including the scored breakdown — exactly as it was.
 * replace_all exists because sometimes the rep really does want a rewrite, but
 * it is the mode that has to be asked for.
 *
 * ── Sanitising ────────────────────────────────────────────────────────────
 * Draft_Content__c is a rich-text field rendered by
 * lightning-formatted-rich-text, and on the published side by
 * gtmReadoutView — so what lands here is eventually read by a prospect. Model
 * output is not trusted markup: scripts, event handlers, javascript: URLs,
 * iframes, forms and style blocks are stripped. This is an allow-nothing-
 * dangerous pass on top of the platform's own rich-text sanitising, not a
 * replacement for it.
 */
public with sharing class GtmReadoutAgentEdit {

    /** Draft_Content__c holds 32768 characters. */
    public static final Integer MAX_CONTENT_CHARS = 32768;

    public static final String MODE_REPLACE_SECTION = 'replace_section';
    public static final String MODE_APPEND_SECTION  = 'append_section';
    public static final String MODE_REPLACE_ALL     = 'replace_all';

    public static final Set<String> MODES = new Set<String>{
        MODE_REPLACE_SECTION, MODE_APPEND_SECTION, MODE_REPLACE_ALL
    };

    /** Outcome of one proposed edit. */
    public class Result {
        public Boolean success;
        public String content;
        public String message;
        Result(Boolean success, String content, String message) {
            this.success = success;
            this.content = content;
            this.message = message;
        }
    }

    public static Result failure(String message) {
        return new Result(false, null, message);
    }

    /**
     * @param currentHtml    the rep's working draft (may be blank)
     * @param mode           replace_section | append_section | replace_all
     * @param heading        the heading to target, for the two section modes
     * @param html           the proposed fragment
     */
    public static Result apply(String currentHtml, String mode, String heading, String html) {
        String safeMode = String.isBlank(mode) ? MODE_REPLACE_SECTION : mode.trim().toLowerCase();
        if (!MODES.contains(safeMode)) {
            return failure('mode must be one of: replace_section, append_section, replace_all.');
        }
        if (String.isBlank(html)) {
            return failure('html is required and must not be empty.');
        }

        String clean = sanitize(html);
        if (String.isBlank(clean)) {
            return failure('The proposed HTML was empty once unsafe markup was removed.');
        }

        String base = currentHtml == null ? '' : currentHtml;
        String result;

        if (safeMode == MODE_REPLACE_ALL) {
            result = clean;
        } else if (safeMode == MODE_APPEND_SECTION) {
            if (String.isBlank(heading)) {
                return failure('section_heading is required for append_section.');
            }
            result = (String.isBlank(base) ? '' : base + '\n') +
                     '<h3>' + heading.trim().escapeHtml4() + '</h3>\n' + clean;
        } else {
            if (String.isBlank(heading)) {
                return failure('section_heading is required for replace_section.');
            }
            Integer[] span = sectionSpan(base, heading.trim());
            if (span == null) {
                return failure(
                    'No section headed "' + heading.trim() + '" exists in the draft. ' +
                    'Use append_section to add it, or name an existing heading exactly.'
                );
            }
            result = base.substring(0, span[0]) + clean + base.substring(span[1]);
        }

        if (result.length() > MAX_CONTENT_CHARS) {
            return failure(
                'The result would be ' + result.length() + ' characters; the readout field holds ' +
                MAX_CONTENT_CHARS + '. Shorten the section.'
            );
        }
        return new Result(true, result, 'Applied to the working draft. Not saved yet.');
    }

    /**
     * Start and end offsets of the BODY under a heading — from just after the
     * heading's closing tag to just before the next heading of the same or a
     * higher level (so replacing an <h2> section takes its <h3> children with
     * it, and replacing an <h3> does not eat its sibling <h2>).
     *
     * Heading match is case-insensitive on the visible text with whitespace
     * collapsed, because the model is repeating a heading back to us from a
     * tool result and will not reproduce the whitespace byte for byte.
     *
     * @return {bodyStart, bodyEnd}, or null when no such heading exists.
     */
    public static Integer[] sectionSpan(String html, String heading) {
        if (String.isBlank(html) || String.isBlank(heading)) return null;

        Matcher m = Pattern.compile('(?is)<h([1-6])[^>]*>(.*?)</h\\1\\s*>').matcher(html);
        String wanted = normalise(heading);

        Integer level = null;
        Integer bodyStart = null;
        while (m.find()) {
            Integer thisLevel = Integer.valueOf(m.group(1));
            if (bodyStart == null) {
                if (normalise(stripTags(m.group(2))) == wanted) {
                    level = thisLevel;
                    bodyStart = m.end();
                }
                continue;
            }
            // Past the target heading: the section ends at the next heading of
            // the same or a higher level (a lower number is higher).
            if (thisLevel <= level) {
                return new Integer[]{ bodyStart, m.start() };
            }
        }
        return bodyStart == null ? null : new Integer[]{ bodyStart, html.length() };
    }

    /** Every heading in the draft, in order — what GUS shows the rep. */
    public static List<String> headings(String html) {
        List<String> out = new List<String>();
        if (String.isBlank(html)) return out;
        Matcher m = Pattern.compile('(?is)<h([1-6])[^>]*>(.*?)</h\\1\\s*>').matcher(html);
        while (m.find()) {
            String text = stripTags(m.group(2)).trim();
            if (String.isNotBlank(text)) out.add(text);
        }
        return out;
    }

    /**
     * Strips the markup that must never reach a prospect's browser. Ordered so
     * that element removal happens before attribute removal, and both before
     * the URL scheme pass, so nothing can be reassembled from the leftovers.
     */
    public static String sanitize(String html) {
        if (String.isBlank(html)) return '';
        String out = html;
        // Whole elements, content included.
        out = out.replaceAll('(?is)<script[^>]*>.*?</script\\s*>', '');
        out = out.replaceAll('(?is)<style[^>]*>.*?</style\\s*>', '');
        out = out.replaceAll('(?is)<iframe[^>]*>.*?</iframe\\s*>', '');
        out = out.replaceAll('(?is)<object[^>]*>.*?</object\\s*>', '');
        out = out.replaceAll('(?is)<embed[^>]*>.*?</embed\\s*>', '');
        out = out.replaceAll('(?is)<form[^>]*>.*?</form\\s*>', '');
        // Unclosed or self-closing forms of the same.
        out = out.replaceAll('(?is)</?(script|style|iframe|object|embed|form|input|button|link|meta|base)[^>]*>', '');
        // Inline event handlers, quoted or bare.
        out = out.replaceAll('(?is)\\son[a-z]+\\s*=\\s*"[^"]*"', '');
        out = out.replaceAll('(?is)\\son[a-z]+\\s*=\\s*\'[^\']*\'', '');
        out = out.replaceAll('(?is)\\son[a-z]+\\s*=\\s*[^\\s>]+', '');
        // Script-bearing URL schemes.
        out = out.replaceAll('(?is)(href|src|action|formaction)\\s*=\\s*"\\s*(javascript|data|vbscript):[^"]*"', '');
        out = out.replaceAll('(?is)(href|src|action|formaction)\\s*=\\s*\'\\s*(javascript|data|vbscript):[^\']*\'', '');
        out = out.replaceAll('(?is)(href|src|action|formaction)\\s*=\\s*(javascript|data|vbscript):[^\\s>]*', '');
        return out.trim();
    }

    private static String stripTags(String value) {
        return value == null ? '' : value.replaceAll('(?is)<[^>]*>', '');
    }

    private static String normalise(String value) {
        return value == null
            ? ''
            : value.replaceAll('\\s+', ' ').trim().toLowerCase();
    }
}
