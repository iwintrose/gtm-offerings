import { createElement } from 'lwc';
import GtmReadoutView from 'c/gtmReadoutView';
import getPublishedReadout from '@salesforce/apex/GtmReadoutPublicController.getPublishedReadout';
import getCommentSections from '@salesforce/apex/GtmReadoutCommentController.getCommentSections';
import submitComment from '@salesforce/apex/GtmReadoutCommentController.submitComment';

const fs = require('fs');
const path = require('path');
const { SNAPSHOT, CONTENT } = require('./data/fixtures.js');

jest.mock('@salesforce/apex/GtmReadoutPublicController.getPublishedReadout',
    () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmReadoutCommentController.getCommentSections',
    () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/GtmReadoutCommentController.submitComment',
    () => ({ default: jest.fn() }), { virtual: true });

/**
 * Renders the REAL component and writes a standalone page of it, so the design
 * can be looked at in a browser without an org.
 *
 * The markup is the component's own shadow DOM, dumped verbatim, and the CSS
 * is gtmReadoutView.css read off disk — so this page cannot drift from what
 * ships. The only substitutions are the two things a shadow root gives the
 * component for free and a plain page does not: `:host` becomes `.rv-host`,
 * and the Lightning base components (which jest stubs to empty elements) are
 * replaced with plain equivalents. Anything the base components would have
 * rendered — the comment form — is therefore NOT what this page shows; the
 * designed readout, which is what is being reviewed, is all component markup.
 *
 * Skipped unless READOUT_PREVIEW_OUT is set, so a normal test run writes
 * nothing into the repo.
 */
const OUT = process.env.READOUT_PREVIEW_OUT;
const maybe = OUT ? describe : describe.skip;

maybe('readout preview page', () => {
    it('writes a standalone page of the rendered component', async () => {
        getCommentSections.mockResolvedValue(['Verdict', 'Scorecard']);
        submitComment.mockResolvedValue({ accepted: true });
        getPublishedReadout.mockResolvedValue({
            content: CONTENT,
            dataJson: JSON.stringify(SNAPSHOT),
            repName: 'Jordan Reyes',
            repEmail: 'jordan.reyes@publicissapient.com',
            repPhone: '+1 (312) 555-0148'
        });
        delete window.location;
        window.location = { search: '?token=preview', hash: '', pathname: '/s/readout' };

        const element = createElement('c-gtm-readout-view', { is: GtmReadoutView });
        document.body.appendChild(element);
        await new Promise((resolve) => setTimeout(resolve, 0));

        const markup = element.shadowRoot.innerHTML;
        const cssPath = path.join(__dirname, '..', 'gtmReadoutView.css');
        const css = fs.readFileSync(cssPath, 'utf8').replace(/:host\b/g, '.rv-host');

        const page = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Readout preview — rendered from c-gtm-readout-view</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Lato:wght@300;400;700&family=Roboto:wght@300;400;500;700&family=Roboto+Mono:wght@300;400;500;700&display=swap">
<style>html,body{margin:0}${css}</style>
</head><body><div class="rv-host">${markup}</div>
<script>
// The pager and the mode toggle are component behaviour, reproduced here only
// so the two modes can be photographed. Nothing else on the page is scripted.
(function () {
  var root = document.querySelector('.rv-root');
  var q = new URLSearchParams(location.search);
  if (q.get('mode')) root.dataset.mode = q.get('mode');
  if (q.get('theme') === 'dark') root.classList.add('dark');
  if (q.get('theme') === 'light') root.classList.add('light');
  var buttons = root.querySelectorAll('.viewtoggle button');
  if (buttons[0]) buttons[0].onclick = function () { root.dataset.mode = 'present'; };
  if (buttons[1]) buttons[1].onclick = function () { root.dataset.mode = 'read'; };
  if (buttons[2]) buttons[2].onclick = function () { window.print(); };
})();
</script>
</body></html>`;

        fs.mkdirSync(OUT, { recursive: true });
        fs.writeFileSync(path.join(OUT, 'readout-preview.html'), page, 'utf8');
        expect(markup.length).toBeGreaterThan(1000);
    });
});
