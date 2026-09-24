/**
 * Content Manager-facing CRUD/publish surface for the live-editable
 * GTM_Instrument__c / GTM_Instrument_Question__c model
 * (docs/architecture/gtm-instrument-editor.md, sub-issue 02 of the
 * instrument-editor-rework umbrella).
 *
 * Not a GUS tool-surface class -- the "no DML/callouts inside a tool
 * implementation" rule (CLAUDE.md/AGENTS.md §1) does not apply here, per the
 * architecture doc §4.1. DML lives directly in these methods.
 *
 * `with sharing`: Content Managers only, gated by the GTM_Content_Manager /
 * GTM_Content_Admin permission sets (architecture doc §6) -- there is no
 * guest or unauthenticated caller of this class.
 */
public with sharing class GtmInstrumentController {

    public class InstrumentDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String offeringKey;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Integer version;
        @AuraEnabled public List<QuestionDto> questions;

        public InstrumentDto() {
            this.questions = new List<QuestionDto>();
        }
    }

    public class QuestionDto {
        @AuraEnabled public Id id;
        @AuraEnabled public Integer slotOrder;
        @AuraEnabled public String questionText;
        @AuraEnabled public String optionsJson;
        @AuraEnabled public String rulesJson;
        @AuraEnabled public Boolean required;
        @AuraEnabled public String questionKey;
    }

    /**
     * The instrument (if any) plus its ordered questions for one offering,
     * for gtmInstrumentAuthor to hydrate. Null when the offering has never
     * opted into this model -- the caller (sub-issue 04) is expected to
     * treat null as "no instrument yet", not an error.
     *
     * Single SOQL: the child questions come back via a subquery rather than
     * a second query, per the umbrella's "single SOQL" note.
     */
    @AuraEnabled(cacheable=true)
    public static InstrumentDto getInstrumentForOffering(String offeringKey) {
        List<GTM_Instrument__c> instruments = [
            SELECT Id, Name, Offering_Key__c, Status__c, Version__c,
                   (SELECT Id, Slot_Order__c, Question_Text__c, Options_JSON__c,
                           Rules_JSON__c, Required__c, Question_Key__c
                    FROM Questions__r
                    ORDER BY Slot_Order__c NULLS LAST)
            FROM GTM_Instrument__c
            WHERE Offering_Key__c = :offeringKey
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (instruments.isEmpty()) {
            return null;
        }
        return toDto(instruments[0]);
    }

    /**
     * Starts a new instrument in Draft, Version 1. Per the architecture doc
     * §4.2's inversion, the moment this insert succeeds the offering is
     * opted out of the legacy "always available" default -- sub-issue 04
     * owns warning about that before calling this.
     */
    @AuraEnabled
    public static InstrumentDto createInstrument(String offeringKey, String name) {
        GTM_Instrument__c instrument = new GTM_Instrument__c(
            Offering_Key__c = offeringKey,
            Name            = name,
            Status__c       = 'Draft',
            Version__c      = 1
        );
        List<GTM_Instrument__c> toInsert = new List<GTM_Instrument__c>{ instrument };
        SObjectAccessDecision decision =
            Security.stripInaccessible(AccessType.CREATABLE, toInsert);
        insert decision.getRecords();

        InstrumentDto dto = new InstrumentDto();
        dto.id          = decision.getRecords()[0].Id;
        dto.offeringKey = offeringKey;
        dto.name        = name;
        dto.status      = 'Draft';
        dto.version     = 1;
        return dto;
    }

    /** Plain field update -- name and/or status (e.g. reverting Active -> Draft). */
    @AuraEnabled
    public static void saveInstrument(Id instrumentId, String name, String status) {
        List<GTM_Instrument__c> toUpdate = new List<GTM_Instrument__c>{
            new GTM_Instrument__c(Id = instrumentId, Name = name, Status__c = status)
        };
        SObjectAccessDecision decision =
            Security.stripInaccessible(AccessType.UPDATABLE, toUpdate);
        update decision.getRecords();
    }

    /**
     * Batched upsert of the authored question set, keyed on Id: rows with an
     * Id are updated, rows without one are inserted as new children of
     * instrumentId. Deletion of removed questions is the caller's job via a
     * separate explicit call (this method only ever adds/updates, never
     * deletes -- an editor accidentally clearing its local list must not be
     * able to wipe authored content by loading a stale array).
     */
    @AuraEnabled
    public static void saveQuestions(Id instrumentId, List<QuestionDto> questions) {
        if (questions == null || questions.isEmpty()) {
            return;
        }
        List<GTM_Instrument_Question__c> toUpsert = new List<GTM_Instrument_Question__c>();
        for (QuestionDto dto : questions) {
            GTM_Instrument_Question__c q = new GTM_Instrument_Question__c(
                Id               = dto.id,
                GTM_Instrument__c = instrumentId,
                Slot_Order__c    = dto.slotOrder,
                Question_Text__c = dto.questionText,
                Options_JSON__c  = dto.optionsJson,
                Rules_JSON__c    = dto.rulesJson,
                Required__c      = dto.required == null ? false : dto.required,
                Question_Key__c  = dto.questionKey
            );
            toUpsert.add(q);
        }
        SObjectAccessDecision decision =
            Security.stripInaccessible(AccessType.UPSERTABLE, toUpsert);
        List<GTM_Instrument_Question__c> sanitized = decision.getRecords();
        // GTM_Instrument__c (master-detail) and Slot_Order__c (required) get
        // no explicit fieldPermissions entries -- they are implicitly
        // visible to anyone with object-level access (CLAUDE.md §6). Because
        // stripInaccessible only recognizes explicit FLS grants, it strips
        // these two fields even from a fully-permissioned Content Manager;
        // restoring them post-strip is what keeps that platform quirk from
        // turning into a REQUIRED_FIELD_MISSING error on every save.
        for (Integer i = 0; i < sanitized.size(); i++) {
            // Master-detail is not reparentable and the platform rejects a
            // write to it on an already-inserted record ("field is not
            // writeable") even when the value is unchanged -- only stamp it
            // on the rows being newly inserted.
            if (questions[i].id == null) {
                sanitized[i].GTM_Instrument__c = instrumentId;
            }
            sanitized[i].Slot_Order__c = questions[i].slotOrder;
        }
        upsert sanitized;
    }

    /**
     * Publishes an instrument: Status -> Active, Version incremented.
     *
     * "Only one Active instrument per Offering_Key__c" is enforced by the
     * schema itself, not by this method: Offering_Key__c is unique
     * (docs/architecture/gtm-instrument-editor.md §2.1), so at most one
     * GTM_Instrument__c row can ever exist for a given offering -- there is
     * no second row to demote. Publishing an instrument therefore always
     * means transitioning THIS row through its own lifecycle
     * (Draft -> Active, or Draft -> Active again after being reverted),
     * never superseding a sibling row.
     */
    @AuraEnabled
    public static void publishInstrument(Id instrumentId) {
        GTM_Instrument__c target = [
            SELECT Id, Version__c
            FROM GTM_Instrument__c
            WHERE Id = :instrumentId
            WITH USER_MODE
            LIMIT 1
        ];

        List<GTM_Instrument__c> toUpdate = new List<GTM_Instrument__c>{
            new GTM_Instrument__c(
                Id         = instrumentId,
                Status__c  = 'Active',
                Version__c = (target.Version__c == null ? 1 : target.Version__c + 1)
            )
        };

        SObjectAccessDecision decision =
            Security.stripInaccessible(AccessType.UPDATABLE, toUpdate);
        update decision.getRecords();
    }

    /** Sets Status__c = 'Archived'. Blocked by GTM_InstrumentTrigger while Active. */
    @AuraEnabled
    public static void archiveInstrument(Id instrumentId) {
        List<GTM_Instrument__c> toUpdate = new List<GTM_Instrument__c>{
            new GTM_Instrument__c(Id = instrumentId, Status__c = 'Archived')
        };
        SObjectAccessDecision decision =
            Security.stripInaccessible(AccessType.UPDATABLE, toUpdate);
        update decision.getRecords();
    }

    private static InstrumentDto toDto(GTM_Instrument__c instrument) {
        InstrumentDto dto = new InstrumentDto();
        dto.id          = instrument.Id;
        dto.offeringKey = instrument.Offering_Key__c;
        dto.name        = instrument.Name;
        dto.status      = instrument.Status__c;
        dto.version     = instrument.Version__c == null ? null : instrument.Version__c.intValue();
        for (GTM_Instrument_Question__c q : instrument.Questions__r) {
            QuestionDto qDto = new QuestionDto();
            qDto.id           = q.Id;
            qDto.slotOrder    = q.Slot_Order__c == null ? null : q.Slot_Order__c.intValue();
            qDto.questionText = q.Question_Text__c;
            qDto.optionsJson  = q.Options_JSON__c;
            qDto.rulesJson    = q.Rules_JSON__c;
            qDto.required     = q.Required__c;
            qDto.questionKey  = q.Question_Key__c;
            dto.questions.add(qDto);
        }
        return dto;
    }
}
