const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    // sfdx-lwc-jest treats every file under __tests__ as a test, which makes
    // it impossible to keep a shared fixture beside the tests that use it —
    // the fixture is collected as a suite and fails for containing no tests.
    // Narrowing the match to *.test.js is what lets __tests__/data/ exist.
    testMatch: ['**/__tests__/**/*.test.js'],
    // `.claude/worktrees/` is a gitignored scratch area where agent sessions
    // check out their own copies of this repo. Without this, `npm test`
    // collects and runs every suite in every abandoned worktree as well as the
    // real source tree -- so a stale checkout's failures are reported as
    // failures of HEAD, and `npm test` stops being usable as a gate. Only
    // force-app/ is the source of truth.
    testPathIgnorePatterns: ['/node_modules/', '/\\.claude/'],
    // NOTE for anyone who finds gtmStory.css's "used to live in c/gtmBrandTokens,
    // a CSS-only bundle" comment and goes looking for a matching entry here:
    // there used to be one, mapping `c/gtmBrandTokens` straight at a .css file
    // because sfdx-lwc-jest's resolver only looks for <name>.js and that bundle
    // had no .js. That CSS-only bundle was deleted in issue #33 (orphaned,
    // undeployable — no .js/.js-meta.xml) and the mapper entry was accidentally
    // left behind pointing at the now-deleted file, silently dead since nothing
    // imported `c/gtmBrandTokens` again until issue-ps-brand-overhaul-2 rebuilt
    // it as a real bundle (.js + .js-meta.xml, no .html/.css) -- at which point
    // this stale entry started shadowing it and resolving every import to
    // `undefined`. Removed; a normal .js bundle needs no special-case mapper.
    moduleNameMapper: {
        ...(jestConfig.moduleNameMapper || {}),
        // sfdx-lwc-jest ships stubs for lightning/modalHeader, modalBody and
        // modalFooter (a modal's own sub-components) but not for
        // lightning/modal itself -- the base class a modal component
        // extends. See force-app/test/jest-mocks/lightningModal.js.
        '^lightning/modal$':
            '<rootDir>/force-app/test/jest-mocks/lightningModal.js'
    }
};
