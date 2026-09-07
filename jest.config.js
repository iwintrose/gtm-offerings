const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    // sfdx-lwc-jest treats every file under __tests__ as a test, which makes
    // it impossible to keep a shared fixture beside the tests that use it —
    // the fixture is collected as a suite and fails for containing no tests.
    // Narrowing the match to *.test.js is what lets __tests__/data/ exist.
    testMatch: ['**/__tests__/**/*.test.js']
};
