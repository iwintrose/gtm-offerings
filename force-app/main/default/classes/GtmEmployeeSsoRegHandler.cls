/**
 * Registration handler for the GTM_Employee_SSO Auth Provider (issue #106).
 *
 * A rep who is already authenticated in the internal org clicks
 * "Login with Salesforce" on the GTM1 site's login page. Salesforce runs
 * the same-org OAuth handshake and hands the result here to decide who, on
 * the GTM1 site, this identity should become.
 *
 * This handler NEVER creates a user. Every legitimate rep already has an
 * internal user record -- that is the whole premise of "an internal rep
 * SSOs in" -- so the only correct behaviors are (a) find that existing
 * record and link the SSO identity to it, or (b) refuse. Silently
 * provisioning a new user off an OAuth callback on a production identity
 * surface is not a shortcut this class is willing to take (TASK_SCOPE.md
 * §3 item 3, §4).
 *
 * `without sharing`: this runs as part of the platform's own auth pipeline,
 * not as a request from any particular logged-in user, so it must be able
 * to find the matching User row regardless of whatever sharing rules would
 * otherwise apply to the calling context.
 */
global without sharing class GtmEmployeeSsoRegHandler implements Auth.RegistrationHandler {

    /**
     * There is no standard Salesforce-provided exception type for this --
     * any Exception thrown out of createUser() aborts the login with an
     * error page, which is exactly the fail-closed behavior this handler
     * needs.
     */
    public class SsoRegistrationException extends Exception {}

    /**
     * Called once, the first time a given SSO identity authenticates and no
     * existing third-party account link exists for it yet.
     *
     * Despite the name, this does not have to create anything: returning an
     * existing User here tells Salesforce "link this identity to that
     * user", and that link is what makes every later login skip this
     * method entirely. If no existing user matches, this throws rather than
     * inventing one -- fail closed.
     */
    global User createUser(Id portalId, Auth.UserData data) {
        User existing = findExistingUser(data);
        if (existing != null) {
            return existing;
        }
        throw new SsoRegistrationException(
            'No matching internal user for this identity. GTM Employee SSO does not create accounts -- ask your admin to provision the internal user first.'
        );
    }

    /**
     * Called on subsequent logins once a link already exists. There is
     * deliberately nothing to sync here: this handler's only job is
     * identity linking, not profile/role/field maintenance, and touching
     * User fields as a side effect of a login click is out of scope
     * (TASK_SCOPE.md §4).
     */
    global void updateUser(Id userId, Id portalId, Auth.UserData data) {
    }

    /**
     * Matches on Username first (always populated for a same-org
     * providerType=Salesforce identity), falling back to FederationIdentifier
     * for orgs that key identity that way. Inactive users never match --an
     * inactive account should not be silently reactivated by an SSO click.
     */
    @TestVisible
    private static User findExistingUser(Auth.UserData data) {
        String uname = data != null ? data.username : null;
        String fedId = (data != null && data.attributeMap != null)
            ? data.attributeMap.get('federation_id')
            : null;

        if (String.isNotBlank(uname)) {
            List<User> byUsername = [
                SELECT Id FROM User WHERE Username = :uname AND IsActive = true LIMIT 1
            ];
            if (!byUsername.isEmpty()) {
                return byUsername[0];
            }
        }

        if (String.isNotBlank(fedId)) {
            List<User> byFederationId = [
                SELECT Id FROM User WHERE FederationIdentifier = :fedId AND IsActive = true LIMIT 1
            ];
            if (!byFederationId.isEmpty()) {
                return byFederationId[0];
            }
        }

        return null;
    }
}
