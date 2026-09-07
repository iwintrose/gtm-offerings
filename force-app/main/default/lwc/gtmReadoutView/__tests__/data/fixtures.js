/**
 * The illustrative CMC readout, in both halves.
 *
 * SNAPSHOT is a whole Readout_Data__c — the measurement half, exactly as
 * GtmReadoutModel.buildJson emits it. CONTENT is a whole Approved_Content__c —
 * the prose half, in the seven-heading contract the generator writes and the
 * rep and GUS edit.
 *
 * Between them they are the test of the architecture: the component must be
 * able to render a HubSpot → Marketing Cloud Engagement readout with no
 * scenario literal of its own. See README.md for what is real here and what
 * is illustrative (almost all of it).
 */
const SNAPSHOT = require('./hubspot-to-mce.json');

/**
 * Written the way a rep leaves it after editing the generated draft: the
 * argument in their words, and not one number — every figure on the rendered
 * page comes from the snapshot, which is what stops a readout's prose and its
 * scorecard being able to disagree.
 */
const CONTENT = [
    '<h2>Verdict</h2>',
    '<p>Prep Required with a moderate estate is a workable shape, but the CRM decision has ',
    'to land before anything else is worth building. CMC runs its marketing off the CRM that ',
    'lives inside HubSpot, so switching platform is also switching system of record — and ',
    'that is a business decision, not a migration task.</p>',

    '<h2>Findings</h2>',
    '<h3>1. The CRM decision is the critical path</h3>',
    '<p>Audience modelling, consent mapping and the integration surface are all provisional ',
    'until it is made. Sequencing it first is what stops journeys being built twice.</p>',
    '<h3>2. Active-list semantics are the change nobody expects</h3>',
    '<p>HubSpot lists add and remove contacts continuously. Scheduled-refresh audiences do ',
    'not. Suppression lists are where that difference stops being an inconvenience.</p>',
    '<h3>3. The content library is a build, not a port</h3>',
    '<p>HubL and the custom-module set are the largest single line of effort, and the work is ',
    'front-loaded: the component library has to exist before content migration starts.</p>',

    '<h2>The path</h2>',
    '<p>Foundation and data lead. Audience follows them. Journeys wait on both.</p>',
    '<h3>Goals</h3>',
    '<p>One operating model across the Americas, Europe and Asia, and a contractor and ',
    'distributor view that survives the ERP batch rather than working around it.</p>',

    '<h2>Capability gaps</h2>',
    '<p>The constructs below have no like-for-like equivalent on Marketing Cloud Engagement. ',
    'They are the part of the estimate that is rebuild rather than move.</p>',

    '<h2>Context</h2>',
    '<p>Marketing runs project-cycle nurture for contractors and distributors, with regional ',
    'variation across the Americas, Poland and Asia. The nurture structure itself transfers ',
    'with restructuring; the data underneath it is the constraint.</p>',

    '<h2>Scorecard</h2>',
    '<p>Eight dimensions predict how this goes. They are shown weakest first, because that is ',
    'the order of the work.</p>',

    '<h2>Next steps</h2>',
    '<ul>',
    '<li>A named owner for the CRM decision, and a date by which it is made.</li>',
    '<li>A read-only user on the target Marketing Cloud Engagement sandbox.</li>',
    '<li>The domain list for the external form scan — every site and distributor portal ',
    'posting into HubSpot today.</li>',
    '<li>Two hours for the Assess workshop, where we walk the estate inventory with your team.</li>',
    '</ul>'
].join('\n');

module.exports = { SNAPSHOT, CONTENT };
