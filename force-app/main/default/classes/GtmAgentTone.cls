/**
 * GUS's tone setting, resolved from content instead of hardcoded in two Apex
 * prompts. Backs the Framework `assistant` page's `agentTone` field
 * (GTM_Page_Content__c: Offering_Key__c='gtm', Template_Type__c='assistant',
 * Section_Key__c='assistant', Field_Key__c='agentTone', Field_Type__c='enum').
 *
 * SECURITY: this is the whole point of the design. A content author can only
 * ever *select* one of the pre-written sentences below -- never write new
 * prompt text, however they get to the field (the UI's closed
 * lightning-combobox, or a direct API/data-loader write to Text_Value__c).
 * The stored value is looked up as a KEY in this fixed, developer-authored
 * map; it is never interpolated into the prompt as text. An unrecognized key
 * -- blank, deleted, hand-typed garbage, or an injection attempt -- silently
 * falls back to DEFAULT_KEY's clause. There is no code path where an
 * unrecognized string reaches the callout body.
 *
 * without sharing: reuses GtmPageContentReader.getPageContent, which is
 * itself without sharing for the same reason its own header documents --
 * framework content is admin-owned, not user-owned. A `with sharing` caller
 * (GtmReadoutAgentSurface) still resolves it correctly: Apex resolves
 * sharing per executing class.
 */
public without sharing class GtmAgentTone {
    private static final String FRAMEWORK_KEY  = 'gtm';       // mirrors gtmPageLayouts.FRAMEWORK_KEY
    private static final String TEMPLATE_TYPE  = 'assistant';
    private static final String CONTENT_ADDR   = 'assistant::agentTone';
    public  static final String DEFAULT_KEY    = 'professional-concise';

    // Keys here MUST match AGENT_TONE_OPTIONS in gtmPageLayouts.js exactly.
    // The value is the ONLY text that ever reaches the prompt -- the field
    // itself only ever selects a key; it never supplies prompt text.
    private static final Map<String,String> TONE_CLAUSES = new Map<String,String>{
        'professional-concise' => 'Professional and concise. One or two sentences per response.',
        'warm-consultative'    => 'Warm and consultative, like a trusted advisor speaking with a peer. Two to three sentences; more conversational than clipped.',
        'direct-executive'     => 'Direct and efficient, addressing a senior executive audience. One sentence where possible — no filler, no hedging.',
        'technical-precise'    => 'Precise and technically fluent. Prefer exact field, object and platform names over general language.'
    };

    /** The one thing callers use. Never throws, never returns free text
     *  that didn't come from the map above. */
    public static String clause() {
        Map<String,String> content =
            GtmPageContentReader.getPageContent(FRAMEWORK_KEY, TEMPLATE_TYPE, null);
        String key = content.get(CONTENT_ADDR);
        return TONE_CLAUSES.containsKey(key) ? TONE_CLAUSES.get(key) : TONE_CLAUSES.get(DEFAULT_KEY);
    }
}
