# UAT walkthrough — round 1: can a person manage this app?

For each step: do the action, tell me what you actually saw (a screenshot is best, a description is fine too). Mark it ✅ if it matched what's expected, ❌ with what happened instead if not. Don't fix anything yourself as you go — just report; I'll take it from there with the Architect.

## Part A — Content management (the part I never actually tested tonight)

**A1. Open the GTM Content Manager app → Content Manager tab.**
Expected: two-column grid of offering cards. One cell for "Framework," one for "Migration Accelerator."

**A2. Click into the Framework card.**
Expected: exactly two pages, no "add page" option (the code says these are fixed). Can you actually edit a section's text and save it? Does the save visibly stick (reload the page, is your edit still there)?

**A3. Click into the Migration Accelerator (offering) card.**
Expected: more pages than Framework, including per-industry sections (industry-profile: problem, use case, solution, unique points, proof, why-us, demo). Pick one industry, edit its "why us" copy, save. Does it stick?

**A4. Try to create a second Offering.**
Is there any button/path to do this at all? (My honest expectation: no — I found only one `GTM_Offering__mdt` record and no UI to add another. Tell me what you actually find, including if there's genuinely no way.)

**A5. Open the Instrument Author tab.**
Expected: a list of assessment questions with scores and branches, a preview that walks the branches. Try editing one question's label or a score value. Save. Does it stick? Is anything confusing, broken, or missing that you'd expect a real content author to need?

**A6. Try to find any way to set GUS's tone, personality, or instructions.**
My honest expectation: there is currently no way — GUS's behavior is hardcoded in Apex right now. I'm already having this built (see below). Confirm there's genuinely nothing today.

**A7. Try to find any way to configure the "customizer wizard" per offering — its steps, its defaults, anything.**
Same as A6 — tell me what you find, including if it's genuinely not there.

## Part B — The BD rep's actual day

**B1. GTM Offerings app → Overview tab. Click "New engagement link."**
This is the button I fixed and reported as working earlier tonight. **I need to know if it actually works** — does it take you to a working page, or an error/blank/wrong page? This is the single most important thing to check tonight, because I only ever verified the URL string it generates, never that the page loads.

**B2. If B1 worked: walk through creating a real engagement link** for a test client (use a name you'd recognize as your own test data, not a real prospect). Fill in whatever the wizard asks. Does every step make sense? Anything confusing, any dead ends, any field that doesn't do what its label says?

**B3. Copy the link it generates and open it in a private/incognito window** (so you're not logged in — this simulates what a real prospect sees).
Does the page load? Does it look right? If it's password-protected, does entering the password work?

**B4. On that same guest page, find and go through the assessment questionnaire.**
Does it feel like a real, usable form? Submit it with test answers.

**B5. Back in your normal (logged-in) window: GTM Offerings app → Readouts Overview tab.**
Does your test submission show up as a card? Click into it (Readouts Manager).

**B6. In the readout editor: try GUS.** Type a note, see what happens. Try "Send for approval."
Expected per how it's built: content locks, a banner names who it's pending with, the only action left is "Recall request" — there should be **no Approve button anywhere on this screen** (that's deliberate, per how it was built — approving happens through Salesforce's own approval notification, not here). Confirm that's actually what you see.

**B7. Find and act on the approval** (the Salesforce bell icon, an approval email, or Setup → your approvals) as if you were the approving manager. Approve it.
Back in Readouts Manager: does it now show Approved, with a Publish button?

**B8. Click Publish. Go back to the private/incognito window and check the same guest link.**
Does the recipient now see "View your assessment"? Does the published readout actually render and look right?

## Part C — General navigation sanity

**C1. Content Manager app → Home tab.** Is it actually there? (I fixed this earlier tonight — confirm it stuck.)

**C2. Any tab, any page — does anything look broken, unstyled, or throw an error banner** that I haven't already mentioned tonight? Even something small.

---

Work through this in whatever order makes sense to you — Part B first if you want to chase the "does the core money-path actually work" question fastest, Part A first if content-manageability is the bigger worry. Send me what you find as you go, doesn't need to be all at once. I'll bring the Architect in on anything that's a real gap, same process as tonight's doc work.
