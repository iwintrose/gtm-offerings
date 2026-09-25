# TASK SCOPE — ISSUE #8

## 1. Requirements Breakdown

- **Target Objective:** Issue #8 asks to "extract shared c-gtm-page-header LWC" and migrate `gtmOverview` and `gtmContentHome` off their hand-rolled, independently-duplicated header markup (`ov-*` vs `home-*` class prefixes) onto that shared component, per the DRAFT plan in `docs/agent-artifacts/header-bar-consistency-assessment.md`.

  **This work is already done on `main`.** Verification performed against the actual current code (not the stale draft):

  - `force-app/main/default/lwc/gtmPageHeader/` exists today with `gtmPageHeader.html`, `.js`, `.css`, `.js-meta.xml`, and a Jest spec (`__tests__/gtmPageHeader.test.js`). Its template implements exactly the icon/eyebrow/title/meta/actions contract the draft proposed:
    ```
    <div class={hdrClass}>
      <div class="slds-page-header__row">
        <div class="slds-page-header__col-title">
          <lightning-icon icon-name={iconName} ... class="hdr-icon"></lightning-icon>
          <div class="slds-media__body">
            <p class="slds-page-header__name-title hdr-eyebrow">{eyebrow}</p>
            <h1 class="hdr-title">{title}</h1>
            <p class="slds-page-header__name-meta hdr-meta">{meta}</p>
          </div>
        </div>
        <div class="slds-page-header__col-actions">
          <slot name="actions"></slot>
          ...lightning-button-menu / lightning-button for declarative `actions` prop...
        </div>
      </div>
    </div>
    ```
  - `force-app/main/default/lwc/gtmOverview/gtmOverview.html` (lines 44-50) already renders:
    ```html
    <c-gtm-page-header icon-name="standard:opportunity" eyebrow="Go to market"
                      title="GTM Offerings" meta={headerMeta}
                      actions={headerActions} onheaderaction={handleHeaderAction}>
    </c-gtm-page-header>
    ```
    with an inline code comment: `"Same shape as the Content Manager home, because they are siblings — both now built on the shared c-gtm-page-header (issue B14)."`
  - `force-app/main/default/lwc/gtmContentHome/gtmContentHome.html` (lines 4-8) already renders the equivalent `<c-gtm-page-header icon-name="standard:article" eyebrow="Content" title="GTM Content Manager" ...>`, with a matching comment referencing the same "issue B14" work.
  - `grep -n "ov-hero\|ov-eyebrow\|home-hero\|home-eyebrow" gtmOverview.css gtmContentHome.css` returns **no matches** — the old duplicated hand-rolled header CSS classes the draft described are gone from both files.
  - `git log --oneline --all` shows the extraction commit directly: `861f020 refactor(lwc): extract shared c-gtm-page-header, migrate gtmOverview + gtmContentHome (issue-B14a)`, followed by a long chain of hardening/iteration commits already merged to `main`: `768bbba` (reserve row min-height), `fb27785` / `b2ca7cc` (icon-shift fixes), `10b7722` / `d384c3b` (layout fix, wrap actions / floor title), `a0c1ef2` / `d993607` / `f196696` (declarative `actions` prop + hamburger menu), `22e4171` (responsive CSS at breakpoints).
  - `c-gtm-page-header` is additionally already consumed well beyond the two pages this issue named — `grep -rl "gtmPageHeader\|c-gtm-page-header" force-app/main/default/lwc/` shows it wired into `gtmPageBrowser`, `gtmAnalytics`, `gtmAssessmentSubmissionView`, `gtmReadoutApprovalSettings`, `gtmContentManager`, `gtmInstrumentAuthor`, `gtmReadoutsOverview`, `gtmOfferingsSettings`, `gtmRecycleBin`, and `gtmContentManagerSettings` — i.e. the broader "extend to new pages" follow-on from the draft's sequencing step 2 has also already shipped, in addition to the core ask.

  **Conclusion / ambiguity to flag for a human:** there is nothing left to build for the literal ask in issue #8. The most likely correct actions are (a) close issue #8 as already-resolved by the `issue-B14a` chain, or (b) re-scope it narrowly if the actual outstanding want is something more specific (e.g. a residual visual nit, a missed page, or a regression) — but that would require the issue author to say what's still wrong, since the described objective (extract + migrate the two exact matches) is verifiably complete in the current tree. I am not guessing at a replacement scope; this determination should go back to a human/the Architect step rather than being treated as settled by an agent.

- **System Component Impacted:** LWC (`force-app/main/default/lwc/gtmPageHeader/`, `gtmOverview/`, `gtmContentHome/`) — already-shipped, no further changes scoped by this doc.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? — N/A, no code change is being scoped here.
- [ ] Altering Custom Metadata? — N/A.
- [ ] Introducing database fields? — N/A.

(No Salesforce-native-component substitution question applies either: this is a pure LWC composition problem — internal Lightning app page headers built from `lightning-icon` + `lightning-button`/`lightning-button-menu` primitives inside a custom container, which is already how `c-gtm-page-header` itself is implemented. There is no single base/native Lightning component that renders this icon+eyebrow+title+meta+actions card shape as one drop-in; the existing `c-gtm-page-header` wrapper around `lightning-icon`/`lightning-button` is the appropriate level of "native-first," which is why the prior implementation chose it. No further build is needed.)

## 3. Plan Acceptance Criteria

- **Success Metric:** No build/deploy action is warranted from this scope doc. The Architect/Developer/QA chain should not open a worktree for issue #8 as currently written; instead the coordinator should confirm with the issue author/owner whether to close #8 as already-resolved (citing commit `861f020` and the chain above) or restate what remains outstanding so it can be re-scoped as a new, narrower issue.
- **Target Test Target:** `force-app/main/default/lwc/gtmPageHeader/__tests__/gtmPageHeader.test.js`, `force-app/main/default/lwc/gtmOverview/__tests__/gtmOverview.test.js`, `force-app/main/default/lwc/gtmContentHome/__tests__/gtmContentHome.test.js` — these already exist and cover the shipped component/migration; no new test target is scoped.
