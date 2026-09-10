// GUS tone — seeds the new agentTone field on the Framework assistant page
// (gtm::assistant::assistant::agentTone), so the field is visible and
// editable in Content Manager from day one rather than only appearing via
// the "missing fields" prompt. Field_Type__c='enum'; the stored value is a
// KEY into GtmAgentTone.TONE_CLAUSES, never prompt text itself.
//
// The section (gtm::assistant::assistant) already exists — this only adds
// one field row alongside assistantName/assistantRole/fabLabel/greeting/
// inputPlaceholder. Idempotent: upserts by Content_Address__c external ID,
// so a re-run does not duplicate anything or clobber a value someone has
// since edited through Content Manager.
//
// Run via: sf apex run --file scripts/data/seed-agent-tone.apex --target-org gtm-dev

GtmPageContentController.ContentRecord r = new GtmPageContentController.ContentRecord();
r.offeringKey  = 'gtm';
r.templateType = 'assistant';
r.sectionKey   = 'assistant';
r.fieldKey     = 'agentTone';
r.fieldType    = 'enum';
r.textValue    = GtmAgentTone.DEFAULT_KEY; // 'professional-concise'
r.active       = true;
r.status       = 'Published';
r.sortOrder    = 60; // after assistantName/assistantRole/fabLabel/greeting/inputPlaceholder

List<String> ids = GtmPageContentController.saveContentRecords(
    new List<GtmPageContentController.ContentRecord>{ r }
);
System.debug('Seeded agentTone content row, id=' + ids[0]);

System.debug('=== verify ===');
System.debug('GtmAgentTone.clause() => ' + GtmAgentTone.clause());
