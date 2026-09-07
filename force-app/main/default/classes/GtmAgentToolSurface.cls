/**
 * The seam between the Claude tool-use loop and the thing the loop is allowed
 * to do on a given screen.
 *
 * There is ONE loop (GtmAgentProxyController.runLoop) and one Anthropic callout
 * path. A "surface" is the per-screen half: its system prompt, its tool
 * definitions, and its tool executor. Adding GUS to a new screen means adding a
 * surface, never a second loop — the callout/DML ordering, the round cap and
 * the history handling are properties of the loop and must not be re-derived.
 *
 * Sharing is deliberately NOT specified here. GtmAgentProxyController is
 * `without sharing` (it predates this and is fine for reading configurator page
 * state), and in Apex the sharing keyword is a property of the class the code
 * is *executing in*, not of the caller. So a surface that touches client deal
 * records declares itself `with sharing` and gets sharing back, whatever the
 * loop's class is — see GtmReadoutAgentSurface, which additionally asserts
 * record access explicitly rather than trusting that at all.
 *
 * executeTool contract: NEVER throw, NEVER do DML, NEVER do a callout. Return a
 * JSON string, including for failures ({"error": "..."}), because the string is
 * fed straight back to the model as a tool_result and an exception would kill a
 * conversation the model could have recovered from. No DML because tool calls
 * run *between* Anthropic callouts, and Salesforce forbids DML before a
 * callout in the same transaction. Writes are returned as a delta in
 * accumulatedChanges and applied client-side afterwards.
 */
public interface GtmAgentToolSurface {

    /** The system prompt for this screen. */
    String systemPrompt();

    /** Anthropic tool definitions (each a Map<String,Object>). */
    List<Object> toolDefinitions();

    /**
     * max_tokens for this surface's replies. A surface that only confirms field
     * changes needs far less than one that drafts a readout section, and the
     * number is a property of the job, not of the loop.
     */
    Integer maxTokens();

    /**
     * Run one tool call.
     *
     * @param toolName            name from the model's tool_use block
     * @param input               the model's arguments
     * @param accumulatedChanges  delta bag returned to the LWC after the loop
     * @return                    JSON string handed back as the tool_result
     */
    String executeTool(String toolName, Map<String, Object> input, Map<String, Object> accumulatedChanges);
}
