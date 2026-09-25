/**
 * GUS on the Content Manager "Draft with AI" modal: the system prompt, the
 * two tools, and the executor. Plugged into the one tool-use loop in
 * GtmAgentProxyController via GtmAgentToolSurface, the same seam
 * GtmReadoutAgentSurface and the configurator's ConfigSurface use.
 *
 * `with sharing`: content editors' own CRUD/FLS on GTM_Page_Section__c /
 * GTM_Page_Content__c applies here, unlike the configurator surface (page
 * state, not client content).
 *
 * NO TOOL ACCEPTS A SECTION KEY. The section this session drafts for is
 * constructor state, taken from the LWC's currently-active section at the
 * moment "Draft with AI" was opened -- same pattern GtmReadoutAgentSurface
 * uses for readoutId. There is no argument shape a confused or
 * prompt-injected model can supply that reaches a different section.
 *
 * Neither tool does DML or a callout. draft_section_variant's validated
 * proposal is merged into accumulatedChanges['proposedFields'] for the LWC
 * to apply through gtmContentManager.writeValue -- the exact same path a
 * manually-typed edit uses (draftValue / isDraft=true / Draft status via
 * saveDrafts). Nothing here can publish.
 */
public with sharing class GtmContentDraftAgentSurface implements GtmAgentToolSurface {

    private static final Integer DRAFT_MAX_TOKENS = 2048;

    private final String offeringKey;
    private final String templateType;
    private final String sectionKey;

    public GtmContentDraftAgentSurface(String offeringKey, String templateType, String sectionKey) {
        this.offeringKey  = offeringKey;
        this.templateType = templateType;
        this.sectionKey   = sectionKey;
    }

    public Integer maxTokens() { return DRAFT_MAX_TOKENS; }

    // ── Prompt ──────────────────────────────────────────────────────────────

    public String systemPrompt(String toneClause) {
        return
        'You are GUS, helping a Content Manager editor draft copy for ONE whole-section industry ' +
        'variant of a Publicis Sapient GTM offering page. The editor already created this variant ' +
        'section (it starts as a copy of the base section''s fields) and wants help tailoring it to ' +
        'one industry.\n\n' +

        'TOOLS:\n' +
        '• get_section_content — reads the variant''s current field values (label, current text) and ' +
        'the industry research brief (problem, use case, solution, proof points). Call this FIRST, ' +
        'every conversation.\n' +
        '• draft_section_variant — proposes new copy for one or more fields. It does NOT save. The ' +
        'editor reviews every proposed field in the field editor and publishes (or doesn''t) through ' +
        'the normal Draft -> Publish flow.\n\n' +

        'RULES:\n' +
        '1. Always call get_section_content before proposing any copy.\n' +
        '2. Only propose values for fieldKeys that get_section_content actually returned for this ' +
        'section. Do not invent field names.\n' +
        '3. Ground every proposal in the industry brief''s problem/useCase/solution/proofLine -- never ' +
        'invent a client fact, a statistic, or a named customer the brief does not support.\n' +
        '4. Keep the base section''s tone and structure; you are tailoring, not rewriting the offering.\n' +
        '5. After calling draft_section_variant, tell the editor plainly: nothing is saved yet, review ' +
        'it in the field editor.\n' +
        '6. Stay in scope -- only this one section''s copy. Redirect other requests politely.\n\n' +
        'TONE: ' + toneClause;
    }

    // ── Tool definitions ───────────────────────────────────────────────────────

    public List<Object> toolDefinitions() {
        return new List<Object>{
            new Map<String, Object>{
                'name'        => 'get_section_content',
                'description' =>
                    'Read this industry variant section''s current field values and its industry ' +
                    'research brief. Takes no arguments -- it is bound to the section the editor has open.',
                'input_schema' => new Map<String, Object>{
                    'type'       => 'object',
                    'properties' => new Map<String, Object>(),
                    'required'   => new List<String>()
                }
            },
            new Map<String, Object>{
                'name'        => 'draft_section_variant',
                'description' =>
                    'Propose new copy for one or more of this section''s fields. Nothing is saved -- ' +
                    'the result goes into the editor''s field editor as an editable draft.',
                'input_schema' => new Map<String, Object>{
                    'type'       => 'object',
                    'properties' => new Map<String, Object>{
                        'field_values_json' => new Map<String, Object>{
                            'type'        => 'string',
                            'description' =>
                                'JSON object mapping fieldKey to proposed copy, e.g. ' +
                                '{"problem": "...", "solution": "..."}. Only fieldKeys from ' +
                                'get_section_content are accepted.'
                        }
                    },
                    'required' => new List<String>{ 'field_values_json' }
                }
            }
        };
    }

    // ── Tool execution ─────────────────────────────────────────────────────────

    public String executeTool(String toolName, Map<String, Object> input,
                              Map<String, Object> accumulatedChanges) {
        try {
            if ('get_section_content'.equals(toolName))  return getSectionContent();
            if ('draft_section_variant'.equals(toolName)) return draftVariant(input, accumulatedChanges);
            return err('Unknown tool: ' + toolName);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'Content draft tool ' + toolName + ' failed on ' + sectionKey + ': ' + e.getMessage());
            return err('That tool failed. Tell the editor and try a different approach.');
        }
    }

    private String getSectionContent() {
        GtmAgentGetSectionContent.Input inp = new GtmAgentGetSectionContent.Input();
        inp.offeringKey  = offeringKey;
        inp.templateType = templateType;
        inp.sectionKey   = sectionKey;
        GtmAgentGetSectionContent.Output out =
            GtmAgentGetSectionContent.execute(new List<GtmAgentGetSectionContent.Input>{ inp })[0];

        List<Object> fields = new List<Object>();
        for (GtmAgentGetSectionContent.FieldSnapshot fs : out.fields) {
            fields.add(new Map<String, Object>{
                'fieldKey'     => fs.fieldKey,
                'fieldType'    => fs.fieldType,
                'label'        => fs.label,
                'currentValue' => fs.currentValue
            });
        }

        return JSON.serialize(new Map<String, Object>{
            'sectionLabel'     => out.sectionLabel,
            'layoutType'       => out.layoutType,
            'industryKey'      => out.industryKey,
            'industryLabel'    => out.industryLabel,
            'baseSectionKey'   => out.baseSectionKey,
            'fields'           => fields,
            'industryBrief'    => String.isBlank(out.industryBriefJson)
                                   ? new Map<String, Object>()
                                   : (Map<String, Object>) JSON.deserializeUntyped(out.industryBriefJson)
        });
    }

    /**
     * Validates the proposal via GtmAgentDraftSectionVariant (no DML), then
     * merges the accepted fields into accumulatedChanges['proposedFields']
     * so a multi-round turn can build up proposals across several tool
     * calls before the model's final reply.
     */
    private String draftVariant(Map<String, Object> input, Map<String, Object> accumulatedChanges) {
        GtmAgentDraftSectionVariant.Input inp = new GtmAgentDraftSectionVariant.Input();
        inp.offeringKey      = offeringKey;
        inp.templateType     = templateType;
        inp.sectionKey       = sectionKey;
        inp.fieldValuesJson  = (String) input.get('field_values_json');

        GtmAgentDraftSectionVariant.Output out =
            GtmAgentDraftSectionVariant.execute(new List<GtmAgentDraftSectionVariant.Input>{ inp })[0];

        if (out.success != true) {
            return JSON.serialize(new Map<String, Object>{
                'success'      => false,
                'errorMessage' => out.errorMessage
            });
        }

        Map<String, Object> applied = (Map<String, Object>) JSON.deserializeUntyped(out.appliedJson);
        Object existingRaw = accumulatedChanges.get('proposedFields');
        Map<String, Object> proposedFields = existingRaw instanceof Map<String, Object>
            ? (Map<String, Object>) existingRaw
            : new Map<String, Object>();
        proposedFields.putAll(applied);
        accumulatedChanges.put('proposedFields', proposedFields);

        return JSON.serialize(new Map<String, Object>{
            'success' => true,
            'applied' => applied,
            'note'    => 'These fields are now in the editor''s field editor as an editable draft. ' +
                         'Nothing is saved until the editor reviews and publishes.'
        });
    }

    private static String err(String message) {
        return JSON.serialize(new Map<String, Object>{ 'error' => message });
    }
}
