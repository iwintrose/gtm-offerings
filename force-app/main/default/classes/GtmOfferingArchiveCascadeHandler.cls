/**
 * Archive/restore for a whole offering.
 *
 * `GTM_Page_Section__c.Archived__c` on the offering's tile row
 * (Section_Key__c='tile', Template_Type__c='offerings-listing') is the one
 * existing source of truth for "is this offering archived"
 * (GtmPageContentController.setOfferingArchived). This class is that source
 * of truth's downstream: it stamps Archived_Date__c whenever Archived__c
 * actually changes on a record (never re-stamping a write of the value a
 * record already has), and cascades the tile's Archived__c value to every
 * other GTM_Page_Section__c and GTM_Page_Content__c row sharing its
 * Offering_Key__c.
 *
 * See docs/architecture/offering-archive-cascade.md for the full contract.
 */
public with sharing class GtmOfferingArchiveCascadeHandler {

    private static final String TILE_SECTION_KEY = 'tile';
    private static final String TILE_TEMPLATE_TYPE = 'offerings-listing';

    /**
     * Before update on GTM_Page_Section__c: stamp Archived_Date__c on any
     * record whose own Archived__c value changed in this DML. A Checkbox
     * field is never null, so this is a plain !=, and writing the value a
     * record already has is a no-op -- Archived_Date__c is left alone.
     */
    public static void stampSectionDates(List<GTM_Page_Section__c> updated, Map<Id, GTM_Page_Section__c> priorById) {
        if (updated == null || priorById == null) {
            return;
        }
        Datetime stampedAt = Datetime.now();
        for (GTM_Page_Section__c sec : updated) {
            GTM_Page_Section__c prior = priorById.get(sec.Id);
            if (prior == null || sec.Archived__c == prior.Archived__c) {
                continue;
            }
            sec.Archived_Date__c = stampedAt;
        }
    }

    /**
     * Before update on GTM_Page_Content__c: same self-stamp rule as
     * stampSectionDates, but for GTM_Page_Content__c's own Archived__c/
     * Archived_Date__c pair. Fires both for direct edits and for the second
     * DML the cascade below issues against this object.
     */
    public static void stampContentDates(List<GTM_Page_Content__c> updated, Map<Id, GTM_Page_Content__c> priorById) {
        if (updated == null || priorById == null) {
            return;
        }
        Datetime stampedAt = Datetime.now();
        for (GTM_Page_Content__c rec : updated) {
            GTM_Page_Content__c prior = priorById.get(rec.Id);
            if (prior == null || rec.Archived__c == prior.Archived__c) {
                continue;
            }
            rec.Archived_Date__c = stampedAt;
        }
    }

    /**
     * After update on GTM_Page_Section__c: for every tile row whose
     * Archived__c changed in this transaction, push that value onto every
     * other GTM_Page_Section__c and GTM_Page_Content__c row sharing its
     * Offering_Key__c. Only Archived__c is written here -- Archived_Date__c
     * on the cascaded rows comes from each object's own before-update
     * self-stamp above, triggered by this method's DML.
     *
     * Filtering each target query to rows not already at the target value
     * is what makes this idempotent (re-archiving an archived offering
     * touches nothing) and non-recursive (tile rows are excluded from the
     * GTM_Page_Section__c target query, so this handler never re-enters
     * itself).
     */
    public static void cascadeFromTiles(List<GTM_Page_Section__c> updated, Map<Id, GTM_Page_Section__c> priorById) {
        if (updated == null || priorById == null) {
            return;
        }

        Map<String, Boolean> targetByOfferingKey = new Map<String, Boolean>();
        Set<Id> changedTileIds = new Set<Id>();

        for (GTM_Page_Section__c sec : updated) {
            GTM_Page_Section__c prior = priorById.get(sec.Id);
            if (prior == null || !isTile(sec)) {
                continue;
            }
            if (sec.Archived__c == prior.Archived__c) {
                continue;
            }
            if (String.isBlank(sec.Offering_Key__c)) {
                continue;
            }
            targetByOfferingKey.put(sec.Offering_Key__c, sec.Archived__c);
            changedTileIds.add(sec.Id);
        }

        if (targetByOfferingKey.isEmpty()) {
            return;
        }

        cascadeToSections(targetByOfferingKey, changedTileIds);
        cascadeToContent(targetByOfferingKey);
    }

    private static Boolean isTile(GTM_Page_Section__c sec) {
        return sec.Section_Key__c == TILE_SECTION_KEY && sec.Template_Type__c == TILE_TEMPLATE_TYPE;
    }

    private static void cascadeToSections(Map<String, Boolean> targetByOfferingKey, Set<Id> changedTileIds) {
        List<GTM_Page_Section__c> toUpdate = new List<GTM_Page_Section__c>();
        for (GTM_Page_Section__c sibling : [
            SELECT Id, Offering_Key__c, Archived__c
            FROM   GTM_Page_Section__c
            WHERE  Offering_Key__c IN :targetByOfferingKey.keySet()
            AND    Id NOT IN :changedTileIds
        ]) {
            Boolean target = targetByOfferingKey.get(sibling.Offering_Key__c);
            if (sibling.Archived__c == target) {
                continue;
            }
            sibling.Archived__c = target;
            toUpdate.add(sibling);
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private static void cascadeToContent(Map<String, Boolean> targetByOfferingKey) {
        List<GTM_Page_Content__c> toUpdate = new List<GTM_Page_Content__c>();
        for (GTM_Page_Content__c rec : [
            SELECT Id, Offering_Key__c, Archived__c
            FROM   GTM_Page_Content__c
            WHERE  Offering_Key__c IN :targetByOfferingKey.keySet()
        ]) {
            Boolean target = targetByOfferingKey.get(rec.Offering_Key__c);
            if (rec.Archived__c == target) {
                continue;
            }
            rec.Archived__c = target;
            toUpdate.add(rec);
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
