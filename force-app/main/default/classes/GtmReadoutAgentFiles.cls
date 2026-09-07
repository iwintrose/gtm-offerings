/**
 * Turns files a rep has attached to a readout into text GUS can read.
 *
 * ── What can actually be read today, and what cannot ──────────────────────
 * Apex has no document parsers. Blob.toString() decodes UTF-8 bytes and that
 * is the whole toolkit. So:
 *
 *   READABLE NOW  txt, md, csv, tsv, json, xml, html, log, yaml, yml —
 *                 anything whose bytes are already text.
 *   NOT READABLE  pdf, docx, doc, pptx, xlsx, images. These are ZIP or binary
 *                 container formats. There is no way to extract their text in
 *                 Apex without an external service, and pretending otherwise
 *                 would produce mojibake that the model would then confidently
 *                 summarise. They are reported to the model as present but
 *                 unreadable, by name and type, so GUS can say "I can see you
 *                 attached the RFP PDF but I cannot read it — paste the section
 *                 you want me to work from" instead of inventing its contents.
 *
 * The Extractor seam below is how that changes without touching callers. A
 * future PDF/DOCX extraction service (an Apex callout to a text-extraction
 * endpoint, or a Salesforce-side converter) implements Extractor and is
 * registered in EXTRACTORS against its file extensions. Nothing else moves.
 * NOTE for whoever does that: extractAll() runs INSIDE the Claude tool-use
 * loop, between callouts. A callout-based extractor must therefore be called
 * before the loop starts and its result passed in, not fired from here.
 *
 * ── Sharing ───────────────────────────────────────────────────────────────
 * `with sharing`, and every entry point is gated on the caller having already
 * asserted access to the readout. ContentDocumentLink is queried by
 * LinkedEntityId = the readout, so a file is only ever reachable through a
 * readout the rep can already open.
 */
public with sharing class GtmReadoutAgentFiles {

    /** Per-file and total character ceilings on what reaches the model. */
    public static final Integer MAX_CHARS_PER_FILE = 12000;
    public static final Integer MAX_CHARS_TOTAL    = 30000;
    public static final Integer MAX_FILES          = 10;

    /** Extensions whose bytes are already text. */
    public static final Set<String> TEXT_EXTENSIONS = new Set<String>{
        'txt', 'md', 'markdown', 'csv', 'tsv', 'json', 'xml', 'html', 'htm',
        'log', 'yaml', 'yml', 'rtf'
    };

    /**
     * Extensions we can see but not read, with the reason stated in the words
     * the model should repeat to the rep. Named explicitly rather than falling
     * through to a generic "unsupported", because "I cannot read PDFs" is
     * actionable and "unsupported file" is not.
     */
    public static final Map<String, String> UNREADABLE_REASONS = new Map<String, String>{
        'pdf'  => 'PDF text cannot be extracted in Salesforce Apex without an external extraction service, which is not configured.',
        'docx' => 'Word .docx is a ZIP container; its text cannot be extracted in Apex without an external extraction service.',
        'doc'  => 'Legacy Word .doc is a binary format that cannot be read in Apex.',
        'pptx' => 'PowerPoint .pptx is a ZIP container; its text cannot be extracted in Apex without an external extraction service.',
        'ppt'  => 'Legacy PowerPoint .ppt is a binary format that cannot be read in Apex.',
        'xlsx' => 'Excel .xlsx is a ZIP container; its text cannot be extracted in Apex. Export the sheet as CSV and attach that instead.',
        'xls'  => 'Legacy Excel .xls is a binary format that cannot be read in Apex. Export as CSV instead.',
        'zip'  => 'Archives are not unpacked. Attach the individual files.',
        'png'  => 'Images are not read. Describe the content, or paste the numbers.',
        'jpg'  => 'Images are not read. Describe the content, or paste the numbers.',
        'jpeg' => 'Images are not read. Describe the content, or paste the numbers.',
        'gif'  => 'Images are not read. Describe the content, or paste the numbers.'
    };

    /**
     * The seam a future extraction service plugs into. Implementations must be
     * side-effect free and must not call out from inside the tool loop.
     */
    public interface Extractor {
        String extract(ContentVersion version);
    }

    /** Extension → extractor. Empty today; the plain-text path is built in. */
    private static final Map<String, Extractor> EXTRACTORS = new Map<String, Extractor>();

    /** Test/registration seam for a future service. */
    public static void register(String extension, Extractor extractor) {
        if (String.isNotBlank(extension) && extractor != null) {
            EXTRACTORS.put(extension.toLowerCase(), extractor);
        }
    }

    /**
     * One entry per file attached to the readout:
     *   { title, extension, sizeBytes, readable, text | reason }
     *
     * Never throws — the caller is a tool executor.
     */
    public static List<Object> extractAll(Id readoutId) {
        List<Object> out = new List<Object>();
        if (readoutId == null) return out;

        try {
            Set<Id> docIds = new Set<Id>();
            for (ContentDocumentLink link : [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :readoutId
                LIMIT 200
            ]) {
                docIds.add(link.ContentDocumentId);
            }
            if (docIds.isEmpty()) return out;

            Integer budget = MAX_CHARS_TOTAL;
            for (ContentVersion v : [
                SELECT Id, Title, FileExtension, ContentSize, VersionData, CreatedDate
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                  AND IsLatest = true
                ORDER BY CreatedDate DESC
                LIMIT :MAX_FILES
            ]) {
                Map<String, Object> row = describe(v, budget);
                out.add(row);
                Object text = row.get('text');
                if (text != null) budget -= String.valueOf(text).length();
                if (budget < 0) budget = 0;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Attachment read failed: ' + e.getMessage());
        }
        return out;
    }

    private static Map<String, Object> describe(ContentVersion v, Integer budget) {
        String ext = String.isBlank(v.FileExtension) ? '' : v.FileExtension.toLowerCase();

        Map<String, Object> row = new Map<String, Object>{
            'title'     => v.Title,
            'extension' => ext,
            'sizeBytes' => v.ContentSize
        };

        if (budget <= 0) {
            row.put('readable', false);
            row.put('reason', 'Skipped: the attached files already filled the text budget for this conversation.');
            return row;
        }

        Extractor custom = EXTRACTORS.get(ext);
        if (custom != null) {
            try {
                String text = custom.extract(v);
                return withText(row, text, budget);
            } catch (Exception e) {
                row.put('readable', false);
                row.put('reason', 'The extraction service could not read this file.');
                return row;
            }
        }

        if (UNREADABLE_REASONS.containsKey(ext)) {
            row.put('readable', false);
            row.put('reason', UNREADABLE_REASONS.get(ext));
            return row;
        }

        if (!TEXT_EXTENSIONS.contains(ext)) {
            row.put('readable', false);
            row.put('reason',
                'Only plain-text formats (txt, md, csv, tsv, json, xml, html, log, yaml) can be read here. ' +
                'Paste the relevant part into the chat or into your notes instead.');
            return row;
        }

        try {
            return withText(row, v.VersionData == null ? '' : v.VersionData.toString(), budget);
        } catch (Exception e) {
            // toString() throws on bytes that are not valid UTF-8 — which is
            // exactly what a binary file misnamed .txt looks like.
            row.put('readable', false);
            row.put('reason', 'This file is not valid UTF-8 text, so it could not be read.');
            return row;
        }
    }

    private static Map<String, Object> withText(Map<String, Object> row, String text, Integer budget) {
        Integer cap = Math.min(MAX_CHARS_PER_FILE, budget);
        String clipped = (text == null) ? '' : text;
        Boolean truncated = clipped.length() > cap;
        if (truncated) clipped = clipped.substring(0, cap);
        row.put('readable', true);
        row.put('truncated', truncated);
        row.put('text', clipped);
        return row;
    }
}
