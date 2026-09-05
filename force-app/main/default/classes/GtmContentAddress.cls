/**
 * The content-address pattern, in one place.
 *
 * Every piece of page content is addressed by what it is rather than by a
 * record id: offering::template::section::field. The address is the external
 * id on MA_Page_Content__c and the join between a section and the rows that
 * belong to it, so how it is spelled — and what a key is allowed to contain —
 * is a single rule, not a convention each caller re-implements.
 */
public with sharing class MaContentAddress {

    public static final String SEPARATOR = '::';

    /** offering::template::section::field — one content record. */
    public static String forField(
        String offeringKey, String templateType, String sectionKey, String fieldKey
    ) {
        return String.join(
            new List<String>{ offeringKey, templateType, sectionKey, fieldKey },
            SEPARATOR
        );
    }

    /** offering::template::section — one section record. */
    public static String forSection(String offeringKey, String templateType, String sectionKey) {
        return String.join(
            new List<String>{ offeringKey, templateType, sectionKey },
            SEPARATOR
        );
    }

    /**
     * A key has to survive being concatenated into an address and split back
     * out of one, so anything that is not a letter or a digit collapses to a
     * hyphen rather than being escaped. Returns null when nothing usable is
     * left, which callers treat as "not a valid key" rather than as a blank.
     */
    public static String normaliseKey(String raw) {
        if (String.isBlank(raw)) return null;
        String cleaned = raw.trim().toLowerCase().replaceAll('[^a-z0-9]+', '-');
        cleaned = cleaned.replaceAll('^-+', '').replaceAll('-+$', '');
        return String.isBlank(cleaned) ? null : cleaned.left(80);
    }
}
