/**
 * Unified Account/Contact typeahead shared by gtmReadoutAccountFinder (the
 * Assessments tab trail) and gtmRepLinkFinder (the Pages tab trail),
 * replacing each component's original Account-only
 * lightning-record-picker first step (issue-gtm-assessments-account-
 * contact-trail follow-up -- see
 * docs/architecture/gtm-unified-account-contact-search.md).
 *
 * Deliberately its own class, not folded into GtmReadoutController or
 * GtmRepLinkFinderController: this search is not scoped to Assessment
 * Requests or Saved Configurations, it is a generic "find the
 * Account/Contact I mean" lookup both trails need identically.
 *
 * `with sharing`: a rep only ever sees Accounts/Contacts their own sharing
 * rules already grant them, same as every other read path in this area.
 * No DML anywhere in this class.
 */
public with sharing class GtmAccountContactSearchController {

    public class SearchResult {
        @AuraEnabled public String recordId;
        /** 'Account' or 'Contact'. */
        @AuraEnabled public String type;
        /** Account.Name, or "First Last" for a Contact. */
        @AuraEnabled public String label;
        /** '' for an Account result; the parent Account's Name for a Contact
         *  result, so the LWC can show it as a sub-label. */
        @AuraEnabled public String subLabel;
        /** The Account.Id this result resolves to either way -- itself for
         *  an Account result, the parent Account for a Contact result. Lets
         *  the LWC drive its existing Account-keyed drill-down
         *  (getContactsWithRequests/getContactsWithLinks) from either kind
         *  of result without a separate code path. */
        @AuraEnabled public String accountId;
    }

    /**
     * Up to 5 Accounts and 5 Contacts matching searchTerm, one SOSL query
     * (the documented FIND ... RETURNING pattern -- Apex Developer Guide,
     * "Search Queries"). Security.stripInaccessible() is applied to each
     * returned list before it is mapped into SearchResult: SOSL has no
     * WITH SECURITY_ENFORCED, stripInaccessible is the documented FLS-safe
     * substitute (Apex Developer Guide, "Security.stripInaccessible").
     *
     * Returns [] for null/blank input, or input under 2 characters, rather
     * than throwing -- the LWC callers already gate the call itself at 2+
     * characters (debounced client-side), but this method does not trust
     * that gate alone.
     *
     * Deliberately NOT cacheable: results are keyed on a live, freshly
     * typed search term fired on (debounced) every keystroke -- there is no
     * stable cache key a rep would hit twice the way a cacheable=true wire
     * benefits from.
     */
    @AuraEnabled(cacheable=false)
    public static List<SearchResult> searchAccountsAndContacts(String searchTerm) {
        List<SearchResult> out = new List<SearchResult>();
        if (searchTerm == null) {
            return out;
        }
        String trimmed = searchTerm.trim();
        if (trimmed.length() < 2) {
            return out;
        }

        String term = '*' + String.escapeSingleQuotes(trimmed) + '*';
        List<List<SObject>> results = [
            FIND :term IN ALL FIELDS
            RETURNING
                Account(Id, Name LIMIT 5),
                Contact(Id, FirstName, LastName, AccountId, Account.Name LIMIT 5)
        ];

        List<SObject> accounts = results.size() > 0 ? results[0] : new List<SObject>();
        List<SObject> contacts = results.size() > 1 ? results[1] : new List<SObject>();

        SObjectAccessDecision accountDecision =
            Security.stripInaccessible(AccessType.READABLE, accounts);
        SObjectAccessDecision contactDecision =
            Security.stripInaccessible(AccessType.READABLE, contacts);

        for (SObject sObj : accountDecision.getRecords()) {
            Account acc = (Account) sObj;
            SearchResult r = new SearchResult();
            r.recordId  = acc.Id;
            r.type      = 'Account';
            r.label     = acc.Name;
            r.subLabel  = '';
            r.accountId = acc.Id;
            out.add(r);
        }

        for (SObject sObj : contactDecision.getRecords()) {
            Contact con = (Contact) sObj;
            SearchResult r = new SearchResult();
            r.recordId  = con.Id;
            r.type      = 'Contact';
            r.label     = fullName(con.FirstName, con.LastName);
            r.subLabel  = con.Account != null ? con.Account.Name : '';
            r.accountId = con.AccountId;
            out.add(r);
        }

        return out;
    }

    private static String fullName(String firstName, String lastName) {
        if (String.isBlank(firstName)) {
            return lastName;
        }
        if (String.isBlank(lastName)) {
            return firstName;
        }
        return firstName + ' ' + lastName;
    }
}
