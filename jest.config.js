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
    // `c/gtmBrandTokens` is a CSS-only LWC module (a folder holding just a
    // .css). The real compiler resolves `@import 'c/gtmBrandTokens'` to that
    // stylesheet, but sfdx-lwc-jest's resolver only looks for <name>.js and
    // fails the whole suite with "Cannot find module". Adding a .js is NOT the
    // fix — the resolver then hands the engine a module instead of a
    // stylesheet and it dies on `$scoped$`. Point the specifier straight at
    // the CSS so jest applies its own stylesheet transform to it.
    moduleNameMapper: {
        ...(jestConfig.moduleNameMapper || {}),
        '^c/gtmBrandTokens$':
            '<rootDir>/force-app/main/default/lwc/gtmBrandTokens/gtmBrandTokens.css'
    }
};
