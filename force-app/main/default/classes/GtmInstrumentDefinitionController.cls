/**
 * Content Manager-facing CRUD/publish surface for the rebuilt instrument
 * schema (docs/architecture/gtm-instrument-schema.md, sub-issue
 * assessment-instrument-rebuild-01-schema): `GTM_Instrument_Definition__c`,
 * `GTM_Instrument_Question_Definition__c`, and
 * `GTM_Instrument_Outcome_Range__c`.
 *
 * This is a NEW class rather than an extension of `GtmInstrumentController`
 * because that class targets the superseded `GTM_Instrument__c` /
 * `GTM_Instrument_Question__c` model — per gtm-instrument-schema.md §0, "no
 * new work should target them." Adding new-schema methods onto the old
 * class would mix two unrelated object models behind one name, which is
 * exactly the kind of drift the schema doc's supersession note exists to
 * prevent. `GtmInstrumentController` stays deployed, untouched, for the
 * legacy path it still serves (see that doc §6 / §7).
 *
 * Not a GUS tool-surface class -- the "no DML/callouts inside a tool
 * implementation" rule (CLAUDE.md/AGENTS.md §1) does not apply here; DML
 * lives directly in these methods, same convention as `GtmInstrumentController`.
 *
 * `with sharing`: Content Managers only, gated by the `GTM_Content_Manager` /
 * `GTM_Content_Admin` permission sets (schema doc §6) -- there is no guest
 * or unauthenticated caller of this class. Guests reach instrument content
 * only through the submission-side controller
 * (`GtmAssessmentRequestController`), never this one.
 */
public with sharing class GtmInstrumentDefinitionController {

    public class DefinitionDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String offeringKey;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Integer version;
        @AuraEnabled public String themeKey;
        @AuraEnabled public List<QuestionDto> questions;
        @AuraEnabled public List<OutcomeRangeDto> outcomeRanges;

        public DefinitionDto() {
            this.questions = new List<QuestionDto>();
            this.outcomeRanges = new List<OutcomeRangeDto>();
        }
    }

    public class QuestionDto {
        @AuraEnabled public Id id;
        @AuraEnabled public Integer slotOrder;
        @AuraEnabled public String questionText;
        @AuraEnabled public String questionType;
        @AuraEnabled public String optionsJson;
        @AuraEnabled public String rulesJson;
        @AuraEnabled public Boolean required;
        @AuraEnabled public String questionKey;
        @AuraEnabled public Decimal minValue;
        @AuraEnabled public Decimal maxValue;
        @AuraEnabled public Decimal pointsPerUnit;
    }

    public class OutcomeRangeDto {
        @AuraEnabled public Id id;
        @AuraEnabled public Decimal minScore;
        @AuraEnabled public Decimal maxScore;
        @AuraEnabled public String tierLabel;
        @AuraEnabled public String readoutTemplateKey;
        @AuraEnabled public Integer sortOrder;
    }

    /**
     * The definition (if any) plus its ordered questions and outcome ranges
     * for one offering, for the instrument editor LWC to hydrate. Null when
     * the offering has never opted into this model -- the caller is
     * expected to treat null as "no instrument yet", not an error, and
     * offer to create one (createDefinition).
     */
    @AuraEnabled(cacheable=true)
    public static DefinitionDto getDefinitionForOffering(String offeringKey) {
        List<GTM_Instrument_Definition__c> definitions = [
            SELECT Id, Name, Offering_Key__c, Status__c, Version__c, Theme_Key__c,
                   (SELECT Id, Slot_Order__c, Question_Text__c, Question_Type__c,
                           Options_JSON__c, Rules_JSON__c, Required__c, Question_Key__c,
                           Min_Value__c, Max_Value__c, Points_Per_Unit__c
                    FROM Questions__r
                    ORDER BY Slot_Order__c NULLS LAST),
                   (SELECT Id, Min_Score__c, Max_Score__c, Tier_Label__c,
                           Readout_Template_Key__c, Sort_Order__c
                    FROM Outcome_Ranges__r
                    ORDER BY Sort_Order__c NULLS LAST, Min_Score__c NULLS LAST)
            FROM GTM_Instrument_Definition__c
            WHERE Offering_Key__c = :offeringKey
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (definitions.isEmpty()) {
            return null;
        }
        return toDto(definitions[0]);
    }

    /** Starts a new instrument definition in Draft, Version 1. */
    @AuraEnabled
    public static DefinitionDto createDefinition(String offeringKey, String name) {
        GTM_Instrument_Definition__c definition = new GTM_Instrument_Definition__c(
            Offering_Key__c = offeringKey,
            Name            = name,
            Status__c       = 'Draft',
            Version__c      = 1
        );
        List<GTM_Instrument_Definition__c> toInsert =
            new List<GTM_Instrument_Definition__c>{ definition };
        SObjectAccessDecision decision =
            Security.stripInaccessible(AccessType.CREATABLE, toInsert);
        insert decision.getRecords();

        DefinitionDto dto = new DefinitionDto();
        dto.id          = decision.getRecords()[0].Id;
        dto.offeringKey = offeringKey;
        dto.name        = name;
        dto.status      = 'Draft';
        dto.version     = 1;
        return dto;
    }

    /** Plain field update -- name, status, and/or theme key. */
    @AuraEnabled
    public static void saveDefinition(Id definitionId, String name, String status, String themeKey) {
        List<GTM_Instrument_Definition__c> toUpdate = new List<GTM_Instrument_Definition__c>{
            new GTM_Instrument_Definition__c(
                Id         = definitionId,
                Name       = name,
                Status__c  = status,
                Theme_Key__c = themeKey
            )
        };
        SObjectAccessDecision decision =
            Security.stripInaccessible(AccessType.UPDATABLE, toUpdate);
        update decision.getRecords();
    }

    /**
     * Batched upsert of the authored question set, keyed on Id: rows with an
     * Id are updated, rows without one are inserted as new children of
     * definitionId. Deletion of removed questions is a separate explicit
     * call (deleteQuestions) -- this method only ever adds/updates.
     *
     * Takes the question list as a raw JSON string, not
     * `List<QuestionDto>`, and deserializes it here with `JSON.deserialize`
     * -- deliberately, not a style choice. Live gtm-staging debug log
     * 07LgK00000Sj1uHUAR (2026-09-23T19:56:30Z) proved Aura's own
     * automatic parameter binding for `List<QuestionDto>` silently drops
     * `questionText` before this method body even runs (the DTO's
     * `questionText` was already null at the top of the loop below,
     * despite the browser's XHR payload definitively containing the
     * correct string) while a sibling `Integer` field (`slotOrder`) on the
     * exact same inner-class instance bound correctly. A follow-up
     * anonymous-Apex check against gtm-staging confirmed `JSON.deserialize`
     * called directly on the identical JSON string decodes `questionText`
     * correctly every time -- so the defect is specific to Aura's
     * server-side action-parameter binder (a separate code path from
     * `JSON.deserialize`, not the Apex class shape, and not a
     * stripInaccessible/FLS issue -- that runs later, on the sObject, and
     * was ruled out by the same log). Accepting the payload as a string and
     * deserializing it ourselves routes around that binder entirely and
     * uses the path proven to work. See saveOutcomeRanges for the same
     * treatment applied to `OutcomeRangeDto`, which binds through the same
     * Aura mechanism and is equally exposed.
     */
    @AuraEnabled
    public static void saveQuestions(Id definitionId, String questionsJson) {
        List<QuestionDto> questions = parseQuestions(questionsJson);
        if (questions == null || questions.isEmpty()) {
            return;
        }
        List<GTM_Instrument_Question_Definition__c> toUpsert =
            new List<GTM_Instrument_Question_Definition__c>();
        for (QuestionDto dto : questions) {
            GTM_Instrument_Question_Definition__c q = new GTM_Instrument_Question_Definition__c(
                Id                          = dto.id,
                GTM_Instrument_Definition__c = definitionId,
                Slot_Order__c               = dto.slotOrder,
                Question_Text__c            = dto.questionText,
                Question_Type__c            = dto.questionType,
                Options_JSON__c             = dto.optionsJson,
                Rules_JSON__c               = dto.rulesJson,
                Required__c                 = dto.required == null ? false : dto.required,
                Question_Key__c             = dto.questionKey,
                Min_Value__c                = dto.minValue,
                Max_Value__c                = dto.maxValue,
                Points_Per_Unit__c          = dto.pointsPerUnit
            );
            toUpsert.add(q);
        }
        SObjectAccessDecision decision =
            Security.stripInaccessible(AccessType.UPSERTABLE, toUpsert);
        List<GTM_Instrument_Question_Definition__c> sanitized = decision.getRecords();
        // GTM_Instrument_Definition__c (master-detail), Slot_Order__c, and
        // Question_Type__c get no explicit fieldPermissions entries -- they
        // are implicitly visible to anyone with object-level access
        // (CLAUDE.md §6). stripInaccessible only recognizes explicit FLS
        // grants, so it strips these even from a fully-permissioned Content
        // Manager; restoring them post-strip keeps that platform quirk from
        // turning into a REQUIRED_FIELD_MISSING error on every save.
        //
        // Question_Text__c is restored here too, but NOT for the same
        // reason as the fields above (that FLS/stripInaccessible theory was
        // disproven -- see the class-level comment on the `questions`
        // parameter). This restore is now redundant with the fix at the
        // parameter boundary (the JSON.deserialize path never loses the
        // value in the first place), but it's kept as defense in depth:
        // it costs nothing and guards against a future stripInaccessible
        // regression on this field independently of the Aura binding
        // defect that was the real cause here.
        for (Integer i = 0; i < sanitized.size(); i++) {
            if (questions[i].id == null) {
                sanitized[i].GTM_Instrument_Definition__c = definitionId;
            }
            // Slot_Order__c is required; fall back to authored position (1-based)
            // rather than let a missing/blank value on the DTO surface as an
            // opaque REQUIRED_FIELD_MISSING at DML time.
            sanitized[i].Slot_Order__c =
                questions[i].slotOrder == null ? (i + 1) : questions[i].slotOrder;
            sanitized[i].Question_Type__c =
                String.isBlank(questions[i].questionType) ? 'Single_Select' : questions[i].questionType;
            sanitized[i].Question_Text__c = questions[i].questionText;
        }
        upsert sanitized;
    }

    /** Deletes questions the author removed from the editor's local list. */
    @AuraEnabled
    public static void deleteQuestions(List<Id> questionIds) {
        if (questionIds == null || questionIds.isEmpty()) {
            return;
        }
        List<GTM_Instrument_Question_Definition__c> toDelete = new List<GTM_Instrument_Question_Definition__c>();
        for (Id qid : questionIds) {
            toDelete.add(new GTM_Instrument_Question_Definition__c(Id = qid));
        }
        delete toDelete;
    }

    /**
     * Batched upsert of the Outcome Mapping (score-range -> tier/readout)
     * rows for one definition. Same id-keyed upsert/delete-is-separate
     * convention as saveQuestions, and the same raw-JSON-string parameter
     * shape for the same reason documented on saveQuestions: Aura's
     * automatic `List<InnerClass>` parameter binder is the confirmed
     * defect, not any one field, so every inner-class-list parameter on
     * this controller is equally exposed and gets the same treatment.
     */
    @AuraEnabled
    public static void saveOutcomeRanges(Id definitionId, String rangesJson) {
        List<OutcomeRangeDto> ranges = parseOutcomeRanges(rangesJson);
        if (ranges == null || ranges.isEmpty()) {
            return;
        }
        List<GTM_Instrument_Outcome_Range__c> toUpsert = new List<GTM_Instrument_Outcome_Range__c>();
        for (OutcomeRangeDto dto : ranges) {
            GTM_Instrument_Outcome_Range__c r = new GTM_Instrument_Outcome_Range__c(
                Id                          = dto.id,
                GTM_Instrument_Definition__c = definitionId,
                Min_Score__c                = dto.minScore,
                Max_Score__c                = dto.maxScore,
                Tier_Label__c               = dto.tierLabel,
                Readout_Template_Key__c     = dto.readoutTemplateKey,
                Sort_Order__c               = dto.sortOrder
            );
            toUpsert.add(r);
        }
        SObjectAccessDecision decision =
            Security.stripInaccessible(AccessType.UPSERTABLE, toUpsert);
        List<GTM_Instrument_Outcome_Range__c> sanitized = decision.getRecords();
        for (Integer i = 0; i < sanitized.size(); i++) {
            if (ranges[i].id == null) {
                sanitized[i].GTM_Instrument_Definition__c = definitionId;
            }
            sanitized[i].Min_Score__c = ranges[i].minScore;
            sanitized[i].Max_Score__c = ranges[i].maxScore;
        }
        upsert sanitized;
    }

    /** Deletes outcome ranges the author removed from the editor's local list. */
    @AuraEnabled
    public static void deleteOutcomeRanges(List<Id> rangeIds) {
        if (rangeIds == null || rangeIds.isEmpty()) {
            return;
        }
        List<GTM_Instrument_Outcome_Range__c> toDelete = new List<GTM_Instrument_Outcome_Range__c>();
        for (Id rid : rangeIds) {
            toDelete.add(new GTM_Instrument_Outcome_Range__c(Id = rid));
        }
        delete toDelete;
    }

    /** Publishes a definition: Status -> Active, Version incremented. */
    @AuraEnabled
    public static void publishDefinition(Id definitionId) {
        GTM_Instrument_Definition__c target = [
            SELECT Id, Version__c
            FROM GTM_Instrument_Definition__c
            WHERE Id = :definitionId
            WITH USER_MODE
            LIMIT 1
        ];

        List<GTM_Instrument_Definition__c> toUpdate = new List<GTM_Instrument_Definition__c>{
            new GTM_Instrument_Definition__c(
                Id         = definitionId,
                Status__c  = 'Active',
                Version__c = (target.Version__c == null ? 1 : target.Version__c + 1)
            )
        };

        SObjectAccessDecision decision =
            Security.stripInaccessible(AccessType.UPDATABLE, toUpdate);
        update decision.getRecords();
    }

    /** Sets Status__c = 'Archived'. */
    @AuraEnabled
    public static void archiveDefinition(Id definitionId) {
        List<GTM_Instrument_Definition__c> toUpdate = new List<GTM_Instrument_Definition__c>{
            new GTM_Instrument_Definition__c(Id = definitionId, Status__c = 'Archived')
        };
        SObjectAccessDecision decision =
            Security.stripInaccessible(AccessType.UPDATABLE, toUpdate);
        update decision.getRecords();
    }

    /**
     * Deserializes the raw JSON question list sent by the client. See the
     * class-level comment on saveQuestions's `questionsJson` parameter for
     * why this is done manually instead of an `@AuraEnabled` List<QuestionDto>
     * parameter.
     */
    private static List<QuestionDto> parseQuestions(String questionsJson) {
        if (String.isBlank(questionsJson)) {
            return new List<QuestionDto>();
        }
        return (List<QuestionDto>) JSON.deserialize(questionsJson, List<QuestionDto>.class);
    }

    /** Same treatment as parseQuestions, for OutcomeRangeDto. */
    private static List<OutcomeRangeDto> parseOutcomeRanges(String rangesJson) {
        if (String.isBlank(rangesJson)) {
            return new List<OutcomeRangeDto>();
        }
        return (List<OutcomeRangeDto>) JSON.deserialize(rangesJson, List<OutcomeRangeDto>.class);
    }

    private static DefinitionDto toDto(GTM_Instrument_Definition__c definition) {
        DefinitionDto dto = new DefinitionDto();
        dto.id          = definition.Id;
        dto.offeringKey = definition.Offering_Key__c;
        dto.name        = definition.Name;
        dto.status      = definition.Status__c;
        dto.version     = definition.Version__c == null ? null : definition.Version__c.intValue();
        dto.themeKey    = definition.Theme_Key__c;
        for (GTM_Instrument_Question_Definition__c q : definition.Questions__r) {
            QuestionDto qDto = new QuestionDto();
            qDto.id            = q.Id;
            qDto.slotOrder     = q.Slot_Order__c == null ? null : q.Slot_Order__c.intValue();
            qDto.questionText  = q.Question_Text__c;
            qDto.questionType  = q.Question_Type__c;
            qDto.optionsJson   = q.Options_JSON__c;
            qDto.rulesJson     = q.Rules_JSON__c;
            qDto.required      = q.Required__c;
            qDto.questionKey   = q.Question_Key__c;
            qDto.minValue      = q.Min_Value__c;
            qDto.maxValue      = q.Max_Value__c;
            qDto.pointsPerUnit = q.Points_Per_Unit__c;
            dto.questions.add(qDto);
        }
        for (GTM_Instrument_Outcome_Range__c r : definition.Outcome_Ranges__r) {
            OutcomeRangeDto rDto = new OutcomeRangeDto();
            rDto.id                 = r.Id;
            rDto.minScore           = r.Min_Score__c;
            rDto.maxScore           = r.Max_Score__c;
            rDto.tierLabel          = r.Tier_Label__c;
            rDto.readoutTemplateKey = r.Readout_Template_Key__c;
            rDto.sortOrder          = r.Sort_Order__c == null ? null : r.Sort_Order__c.intValue();
            dto.outcomeRanges.add(rDto);
        }
        return dto;
    }
}
