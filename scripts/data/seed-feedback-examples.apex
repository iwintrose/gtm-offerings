// Two notes, so both halves of the loop have something to show on first look:
// one still waiting on the writers, one where the writers asked a question back.
// Skips if any feedback already exists, so it never doubles up.
if ([SELECT COUNT() FROM GTM_Offering_Feedback__c] > 0) {
    System.debug('feedback already present — leaving it alone');
} else {
    GtmFeedbackController.FeedbackItem a = GtmFeedbackController.submitFeedback(
        'migration-accelerator', 'story',
        'The "4,128 assets" figure lands well but a client asked where it came from and I had nothing. ' +
        'Could the story say which environment it is drawn from?');
    GtmFeedbackController.FeedbackItem b = GtmFeedbackController.submitFeedback(
        'migration-accelerator', 'configurator',
        'On the closing chapter, "Book the assessment" implies a commitment. Two prospects have read it ' +
        'as signing up for paid work. Something softer would convert better.');
    GtmFeedbackController.respond(b.recordId, 'Needs More Info',
        'Good catch. Do you want it softened everywhere, or just where the link goes to a cold prospect?');
    System.debug('raised ' + a.name + ' (new) and ' + b.name + ' (question asked back)');
    System.debug('open queue: ' + GtmFeedbackController.countOpenFeedback());
}
