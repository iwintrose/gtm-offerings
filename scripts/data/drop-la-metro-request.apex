// One-off correction to the seeded demo set.
//
// reset-accelerator-demo.apex used to create a request for all four clients
// while only three of them submitted the form. LA Metro therefore read as
// "dropped off" and "request received" at the same time, which is the one
// thing the overview's funnel must never say. The reset script no longer
// does this; this brings the current org into line without rebuilding the
// links, whose ids are in URLs that have already been sent.
MA_Assessment_Request__c[] stray = [
    SELECT Id, Name, Company__c, Saved_Configuration__c
    FROM   MA_Assessment_Request__c
    WHERE  Company__c = 'LA Metro'
];
System.debug('found ' + stray.size() + ' LA Metro request(s)');
for (MA_Assessment_Request__c r : stray) {
    Integer submitted = [
        SELECT COUNT() FROM MA_Link_Event__c
        WHERE  Saved_Configuration__c = :r.Saved_Configuration__c
        AND    Event_Type__c = 'Form Submitted'
    ];
    // Only remove a request the funnel says never happened. A request with a
    // submission behind it is real data, whatever the company name.
    if (submitted > 0) { System.debug('keeping ' + r.Name + ': it has a submission'); continue; }
    System.debug('deleting ' + r.Name + ' (no Form Submitted event behind it)');
    delete r;
}
System.debug('requests now=' + [SELECT COUNT() FROM MA_Assessment_Request__c]
    + ' submissions=' + [SELECT COUNT() FROM MA_Link_Event__c WHERE Event_Type__c = 'Form Submitted']);
