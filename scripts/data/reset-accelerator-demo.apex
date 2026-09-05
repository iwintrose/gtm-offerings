/**
 * Wipe and rebuild the Migration Accelerator's demo data.
 *
 * Deletes ONLY what this app created -- its engagement links, assessment
 * requests, link events, and the accounts, contacts and opportunities those
 * records point at. The Salesforce sample data (Edge Communications, Grand
 * Hotels, GenePoint and the rest) is left alone: nothing here touches a record
 * this app did not create.
 *
 * Then rebuilds a coherent set: four clients across four industries, each with
 * a contact, one opportunity named by MaDealNaming, one engagement link whose
 * payload holds every value (the accent included, so nothing lives only in a
 * URL), an assessment request, and the interaction events behind the overview.
 *
 * Run:  sf apex run --file scripts/data/reset-accelerator-demo.apex
 */

// ─── 1. what this app owns ───────────────────────────────────────────────────
Set<Id> appAccts = new Set<Id>();
Set<Id> appOpps  = new Set<Id>();
Set<Id> appCons  = new Set<Id>();
for (MA_Saved_Configuration__c c : [SELECT Account__c, Contact__c, Opportunity__c FROM MA_Saved_Configuration__c]) {
    if (c.Account__c != null) appAccts.add(c.Account__c);
    if (c.Contact__c != null) appCons.add(c.Contact__c);
    if (c.Opportunity__c != null) appOpps.add(c.Opportunity__c);
}
for (MA_Assessment_Request__c r : [SELECT Account__c, Contact__c, Opportunity__c FROM MA_Assessment_Request__c]) {
    if (r.Account__c != null) appAccts.add(r.Account__c);
    if (r.Contact__c != null) appCons.add(r.Contact__c);
    if (r.Opportunity__c != null) appOpps.add(r.Opportunity__c);
}
for (Opportunity o : [SELECT Id FROM Opportunity WHERE Name LIKE 'DELETE ME%']) appOpps.add(o.Id);

System.debug('deleting: links=' + [SELECT COUNT() FROM MA_Saved_Configuration__c]
    + ' requests=' + [SELECT COUNT() FROM MA_Assessment_Request__c]
    + ' events=' + [SELECT COUNT() FROM MA_Link_Event__c]
    + ' accounts=' + appAccts.size() + ' contacts=' + appCons.size() + ' opps=' + appOpps.size());

delete [SELECT Id FROM MA_Link_Event__c];
delete [SELECT Id FROM MA_Assessment_Request__c];
delete [SELECT Id FROM MA_Saved_Configuration__c];
delete [SELECT Id FROM Opportunity WHERE Id IN :appOpps];
delete [SELECT Id FROM Contact  WHERE Id IN :appCons];
delete [SELECT Id FROM Account  WHERE Id IN :appAccts];

// ─── 2. the clients ──────────────────────────────────────────────────────────
// company | industry key | source | target | accent | assets | deps | health
List<List<String>> spec = new List<List<String>>{
    new List<String>{'MUCH Music','media','Eloqua','Salesforce Marketing Cloud','0B5FFF','4128','9640','62','Marcus Rivera','marcus.rivera@muchmusic.example'},
    new List<String>{'TD Bank','fintech','Marketo','Salesforce Marketing Cloud','1B4F9C','12400','26800','45','Angela Chen','angela.chen@tdbank.example'},
    new List<String>{'Medtronic','medtech','Braze','Salesforce Marketing Cloud Next','00857D','2128','12640','54','Priya Sundaram','priya.sundaram@medtronic.example'},
    new List<String>{'LA Metro','transport','HubSpot','Salesforce Marketing Cloud','C2703A','8400','15200','71','Paul Johns','paul.johns@lametro.example'}
};

List<Account> accounts = new List<Account>();
for (List<String> s : spec) accounts.add(new Account(Name = s[0]));
insert accounts;
Map<String, Id> acctByName = new Map<String, Id>();
for (Account a : accounts) acctByName.put(a.Name, a.Id);

List<Contact> contacts = new List<Contact>();
for (List<String> s : spec) {
    List<String> parts = s[8].split(' ');
    contacts.add(new Contact(
        FirstName = parts[0], LastName = parts.size() > 1 ? parts[1] : parts[0],
        Email = s[9], AccountId = acctByName.get(s[0])));
}
insert contacts;
Map<String, Id> conByAcct = new Map<String, Id>();
for (Contact c : contacts) conByAcct.put(String.valueOf(c.AccountId), c.Id);

// ─── 3. one deal per client, named by the shared authority ───────────────────
List<Opportunity> opps = new List<Opportunity>();
for (List<String> s : spec) {
    Id acct = acctByName.get(s[0]);
    opps.add(new Opportunity(
        Name = MaDealNaming.nameFor(s[0], 'migration-accelerator', null),
        AccountId = acct, StageName = 'Qualification',
        CloseDate = Date.today().addDays(90)));
}
insert opps;
Map<String, Id> oppByAcct = new Map<String, Id>();
for (Opportunity o : opps) oppByAcct.put(String.valueOf(o.AccountId), o.Id);

for (List<String> s : spec) {
    Id acct = acctByName.get(s[0]);
    insert new OpportunityContactRole(
        OpportunityId = oppByAcct.get(String.valueOf(acct)),
        ContactId = conByAcct.get(String.valueOf(acct)),
        Role = 'Decision Maker', IsPrimary = true);
}

// ─── 4. the engagement links ─────────────────────────────────────────────────
// Every value sits in the payload. Nothing lives only in a URL any more.
String base = MaSavedConfigurationController.getConfiguratorPageUrl();
List<MA_Saved_Configuration__c> links = new List<MA_Saved_Configuration__c>();
for (List<String> s : spec) {
    Id acct = acctByName.get(s[0]);
    links.add(new MA_Saved_Configuration__c(
        Offering__c = 'migration-accelerator',
        Company__c = s[0], Industry__c = s[1],
        Account__c = acct, Contact__c = conByAcct.get(String.valueOf(acct)),
        Opportunity__c = oppByAcct.get(String.valueOf(acct)),
        Active__c = true,
        Config_Payload__c = JSON.serialize(new Map<String, String>{
            'SOURCE_PLATFORM' => s[2], 'TARGET_PLATFORM' => s[3],
            'ACCENT' => s[4], 'ASSET_COUNT' => s[5],
            'DEPENDENCY_COUNT' => s[6], 'HEALTH_SCORE' => s[7],
            'CONTACT_NAME' => s[8], 'CONTACT_EMAIL' => s[9]
        })));
}
insert links;
for (MA_Saved_Configuration__c l : links) l.Generated_URL__c = base + '?cfgId=' + l.Id;
update links;

// ─── 5. requests and the interactions behind them ────────────────────────────
//
// Three of the four convert; the fourth opens the form and leaves. That is
// deliberate, and it is the difference the overview has to be able to show: a
// request is the record of an ask, a Form Submitted event is the record of the
// click that made it, and a deal that has one without the other is either a
// bug or a prospect worth chasing. Seeding a request for the client who
// dropped off made every deal look identical and hid both.
Integer CONVERTED = 3;

List<MA_Assessment_Request__c> reqs = new List<MA_Assessment_Request__c>();
Integer i = 0;
for (List<String> s : spec) {
    if (i >= CONVERTED) { i++; continue; }
    Id acct = acctByName.get(s[0]);
    reqs.add(new MA_Assessment_Request__c(
        Requester_Name__c = s[8], Requester_Email__c = s[9],
        Company__c = s[0], Status__c = (i == 0 ? 'Scheduled' : (i == 1 ? 'Contacted' : 'New')),
        Account__c = acct, Contact__c = conByAcct.get(String.valueOf(acct)),
        Opportunity__c = oppByAcct.get(String.valueOf(acct)),
        Saved_Configuration__c = links[i].Id,
        Current_Platform__c = s[2], Target_Platform__c = s[3],
        Submitted_At__c = System.now().addDays(-i)));
    i++;
}
insert reqs;

List<MA_Link_Event__c> events = new List<MA_Link_Event__c>();
for (Integer n = 0; n < links.size(); n++) {
    String session = 'seed-' + n;
    events.add(new MA_Link_Event__c(Saved_Configuration__c = links[n].Id,
        Event_Type__c = 'Page View', Session_Id__c = session, Step__c = 'cover'));
    events.add(new MA_Link_Event__c(Saved_Configuration__c = links[n].Id,
        Event_Type__c = 'Page View', Session_Id__c = session, Step__c = 'proof'));
    events.add(new MA_Link_Event__c(Saved_Configuration__c = links[n].Id,
        Event_Type__c = 'Form Opened', Session_Id__c = session, Step__c = 'assessment'));
    if (n < CONVERTED) {
        events.add(new MA_Link_Event__c(Saved_Configuration__c = links[n].Id,
            Assessment_Request__c = reqs[n].Id,
            Event_Type__c = 'Form Submitted', Session_Id__c = session, Step__c = 'assessment'));
    } else {
        events.add(new MA_Link_Event__c(Saved_Configuration__c = links[n].Id,
            Event_Type__c = 'Drop-off', Session_Id__c = session, Step__c = 'assessment'));
    }
}
insert events;

// ─── 6. what came out ────────────────────────────────────────────────────────
System.debug('=== rebuilt ===');
for (MA_Saved_Configuration__c l : [
    SELECT Name, Company__c, Industry__c, Generated_URL__c, Config_Payload__c,
           Opportunity__r.Name, Contact__r.Name
    FROM MA_Saved_Configuration__c ORDER BY Company__c
]) {
    System.debug(l.Name + ' | ' + l.Company__c + ' (' + l.Industry__c + ')');
    System.debug('    deal    : ' + l.Opportunity__r.Name);
    System.debug('    contact : ' + l.Contact__r.Name);
    System.debug('    link    : ' + l.Generated_URL__c);
    System.debug('    payload : ' + l.Config_Payload__c);
}
System.debug('requests=' + [SELECT COUNT() FROM MA_Assessment_Request__c]
    + ' events=' + [SELECT COUNT() FROM MA_Link_Event__c]);
System.debug('org totals now: accounts=' + [SELECT COUNT() FROM Account]
    + ' opportunities=' + [SELECT COUNT() FROM Opportunity]
    + ' contacts=' + [SELECT COUNT() FROM Contact]);
