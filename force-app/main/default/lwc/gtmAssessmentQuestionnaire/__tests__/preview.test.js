import { createElement } from 'lwc';
import GtmAssessmentQuestionnaire from 'c/gtmAssessmentQuestionnaire';
import getPlatforms from '@salesforce/apex/GtmAssessmentInstrument.getPlatforms';
import getPack from '@salesforce/apex/GtmAssessmentInstrument.getPack';
import getQuestionnaire from '@salesforce/apex/GtmAssessmentQuestions.getQuestionnaire';
import submitRequest from '@salesforce/apex/GtmAssessmentRequestController.submitRequest';
import saveDraft from '@salesforce/apex/GtmAssessmentDraftController.saveDraft';
import resumeDraft from '@salesforce/apex/GtmAssessmentDraftController.resumeDraft';
import emailResumeLink from '@salesforce/apex/GtmAssessmentDraftController.emailResumeLink';

const fs = require('fs');
const path = require('path');

jest.mock(
    '@salesforce/apex/GtmAssessmentInstrument.getPlatforms',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentInstrument.getPack',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentQuestions.getQuestionnaire',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentRequestController.submitRequest',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentDraftController.saveDraft',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentDraftController.resumeDraft',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentDraftController.emailResumeLink',
    () => ({ default: jest.fn() }), { virtual: true }
);

/**
 * Renders the REAL c-gtm-assessment-questionnaire, walked through two real
 * migration pairs, and writes ONE standalone page holding every screen it
 * showed along the way -- so the actual prospect experience (its own markup,
 * its own CSS) can be reviewed in a browser without an org.
 *
 * DATA. `./data/questionnaire.json` is a verbatim copy of
 * `/tmp/gen-assessment/orgdata/questionnaire.json`, pulled read-only from
 * `gtm-dev` via `sf apex run` against `GtmAssessmentInstrument.getPlatforms`
 * and `.getPack` -- exactly what a guest's browser receives. It is
 * instrument configuration (question text, scoring, branch predicates), not
 * prospect data, so it is safe to check in; nothing about a real engagement
 * link or a real respondent is in it.
 *
 * TWO PATHS, DELIBERATELY. Neither real pair on its own demonstrates both
 * pieces of branching behaviour worth seeing:
 *   - HubSpot -> SFMC caps `source_access` at 3 (no HubSpot connector ships
 *     today) -- rendered disabled, struck through, with its reason, never
 *     silently dropped.
 *   - SFMC -> Marketing Cloud Next substitutes a different question for slot
 *     7 (`consent_portability`) when `integration_containment` (slot 6) is
 *     answered <= 2 -- a real showWhenJson branch firing, not a mocked one.
 * Walking both is the only way to put both in front of a reviewer without
 * inventing pack data the way the hand-authored document version did.
 *
 * WHAT MAKES THIS TRACTABLE. Zero Lightning base components in this
 * component's template -- every control is a native <select>/<button>/
 * <textarea> -- so there is nothing to swap for a plain-DOM equivalent, and
 * the shadow root's innerHTML is complete, working markup as-is. The CSS has
 * no off-token colours and no `@import`, so it is read off disk unmodified
 * apart from the one substitution a shadow host gives the component for free
 * and a plain page does not: `:host` -> `.qa-host`.
 *
 * NAVIGATING BY THE STEP'S OWN TITLE, not by counting. The component derives
 * its step count from the resolved pack (steps.length varies with how many
 * supplements a pair has), so hard-coding "step 6 of 11" would silently drift
 * the moment a pair's supplement count changes. `.q-title` is the same text
 * the respondent reads, so branching on it can't drift from what's shown.
 *
 * Skipped unless QUESTIONNAIRE_PREVIEW_OUT is set, so a normal test run
 * writes nothing into the repo.
 */
const OUT = process.env.QUESTIONNAIRE_PREVIEW_OUT;
const maybe = OUT ? describe : describe.skip;

const FIXTURE = JSON.parse(
    fs.readFileSync(path.join(__dirname, 'data', 'questionnaire.json'), 'utf8')
);

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const q = (el, sel) => el.shadowRoot.querySelectorAll(sel);
const one = (el, sel) => el.shadowRoot.querySelector(sel);

function setSelect(el, field, value) {
    const node = one(el, `select[data-field="${field}"]`);
    if (!node) return;
    node.value = value;
    node.dispatchEvent(new CustomEvent('change'));
}

function fillContactField(el, field, value) {
    const node = one(el, `input[data-field="${field}"]`);
    if (!node) return;
    node.value = value;
    node.dispatchEvent(new CustomEvent('change'));
}

async function next(el) {
    one(el, '.q-btn--go').click();
    await flush();
    await flush();
}

/**
 * Answers every visible fieldset on the current step, whatever kind it is.
 * `branchLowKey`, when given, answers that one readiness slot with 2 instead
 * of 3 -- the value that makes SFMC -> MCN's slot 7 branch fire on the very
 * next screen. Every other bucket (complexity, supplements, bdContext) gets
 * placeholder content realistic enough to show the control filled in.
 */
function answerCurrentStep(el, branchLowKey) {
    q(el, 'fieldset').forEach((fieldset) => {
        const optBtn = fieldset.querySelector('.q-opt-btn[data-key]');
        if (optBtn) {
            const key = optBtn.dataset.key;
            const wanted = branchLowKey && key === branchLowKey ? 2 : 3;
            const btns = fieldset.querySelectorAll(
                `.q-opt-btn[data-value="${wanted}"]`
            );
            const btn = btns.length ? btns[0] : fieldset.querySelector('.q-opt-btn:not(:disabled)');
            if (btn && !btn.disabled) btn.click();
            return;
        }
        const textarea = fieldset.querySelector('textarea[data-key]');
        if (textarea) {
            textarea.value =
                'This is what a guest sees the field carrying through to the ' +
                'readout in their own words -- nothing here is scored.';
            textarea.dispatchEvent(new CustomEvent('change'));
            return;
        }
        const select = fieldset.querySelector('select[data-key]');
        if (select && select.options.length > 1) {
            select.value = select.options[1].value;
            select.dispatchEvent(new CustomEvent('change'));
            return;
        }
        const input = fieldset.querySelector('input[data-key]');
        if (input) {
            input.value = input.type === 'number' ? '250000' : 'A preview answer';
            input.dispatchEvent(new CustomEvent('change'));
        }
    });
}

/**
 * Mirrors live `.value` onto the DOM so it survives `innerHTML` serialization.
 *
 * `<input>`'s `value` IDL property does not reflect to a content attribute,
 * and `<textarea>`'s only ever serializes its ORIGINAL child text node, not
 * whatever `.value` was set to afterwards -- both confirmed directly against
 * jsdom, not assumed. LWC sets these as live properties on render/re-render,
 * so every dynamically-typed or dynamically-computed field (the resume URL,
 * a typed contact name, a BD-context textarea) would otherwise vanish from
 * this preview while working perfectly in the real component -- a preview
 * bug, not a product one, and a confusing one to spot from a screenshot
 * alone. Run right before reading `innerHTML`, on the live shadow root.
 */
function syncFormValues(root) {
    root.querySelectorAll('input').forEach((el) => {
        if (el.value) el.setAttribute('value', el.value);
    });
    root.querySelectorAll('textarea').forEach((el) => {
        el.textContent = el.value;
    });
}

/** The component's own CSS, with the one substitution a plain page needs. */
function componentCss() {
    const cssPath = path.join(__dirname, '..', 'gtmAssessmentQuestionnaire.css');
    return fs.readFileSync(cssPath, 'utf8').replace(/:host\b/g, '.qa-host');
}

/**
 * Walks one real pair end to end, capturing the shadow root's markup at
 * every screen a respondent actually sees -- before it is answered, which is
 * the state a real visit renders. Two extra frames earn their keep: routing
 * filled in (the "keeping your place" panel appears the moment a source is
 * picked, before anything else is answered) and contact filled in (by then a
 * real resume link exists, because a draft is pushed on every step
 * transition after routing).
 */
async function walkPair(label, opts) {
    window.localStorage.clear();
    const el = createElement('c-gtm-assessment-questionnaire', {
        is: GtmAssessmentQuestionnaire
    });
    el.savedRecordId = opts.savedRecordId;
    document.body.appendChild(el);
    await flush();
    await flush();

    const frames = [];
    const capture = (frameLabel) => {
        syncFormValues(el.shadowRoot);
        frames.push({ label: frameLabel, html: el.shadowRoot.innerHTML });
    };

    capture('About the move');
    setSelect(el, 'source', opts.source);
    setSelect(el, 'target', opts.target);
    setSelect(el, 'timeline', opts.timeline);
    setSelect(el, 'environmentSize', opts.environmentSize);
    await flush();
    capture('About the move — filled in');
    await next(el);

    let guard = 0;
    while (!one(el, '.q-done') && guard < 30) {
        const title = one(el, '.q-title') ? one(el, '.q-title').textContent : `Step ${guard + 1}`;
        capture(title);

        if (one(el, 'input[data-field="name"]')) {
            fillContactField(el, 'name', opts.name);
            fillContactField(el, 'email', opts.email);
            fillContactField(el, 'company', opts.company);
            fillContactField(el, 'role', opts.role);
            await flush();
            capture(`${title} — filled in`);
            await next(el);
        } else if (one(el, '.q-skip') && opts.skipBdContext) {
            one(el, '.q-skip').click();
            await flush();
            await flush();
        } else {
            answerCurrentStep(el, opts.branchLowKey);
            await flush();
            await next(el);
        }
        guard += 1;
    }
    capture('Assessment received');

    document.body.removeChild(el);
    return { label, frames };
}

maybe('assessment questionnaire preview page', () => {
    it('writes a standalone, walkable page of the rendered component', async () => {
        getPlatforms.mockResolvedValue(FIXTURE.platforms);
        getQuestionnaire.mockResolvedValue(FIXTURE.questionnaire);
        getPack.mockImplementation(({ sourceName, targetName }) => {
            if (sourceName === 'hubspot' && targetName === 'sfmc') {
                return Promise.resolve(FIXTURE.packHubToSfmc);
            }
            if (sourceName === 'sfmc' && targetName === 'sfmc_next') {
                return Promise.resolve(FIXTURE.packSfmcToMcn);
            }
            return Promise.resolve(null);
        });
        submitRequest.mockResolvedValue({ assessmentRequestId: 'PREVIEW-0001', contactId: null });
        saveDraft.mockImplementation(({ resumeToken }) =>
            Promise.resolve({
                resumeToken: resumeToken || 'PREVIEW-TOKEN',
                expiresAt: '2026-10-06T09:00:00.000Z',
                created: !resumeToken
            })
        );
        resumeDraft.mockResolvedValue(null);
        emailResumeLink.mockResolvedValue({ sent: true, message: 'Sent.' });

        const paths = await Promise.all([
            walkPair('HubSpot → Marketing Cloud Engagement', {
                savedRecordId: 'preview-hubspot-sfmc',
                source: 'hubspot',
                target: 'sfmc',
                timeline: 'Active — next 3 months',
                environmentSize: '2,000–10,000',
                name: 'Priya Anand',
                email: 'priya.anand@example.com',
                company: 'Northbeam Retail Group',
                role: 'VP Marketing Technology',
                skipBdContext: true
            }),
            walkPair('Marketing Cloud Engagement → Marketing Cloud Next', {
                savedRecordId: 'preview-sfmc-mcn',
                source: 'sfmc',
                target: 'sfmc_next',
                timeline: '3–6 months',
                environmentSize: '10,000+',
                name: 'Dana Cole',
                email: 'dana.cole@example.com',
                company: 'Solara Health Systems',
                role: 'Director, Marketing Operations',
                branchLowKey: 'integration_containment',
                skipBdContext: false
            })
        ]);

        const css = componentCss();

        const pathsJson = JSON.stringify(
            paths.map((p) => ({ label: p.label, frames: p.frames.map((f) => f.label) }))
        );
        const allFrames = paths.map((p) => p.frames.map((f) => f.html));

        const page = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Assessment questionnaire preview — rendered from c-gtm-assessment-questionnaire</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Lato:ital,wght@0,300;0,400;0,700;1,400&family=Roboto:wght@300;400;500;700&family=Roboto+Mono:wght@400;500;700&display=swap">
<style>
html, body { margin: 0; background: #ededed; }
${css}
.qa-shell { max-width: 56rem; margin: 0 auto; padding: 1.25rem 1.25rem 4rem; font-family: Lato, Roboto, sans-serif; }
.qa-shell h1 { font-size: 1.05rem; margin: 0 0 0.2rem; }
.qa-shell .qa-sub {
  margin: 0 0 1rem; font-size: 0.85rem; color: #555;
  font-family: 'Roboto Mono', ui-monospace, monospace;
}
.qa-tabs { display: flex; gap: 0.5rem; margin-bottom: 0.75rem; flex-wrap: wrap; }
.qa-tab {
  font: inherit; font-size: 0.85rem; font-weight: 700; cursor: pointer;
  padding: 0.5rem 0.9rem; border: 1px solid #101010; background: #fff; color: #101010;
}
.qa-tab[aria-selected="true"] { background: #101010; color: #fff; }
.qa-pager {
  display: flex; align-items: center; gap: 0.6rem; margin-bottom: 0.9rem;
  font-family: 'Roboto Mono', ui-monospace, monospace; font-size: 0.78rem;
}
.qa-pager button {
  font: inherit; font-weight: 700; cursor: pointer; padding: 0.4rem 0.8rem;
  border: 1px solid #101010; background: #fff; color: #101010;
}
.qa-pager button:disabled { opacity: 0.35; cursor: default; }
.qa-pager select { font: inherit; padding: 0.35rem 0.5rem; flex: 1; min-width: 0; }
.qa-frame-label {
  margin: 0 0 0.75rem; font-size: 0.8rem; color: #555;
  font-family: 'Roboto Mono', ui-monospace, monospace;
}
.qa-callout {
  border: 1px solid #101010; border-left: 3px solid #e4002b; background: #fff;
  padding: 0.75rem 0.9rem; margin: 0 0 1rem; font-size: 0.85rem; line-height: 1.5;
}
.qa-callout strong { color: #e4002b; }
.qa-stage { background: #fff; border: 1px solid #d4d4d4; }
.qa-frame { display: none; }
.qa-frame.qa-current { display: block; }
</style>
</head>
<body>
<div class="qa-shell">
  <h1>Assessment questionnaire — real prospect experience</h1>
  <p class="qa-sub">c-gtm-assessment-questionnaire, rendered verbatim — its own markup, its own CSS, walked through two real migration pairs.</p>
  <div class="qa-callout">
    <strong>Two real behaviours to look for:</strong> on the HubSpot → SFMC path, "What you are moving, and whether we can read it" shows a capped option (source access, value 4) rendered disabled with its reason rather than dropped. On the SFMC → Marketing Cloud Next path, slot 6 was answered low on purpose, so "Permission, and who decides" shows the branched consent question that fires only when the estate reaches outside the platform.
  </div>
  <div class="qa-tabs" role="tablist"></div>
  <div class="qa-pager">
    <button type="button" data-act="prev">← Prev</button>
    <select data-act="jump"></select>
    <button type="button" data-act="next">Next →</button>
  </div>
  <p class="qa-frame-label"></p>
  <div class="qa-stage">
    <div class="qa-host"></div>
  </div>
</div>
<script>
(function () {
  var PATHS = ${pathsJson};
  var FRAMES = ${JSON.stringify(allFrames)};
  var q = new URLSearchParams(location.search);
  var pathIndex = Math.min(Math.max(Number(q.get('path')) || 0, 0), PATHS.length - 1);
  var frameIndex = Math.max(Number(q.get('frame')) || 0, 0);

  var tabs = document.querySelector('.qa-tabs');
  var jump = document.querySelector('[data-act="jump"]');
  var label = document.querySelector('.qa-frame-label');
  var host = document.querySelector('.qa-host');
  var prevBtn = document.querySelector('[data-act="prev"]');
  var nextBtn = document.querySelector('[data-act="next"]');

  PATHS.forEach(function (p, i) {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'qa-tab';
    b.textContent = p.label;
    b.setAttribute('role', 'tab');
    b.addEventListener('click', function () { pathIndex = i; frameIndex = 0; render(); });
    tabs.appendChild(b);
  });

  function render() {
    var frames = PATHS[pathIndex].frames;
    frameIndex = Math.min(frameIndex, frames.length - 1);
    Array.prototype.forEach.call(tabs.children, function (b, i) {
      b.setAttribute('aria-selected', i === pathIndex ? 'true' : 'false');
    });
    jump.innerHTML = '';
    frames.forEach(function (f, i) {
      var o = document.createElement('option');
      o.value = i;
      o.textContent = (i + 1) + '. ' + f;
      jump.appendChild(o);
    });
    jump.value = frameIndex;
    label.textContent = 'Screen ' + (frameIndex + 1) + ' of ' + frames.length + ' — ' + frames[frameIndex];
    host.innerHTML = FRAMES[pathIndex][frameIndex];
    prevBtn.disabled = frameIndex === 0;
    nextBtn.disabled = frameIndex === frames.length - 1;
  }

  prevBtn.addEventListener('click', function () { if (frameIndex > 0) { frameIndex -= 1; render(); } });
  nextBtn.addEventListener('click', function () {
    if (frameIndex < PATHS[pathIndex].frames.length - 1) { frameIndex += 1; render(); }
  });
  jump.addEventListener('change', function () { frameIndex = Number(jump.value); render(); });

  render();
})();
</script>
</body></html>`;

        fs.mkdirSync(OUT, { recursive: true });
        fs.writeFileSync(path.join(OUT, 'assessment-questionnaire-preview.html'), page, 'utf8');
        expect(paths[0].frames.length).toBeGreaterThan(5);
        expect(paths[1].frames.length).toBeGreaterThan(5);
    });
});
