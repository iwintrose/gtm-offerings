/**
 * Apex read/write surface for the recycle-bin LWC (gtmRecycleBin, part 3 of
 * issue #184's build). Covers GTM_Page_Section__c and GTM_Page_Content__c
 * rows soft-archived by GtmOfferingArchiveCascadeHandler/setOfferingArchived
 * (see docs/architecture/offering-archive-cascade.md): listing what is
 * archived, restoring it, and permanently deleting it.
 *
 * Permission Set grants: GTM_Content_Manager and GTM_Content_Admin both
 * hold classAccesses to this whole class (issue-184-permissions, part 4),
 * which unblocks the read/restore surface for both. Permanent hard-delete
 * (deleteRecord/deleteRecords) is further gated in-code to GTM_Content_Admin
 * only via hasDeleteAccess() below, mirroring
 * GtmAnalyticsTeamController.hasTeamAccess()'s PermissionSetAssignment-query
 * pattern -- classAccesses alone cannot separate "can restore" from "can
 * permanently delete" within one class. GTM_Offering_User/Admin/Guest are
 * deliberately NOT granted classAccesses here; this is Content role tooling.
 *
 * `with sharing`: this is internal Content Manager/admin tooling, never
 * called from a guest Experience Cloud context, so standard record sharing
 * applies. FLS/CRUD is enforced throughout via `WITH USER_MODE` on SOQL and
 * `AccessLevel.USER_MODE` on DML -- the convention already in production use
 * in GtmAccountContactSearchController for this codebase's other admin/rep
 * read surfaces (confirmed via that class before writing this one).
 */
public with sharing class GTM_RecycleBinController {

    /**
     * AuraHandledException has a well-known Apex quirk: passing a message to
     * its constructor does NOT populate what getMessage() returns to the
     * calling LWC unless setMessage() is also called explicitly afterward.
     * Every throw site in this class goes through this helper so callers
     * (and tests asserting on caught messages) actually receive the text
     * instead of the generic "Script-thrown exception".
     */
    private static AuraHandledException handledException(String message) {
        AuraHandledException ahe = new AuraHandledException(message);
        ahe.setMessage(message);
        return ahe;
    }

    /**
     * Gates permanent hard-delete to GTM_Content_Admin only. Both
     * GTM_Content_Manager and GTM_Content_Admin have classAccesses to this
     * whole class (restore/list are fine for either), but a Content_Manager-
     * only user must still be blocked at the server from deleteRecord/
     * deleteRecords, mirroring GtmAnalyticsTeamController.hasTeamAccess()'s
     * PermissionSetAssignment-query pattern rather than inventing a new one.
     */
    private static Boolean hasDeleteAccess() {
        return ![
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
              AND PermissionSet.Name = 'GTM_Content_Admin'
            LIMIT 1
        ].isEmpty();
    }

    private static final String TILE_SECTION_KEY = 'tile';
    private static final String TILE_TEMPLATE_TYPE = 'offerings-listing';

    // ─── Shared "is this offering archived/published" lookup ──────────────
    // Consolidates what was previously two independent copies of the same
    // tile-section query: one in GtmPageContentReader.getOfferingTiles()
    // (the rep-facing dashboard) and one inlined in
    // GtmPageContentController.getHomeSummary(). This is now the one place
    // that query is written; GtmPageContentReader.getOfferingTiles() has
    // been refactored to call it instead of keeping its own copy.

    public class TileStatus {
        @AuraEnabled public String offeringStatus;
        @AuraEnabled public Boolean archived;
    }

    /**
     * The offerings-listing tile row's Offering_Status__c/Archived__c for
     * each offering key that has one, keyed by Offering_Key__c. An offering
     * with no tile section yet simply has no entry -- callers treat "no
     * entry" the same way they always have (getOfferingTiles keeps the
     * offering; nothing here changes that).
     *
     * Deliberately NOT `WITH USER_MODE`: this mirrors the unenforced read
     * GtmPageContentReader.getOfferingTiles() already performed on this same
     * query before this refactor. That method runs `without sharing` so an
     * Experience Cloud guest user can resolve the dashboard; gating this
     * specific query behind FLS now, before GTM_Guest's permission set has
     * been extended for it (deferred to part 4 of this issue), would
     * silently empty guest tile results rather than changing behavior for
     * this slice only.
     */
    public static Map<String, TileStatus> getOfferingTileStatus(Set<String> offeringKeys) {
        Map<String, TileStatus> out = new Map<String, TileStatus>();
        if (offeringKeys == null || offeringKeys.isEmpty()) {
            return out;
        }
        for (GTM_Page_Section__c sec : [
            SELECT Offering_Key__c, Offering_Status__c, Archived__c
            FROM   GTM_Page_Section__c
            WHERE  Template_Type__c = :TILE_TEMPLATE_TYPE
            AND    Section_Key__c   = :TILE_SECTION_KEY
            AND    Offering_Key__c IN :offeringKeys
            LIMIT  500
        ]) {
            TileStatus status = new TileStatus();
            status.offeringStatus = sec.Offering_Status__c;
            status.archived = sec.Archived__c;
            out.put(sec.Offering_Key__c, status);
        }
        return out;
    }

    // ─── List ───────────────────────────────────────────────────────────

    public class ArchivedItem {
        @AuraEnabled public Id recordId;
        /** 'GTM_Page_Section__c' or 'GTM_Page_Content__c'. */
        @AuraEnabled public String objectType;
        @AuraEnabled public String recordName;
        @AuraEnabled public String offeringKey;
        @AuraEnabled public Datetime archivedDate;
        /** No dedicated Archived_By__c field exists on either object; this is
         *  LastModifiedBy.Name at read time, which is accurate as long as no
         *  other field on the row is edited after archiving (the archive
         *  action itself is the only write these rows normally see once
         *  archived). Good enough for display; not a durable audit trail. */
        @AuraEnabled public String archivedBy;
        /** True for an offering's own tile row (Section_Key__c='tile',
         *  Template_Type__c='offerings-listing') -- the "parent" whose
         *  restore also brings its children back via the cascade trigger. */
        @AuraEnabled public Boolean isOfferingTile;
    }

    @AuraEnabled(cacheable=true)
    public static List<ArchivedItem> getArchivedItems() {
        List<ArchivedItem> out = new List<ArchivedItem>();
        try {
            for (GTM_Page_Section__c sec : [
                SELECT Id, Section_Key__c, Template_Type__c, Label__c, Offering_Key__c,
                       Archived_Date__c, LastModifiedBy.Name
                FROM   GTM_Page_Section__c
                WHERE  Archived__c = true
                WITH USER_MODE
                ORDER BY Archived_Date__c DESC NULLS LAST
                LIMIT  1000
            ]) {
                ArchivedItem item = new ArchivedItem();
                item.recordId = sec.Id;
                item.objectType = 'GTM_Page_Section__c';
                item.recordName = String.isNotBlank(sec.Label__c) ? sec.Label__c : sec.Section_Key__c;
                item.offeringKey = sec.Offering_Key__c;
                item.archivedDate = sec.Archived_Date__c;
                item.archivedBy = sec.LastModifiedBy != null ? sec.LastModifiedBy.Name : null;
                item.isOfferingTile = isTile(sec.Section_Key__c, sec.Template_Type__c);
                out.add(item);
            }

            for (GTM_Page_Content__c rec : [
                SELECT Id, Field_Key__c, Section_Key__c, Offering_Key__c,
                       Archived_Date__c, LastModifiedBy.Name
                FROM   GTM_Page_Content__c
                WHERE  Archived__c = true
                WITH USER_MODE
                ORDER BY Archived_Date__c DESC NULLS LAST
                LIMIT  1000
            ]) {
                ArchivedItem item = new ArchivedItem();
                item.recordId = rec.Id;
                item.objectType = 'GTM_Page_Content__c';
                item.recordName = rec.Section_Key__c + '::' + rec.Field_Key__c;
                item.offeringKey = rec.Offering_Key__c;
                item.archivedDate = rec.Archived_Date__c;
                item.archivedBy = rec.LastModifiedBy != null ? rec.LastModifiedBy.Name : null;
                item.isOfferingTile = false;
                out.add(item);
            }
        } catch (Exception e) {
            throw handledException('You do not have access to view the recycle bin.');
        }
        return out;
    }

    // ─── Restore ────────────────────────────────────────────────────────

    public class RestoreResult {
        @AuraEnabled public Id recordId;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }

    /**
     * Restores a single archived record. Wraps restoreRecords() and throws
     * if that one record could not be restored, so a single-record caller
     * gets a normal AuraHandledException rather than having to inspect a
     * one-element result list.
     */
    @AuraEnabled
    public static RestoreResult restoreRecord(Id recordId) {
        List<RestoreResult> results = restoreRecords(new List<Id>{ recordId });
        RestoreResult result = results.isEmpty() ? null : results[0];
        if (result == null || result.success != true) {
            throw handledException(result != null ? result.message : 'That record could not be restored.');
        }
        return result;
    }

    /**
     * Bulk restore. Each requested Id gets its own RestoreResult rather than
     * the whole call failing on the first bad record, so a partial restore
     * (some rows blocked, some not) is visible to the caller.
     *
     * Parent-dependency check: a non-tile GTM_Page_Section__c or any
     * GTM_Page_Content__c row belongs to an offering whose own tile row
     * (Section_Key__c='tile', Template_Type__c='offerings-listing') is the
     * cascade's source of truth (see GtmOfferingArchiveCascadeHandler). If
     * that tile row has been permanently hard-deleted, or is itself still
     * archived, restoring the lone child directly would either orphan it or
     * put it back while its offering still reads as archived -- both
     * rejected here with a clear message instead of a silent partial state.
     * Restoring the tile row itself is always allowed; the cascade trigger
     * then brings its children back automatically.
     */
    @AuraEnabled
    public static List<RestoreResult> restoreRecords(List<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            throw handledException('At least one record is required to restore.');
        }

        List<RestoreResult> results = new List<RestoreResult>();
        try {
            Set<Id> sectionIds = new Set<Id>();
            Set<Id> contentIds = new Set<Id>();
            for (Id recId : recordIds) {
                if (recId.getSObjectType() == GTM_Page_Section__c.SObjectType) {
                    sectionIds.add(recId);
                } else if (recId.getSObjectType() == GTM_Page_Content__c.SObjectType) {
                    contentIds.add(recId);
                }
            }

            Map<Id, GTM_Page_Section__c> sections = sectionIds.isEmpty()
                ? new Map<Id, GTM_Page_Section__c>()
                : new Map<Id, GTM_Page_Section__c>([
                    SELECT Id, Offering_Key__c, Section_Key__c, Template_Type__c, Archived__c
                    FROM   GTM_Page_Section__c
                    WHERE  Id IN :sectionIds AND Archived__c = true
                    WITH USER_MODE
                ]);

            Map<Id, GTM_Page_Content__c> contents = contentIds.isEmpty()
                ? new Map<Id, GTM_Page_Content__c>()
                : new Map<Id, GTM_Page_Content__c>([
                    SELECT Id, Offering_Key__c, Section_Key__c, Template_Type__c, Archived__c
                    FROM   GTM_Page_Content__c
                    WHERE  Id IN :contentIds AND Archived__c = true
                    WITH USER_MODE
                ]);

            Set<String> offeringKeysNeedingTile = new Set<String>();
            for (GTM_Page_Section__c sec : sections.values()) {
                if (!isTile(sec.Section_Key__c, sec.Template_Type__c) && String.isNotBlank(sec.Offering_Key__c)) {
                    offeringKeysNeedingTile.add(sec.Offering_Key__c);
                }
            }
            for (GTM_Page_Content__c rec : contents.values()) {
                if (String.isNotBlank(rec.Offering_Key__c)) {
                    offeringKeysNeedingTile.add(rec.Offering_Key__c);
                }
            }
            Map<String, GTM_Page_Section__c> tileByOfferingKey = getTileRows(offeringKeysNeedingTile);

            List<GTM_Page_Section__c> sectionsToUpdate = new List<GTM_Page_Section__c>();
            List<GTM_Page_Content__c> contentToUpdate = new List<GTM_Page_Content__c>();

            for (Id recId : recordIds) {
                RestoreResult result = new RestoreResult();
                result.recordId = recId;

                if (sections.containsKey(recId)) {
                    GTM_Page_Section__c sec = sections.get(recId);
                    if (isTile(sec.Section_Key__c, sec.Template_Type__c)) {
                        sec.Archived__c = false;
                        sectionsToUpdate.add(sec);
                        result.success = true;
                    } else {
                        String blockReason = parentBlockReason(sec.Offering_Key__c, tileByOfferingKey);
                        if (blockReason != null) {
                            result.success = false;
                            result.message = blockReason;
                        } else {
                            sec.Archived__c = false;
                            sectionsToUpdate.add(sec);
                            result.success = true;
                        }
                    }
                } else if (contents.containsKey(recId)) {
                    GTM_Page_Content__c rec = contents.get(recId);
                    String blockReason = parentBlockReason(rec.Offering_Key__c, tileByOfferingKey);
                    if (blockReason != null) {
                        result.success = false;
                        result.message = blockReason;
                    } else {
                        rec.Archived__c = false;
                        contentToUpdate.add(rec);
                        result.success = true;
                    }
                } else {
                    result.success = false;
                    result.message = 'Record not found, or not currently archived.';
                }
                results.add(result);
            }

            if (!sectionsToUpdate.isEmpty()) {
                Database.update(sectionsToUpdate, AccessLevel.USER_MODE);
            }
            if (!contentToUpdate.isEmpty()) {
                Database.update(contentToUpdate, AccessLevel.USER_MODE);
            }
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw handledException('That could not be restored. Please try again.');
        }
        return results;
    }

    private static String parentBlockReason(String offeringKey, Map<String, GTM_Page_Section__c> tileByOfferingKey) {
        if (String.isBlank(offeringKey)) {
            // No offering context (e.g. a framework-owned row) -- nothing to
            // check a parent tile against.
            return null;
        }
        GTM_Page_Section__c tile = tileByOfferingKey.get(offeringKey);
        if (tile == null) {
            return 'This item\'s offering has been permanently deleted and can no longer be restored on its own.';
        }
        if (tile.Archived__c == true) {
            return 'The offering itself is still archived. Restore the offering before restoring this item.';
        }
        return null;
    }

    private static Map<String, GTM_Page_Section__c> getTileRows(Set<String> offeringKeys) {
        Map<String, GTM_Page_Section__c> out = new Map<String, GTM_Page_Section__c>();
        if (offeringKeys == null || offeringKeys.isEmpty()) {
            return out;
        }
        for (GTM_Page_Section__c sec : [
            SELECT Id, Offering_Key__c, Archived__c
            FROM   GTM_Page_Section__c
            WHERE  Template_Type__c = :TILE_TEMPLATE_TYPE
            AND    Section_Key__c   = :TILE_SECTION_KEY
            AND    Offering_Key__c IN :offeringKeys
            WITH USER_MODE
        ]) {
            out.put(sec.Offering_Key__c, sec);
        }
        return out;
    }

    private static Boolean isTile(String sectionKey, String templateType) {
        return sectionKey == TILE_SECTION_KEY && templateType == TILE_TEMPLATE_TYPE;
    }

    // ─── Permanent delete ───────────────────────────────────────────────

    public class DeleteResult {
        @AuraEnabled public Id recordId;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }

    /**
     * Permanently deletes a single archived record. Wraps deleteRecords()
     * and throws if that one record could not be deleted.
     */
    @AuraEnabled
    public static DeleteResult deleteRecord(Id recordId) {
        if (!hasDeleteAccess()) {
            throw handledException('You are not authorized to permanently delete recycle bin items.');
        }
        List<DeleteResult> results = deleteRecords(new List<Id>{ recordId });
        DeleteResult result = results.isEmpty() ? null : results[0];
        if (result == null || result.success != true) {
            throw handledException(result != null ? result.message : 'That record could not be deleted.');
        }
        return result;
    }

    /**
     * Bulk permanent hard-delete. Only records currently archived
     * (Archived__c = true) are eligible -- a record not found by the
     * Archived__c-filtered query (wrong Id, already deleted, or never
     * archived) comes back as a failed DeleteResult rather than a thrown
     * exception, so a mixed batch still processes what it can.
     */
    @AuraEnabled
    public static List<DeleteResult> deleteRecords(List<Id> recordIds) {
        if (!hasDeleteAccess()) {
            throw handledException('You are not authorized to permanently delete recycle bin items.');
        }
        if (recordIds == null || recordIds.isEmpty()) {
            throw handledException('At least one record is required to delete.');
        }

        List<DeleteResult> results = new List<DeleteResult>();
        try {
            Set<Id> sectionIds = new Set<Id>();
            Set<Id> contentIds = new Set<Id>();
            for (Id recId : recordIds) {
                if (recId.getSObjectType() == GTM_Page_Section__c.SObjectType) {
                    sectionIds.add(recId);
                } else if (recId.getSObjectType() == GTM_Page_Content__c.SObjectType) {
                    contentIds.add(recId);
                }
            }

            if (!sectionIds.isEmpty()) {
                List<GTM_Page_Section__c> toDelete = [
                    SELECT Id FROM GTM_Page_Section__c
                    WHERE Id IN :sectionIds AND Archived__c = true
                    WITH USER_MODE
                ];
                results.addAll(hardDelete(toDelete, sectionIds));
            }
            if (!contentIds.isEmpty()) {
                List<GTM_Page_Content__c> toDelete = [
                    SELECT Id FROM GTM_Page_Content__c
                    WHERE Id IN :contentIds AND Archived__c = true
                    WITH USER_MODE
                ];
                results.addAll(hardDelete(toDelete, contentIds));
            }
        } catch (Exception e) {
            throw handledException('That could not be deleted. Please try again.');
        }
        return results;
    }

    private static List<DeleteResult> hardDelete(List<SObject> records, Set<Id> requestedIds) {
        List<DeleteResult> out = new List<DeleteResult>();
        Set<Id> foundIds = new Set<Id>();
        for (SObject rec : records) {
            foundIds.add((Id) rec.get('Id'));
        }

        if (!records.isEmpty()) {
            Database.DeleteResult[] drs = Database.delete(records, false, AccessLevel.USER_MODE);
            for (Integer i = 0; i < drs.size(); i++) {
                DeleteResult r = new DeleteResult();
                r.recordId = (Id) records[i].get('Id');
                r.success = drs[i].isSuccess();
                r.message = drs[i].isSuccess() ? null : drs[i].getErrors()[0].getMessage();
                out.add(r);
            }
        }

        for (Id requestedId : requestedIds) {
            if (!foundIds.contains(requestedId)) {
                DeleteResult r = new DeleteResult();
                r.recordId = requestedId;
                r.success = false;
                r.message = 'Record not found, or not currently archived (only archived records can be permanently deleted).';
                out.add(r);
            }
        }
        return out;
    }
}
