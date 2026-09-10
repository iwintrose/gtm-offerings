/**
 * GtmReadoutAgentEdit is pure computation, so this is where the load-bearing
 * rules get proved: that a section edit leaves the scores alone, that the
 * heading match is the forgiving one the model will actually produce, and that
 * nothing executable survives sanitising.
 *
 * NOT RUN. There is no Salesforce CLI or scratch org in the environment this
 * was written in, so no Apex in this change has been compiled or executed.
 * Treat every assertion here as unverified until it runs against an org.
 */
@isTest
private class GtmReadoutAgentEditTest {

    /** A draft shaped like the real one: scores in the body, sections below. */
    private static final String DRAFT =
        '<h2>Migration Assessment Readout — Northwind</h2>\n' +
        '<p><strong>Migration readiness:</strong> 18 out of 32</p>\n' +
        '<h3>What we found</h3>\n' +
        '<p>Original finding.</p>\n' +
        '<h3>Pain points</h3>\n' +
        '<p>Manual list hygiene.</p>';

    @isTest
    static void replaceSectionRewritesOnlyThatSection() {
        GtmReadoutAgentEdit.Result r = GtmReadoutAgentEdit.apply(
            DRAFT, 'replace_section', 'What we found', '<p>New finding.</p>'
        );

        System.assertEquals(true, r.success, r.message);
        System.assert(r.content.contains('<p>New finding.</p>'), 'the new body should be present');
        System.assert(!r.content.contains('Original finding'), 'the old body should be gone');
        // The whole point: the numbers are in the same document and must not move.
        System.assert(r.content.contains('18 out of 32'), 'the score line must survive a section edit');
        System.assert(r.content.contains('Manual list hygiene.'), 'a later section must survive');
        System.assert(r.content.contains('<h3>Pain points</h3>'), 'later headings must survive');
    }

    @isTest
    static void replaceSectionMatchesHeadingCaseAndWhitespaceInsensitively() {
        // The model repeats a heading back from a tool result; it will not
        // reproduce whitespace byte for byte.
        GtmReadoutAgentEdit.Result r = GtmReadoutAgentEdit.apply(
            DRAFT, 'replace_section', '  what WE found ', '<p>Matched.</p>'
        );
        System.assertEquals(true, r.success, r.message);
        System.assert(r.content.contains('Matched.'));
    }

    @isTest
    static void replaceSectionOnAnH2TakesItsChildrenWithIt() {
        GtmReadoutAgentEdit.Result r = GtmReadoutAgentEdit.apply(
            DRAFT, 'replace_section', 'Migration Assessment Readout — Northwind', '<p>All of it.</p>'
        );
        System.assertEquals(true, r.success, r.message);
        System.assert(!r.content.contains('Pain points'),
            'replacing the h2 section should consume its h3 children');
    }

    @isTest
    static void replaceSectionRefusesAnUnknownHeading() {
        GtmReadoutAgentEdit.Result r = GtmReadoutAgentEdit.apply(
            DRAFT, 'replace_section', 'Recommendations', '<p>x</p>'
        );
        System.assertEquals(false, r.success);
        System.assert(r.message.contains('append_section'),
            'the refusal should name the mode that would work');
    }

    @isTest
    static void appendSectionAddsAHeadingAndKeepsEverythingElse() {
        GtmReadoutAgentEdit.Result r = GtmReadoutAgentEdit.apply(
            DRAFT, 'append_section', 'Recommendations', '<p>Start with consent.</p>'
        );
        System.assertEquals(true, r.success, r.message);
        System.assert(r.content.contains('<h3>Recommendations</h3>'));
        System.assert(r.content.contains('18 out of 32'), 'appending must not disturb the scores');
    }

    @isTest
    static void appendSectionEscapesTheHeadingText() {
        GtmReadoutAgentEdit.Result r = GtmReadoutAgentEdit.apply(
            DRAFT, 'append_section', '<img src=x onerror=alert(1)>', '<p>x</p>'
        );
        System.assertEquals(true, r.success, r.message);
        System.assert(!r.content.contains('<img'), 'a heading is text, never markup');
    }

    @isTest
    static void replaceAllReplacesEverything() {
        GtmReadoutAgentEdit.Result r = GtmReadoutAgentEdit.apply(
            DRAFT, 'replace_all', null, '<p>Whole new readout.</p>'
        );
        System.assertEquals(true, r.success, r.message);
        System.assertEquals('<p>Whole new readout.</p>', r.content);
    }

    @isTest
    static void unknownModeIsRefused() {
        GtmReadoutAgentEdit.Result r = GtmReadoutAgentEdit.apply(DRAFT, 'delete_everything', 'x', '<p>x</p>');
        System.assertEquals(false, r.success);
    }

    @isTest
    static void blankHtmlIsRefused() {
        GtmReadoutAgentEdit.Result r = GtmReadoutAgentEdit.apply(DRAFT, 'replace_all', null, '   ');
        System.assertEquals(false, r.success);
    }

    @isTest
    static void sectionModesRequireAHeading() {
        System.assertEquals(false,
            GtmReadoutAgentEdit.apply(DRAFT, 'replace_section', null, '<p>x</p>').success);
        System.assertEquals(false,
            GtmReadoutAgentEdit.apply(DRAFT, 'append_section', '', '<p>x</p>').success);
    }

    @isTest
    static void contentOverTheFieldLimitIsRefusedRatherThanTruncated() {
        String huge = 'x'.repeat(GtmReadoutAgentEdit.MAX_CONTENT_CHARS + 100);
        GtmReadoutAgentEdit.Result r = GtmReadoutAgentEdit.apply(DRAFT, 'replace_all', null, huge);
        System.assertEquals(false, r.success);
        System.assert(r.message.contains('characters'));
    }

    // ------------------------------------------------------------- sanitising

    @isTest
    static void sanitizeStripsScriptsAndTheirContent() {
        String out = GtmReadoutAgentEdit.sanitize('<p>ok</p><script>steal()</script>');
        System.assert(!out.containsIgnoreCase('script'));
        System.assert(!out.contains('steal()'), 'the script body must go with the tag');
        System.assert(out.contains('<p>ok</p>'));
    }

    @isTest
    static void sanitizeStripsInlineEventHandlersQuotedAndBare() {
        System.assert(!GtmReadoutAgentEdit.sanitize('<p onclick="x()">a</p>').containsIgnoreCase('onclick'));
        System.assert(!GtmReadoutAgentEdit.sanitize('<p onclick=\'x()\'>a</p>').containsIgnoreCase('onclick'));
        System.assert(!GtmReadoutAgentEdit.sanitize('<p onclick=x()>a</p>').containsIgnoreCase('onclick'));
    }

    @isTest
    static void sanitizeStripsScriptBearingUrlSchemes() {
        System.assert(!GtmReadoutAgentEdit.sanitize('<a href="javascript:x()">a</a>')
            .containsIgnoreCase('javascript:'));
        System.assert(!GtmReadoutAgentEdit.sanitize('<img src=data:text/html;base64,AAA>')
            .containsIgnoreCase('data:'));
    }

    @isTest
    static void sanitizeStripsFramesFormsAndStyles() {
        String out = GtmReadoutAgentEdit.sanitize(
            '<iframe src="//evil"></iframe><form action="//evil"><input></form><style>p{}</style><p>keep</p>'
        );
        System.assert(!out.containsIgnoreCase('iframe'));
        System.assert(!out.containsIgnoreCase('<form'));
        System.assert(!out.containsIgnoreCase('<input'));
        System.assert(!out.containsIgnoreCase('<style'));
        System.assert(out.contains('<p>keep</p>'));
    }

    @isTest
    static void anEditThatIsNothingButUnsafeMarkupIsRefused() {
        GtmReadoutAgentEdit.Result r =
            GtmReadoutAgentEdit.apply(DRAFT, 'replace_all', null, '<script>x()</script>');
        System.assertEquals(false, r.success);
    }

    // ---------------------------------------------------------------- headings

    @isTest
    static void headingsListsEveryHeadingInOrder() {
        List<String> h = GtmReadoutAgentEdit.headings(DRAFT);
        System.assertEquals(3, h.size());
        System.assertEquals('Migration Assessment Readout — Northwind', h[0]);
        System.assertEquals('What we found', h[1]);
        System.assertEquals('Pain points', h[2]);
    }

    @isTest
    static void headingsOnBlankContentIsEmptyNotNull() {
        System.assertEquals(0, GtmReadoutAgentEdit.headings(null).size());
        System.assertEquals(0, GtmReadoutAgentEdit.headings('').size());
    }

    @isTest
    static void appendSectionWorksOnAnEmptyDraft() {
        GtmReadoutAgentEdit.Result r =
            GtmReadoutAgentEdit.apply('', 'append_section', 'What we found', '<p>x</p>');
        System.assertEquals(true, r.success, r.message);
        System.assert(r.content.startsWith('<h3>What we found</h3>'));
    }
}
