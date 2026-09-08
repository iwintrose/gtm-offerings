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
    testPathIgnorePatterns: ['/node_modules/', '/\\.claude/']
};
