/**
 * Attachment point for tools on the app-wide GUS surface (the utility bar).
 * One class per capability implements this and is registered with a single
 * line in GtmAppAgentSurface.registeredTools(). Contract:
 * docs/architecture/gus-utility-bar-host.md sections 4 and 6.
 *
 * execute() contract is the same as GtmAgentToolSurface.executeTool: NEVER
 * throw, NEVER do DML, NEVER do a callout; return a JSON string, using
 * {"error":"..."} for failures. An implementation is itself `with sharing`,
 * receives no user or record id from the surface, and may set
 * accumulatedChanges.put('pageEffect', {...}) to ask the host to navigate.
 */
public interface GtmAppTool {
    /** Anthropic-format tool definitions (each a Map<String,Object>). */
    List<Object> definitions();

    Boolean handles(String toolName);

    String execute(String toolName, Map<String, Object> input, Map<String, Object> accumulatedChanges);

    /** Appended to the system prompt; an empty string is allowed. */
    String promptFragment();
}
