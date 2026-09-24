@isTest
private class GtmMigrationPairsTest {

    private static GTM_Migration_Platform__mdt platform(String key, String label, String aliases) {
        return new GTM_Migration_Platform__mdt(
            Platform_Key__c = key, Display_Label__c = label,
            Aliases__c = aliases, Active__c = true
        );
    }

    private static GTM_Migration_Pair__mdt pair(String src, String tgt, Boolean supported, String reason) {
        return new GTM_Migration_Pair__mdt(
            Source_Key__c = src, Target_Key__c = tgt,
            Supported__c = supported, Unsupported_Reason__c = reason, Active__c = true
        );
    }

    /** The standard fixture: Eloqua and two Marketing Cloud flavours. */
    private static void seed() {
        GtmMigrationPairs.resetCache();
        GtmMigrationPairs.platformOverride = new List<GTM_Migration_Platform__mdt>{
            platform('eloqua', 'Oracle Eloqua', 'Eloqua;Oracle Marketing Cloud'),
            platform('sfmc', 'Marketing Cloud Engagement', 'SFMC;MCE;ExactTarget'),
            platform('sfmc_next', 'Marketing Cloud Next', 'SFMC Next;MCN;Marketing Cloud Next'),
            platform('mcae', 'Account Engagement', 'MCAE;Pardot')
        };
        GtmMigrationPairs.pairOverride = new List<GTM_Migration_Pair__mdt>{
            pair('eloqua', 'sfmc_next', true, null),
            pair('mcae', 'sfmc_next', false, 'Account Engagement is not an extractable source yet.'),
            pair('sfmc', 'eloqua', false, null)
        };
    }

    // ------------------------------------------------------------ resolution

    @isTest
    static void freeTextPlatformNamesResolveThroughAliases() {
        seed();
        // Case, spacing and punctuation are all noise -- these fields are a
        // human typing a product name into a box.
        for (String spelling : new List<String>{
            'MCE', 'mce', 'ExactTarget', 'exact target', 'Marketing-Cloud Engagement', 'sfmc'
        }) {
            Assert.areEqual('sfmc', GtmMigrationPairs.resolvePlatformKey(spelling),
                'Failed to resolve: ' + spelling);
        }
        Assert.areEqual('sfmc_next', GtmMigrationPairs.resolvePlatformKey('  marketing cloud next  '));
    }

    @isTest
    static void aCanonicalKeyResolvesWithoutBeingListedAsItsOwnAlias() {
        GtmMigrationPairs.resetCache();
        GtmMigrationPairs.platformOverride = new List<GTM_Migration_Platform__mdt>{
            platform('eloqua', 'Oracle Eloqua', null)
        };
        Assert.areEqual('eloqua', GtmMigrationPairs.resolvePlatformKey('Eloqua'));
    }

    @isTest
    static void anUnknownNameResolvesToNothing() {
        seed();
        Assert.isNull(GtmMigrationPairs.resolvePlatformKey('Adobe Campaign'));
        Assert.isNull(GtmMigrationPairs.resolvePlatformKey(null));
        Assert.isNull(GtmMigrationPairs.resolvePlatformKey('   '));
    }

    @isTest
    static void labelForFallsBackToWhatWasTyped() {
        seed();
        Assert.areEqual('Marketing Cloud Engagement', GtmMigrationPairs.labelFor('MCE'));
        // A rep should see the words the prospect actually used, not a blank.
        Assert.areEqual('Adobe Campaign', GtmMigrationPairs.labelFor('Adobe Campaign'));
    }

    @isTest
    static void anInactivePlatformIsIgnored() {
        GtmMigrationPairs.resetCache();
        GTM_Migration_Platform__mdt retired = platform('eloqua', 'Oracle Eloqua', 'Eloqua');
        retired.Active__c = false;
        GtmMigrationPairs.platformOverride = new List<GTM_Migration_Platform__mdt>{ retired };
        Assert.isNull(GtmMigrationPairs.resolvePlatformKey('Eloqua'));
    }

    // ---------------------------------------------------------- the verdicts

    @isTest
    static void aSupportedPairIsEvaluatedAndSupported() {
        seed();
        GtmAssessmentScoring.PairEligibility verdict =
            GtmMigrationPairs.evaluate('Oracle Marketing Cloud', 'MCN');
        Assert.isTrue(verdict.evaluated);
        Assert.isTrue(verdict.supported);
        Assert.isNull(verdict.reason);
    }

    @isTest
    static void anUnsupportedPairCarriesItsConfiguredReason() {
        seed();
        GtmAssessmentScoring.PairEligibility verdict = GtmMigrationPairs.evaluate('Pardot', 'SFMC Next');
        Assert.isTrue(verdict.evaluated);
        Assert.isFalse(verdict.supported);
        Assert.areEqual('Account Engagement is not an extractable source yet.', verdict.reason);
    }

    @isTest
    static void anUnsupportedPairWithNoConfiguredReasonStillGetsSensibleWords() {
        seed();
        GtmAssessmentScoring.PairEligibility verdict = GtmMigrationPairs.evaluate('MCE', 'Eloqua');
        Assert.isFalse(verdict.supported);
        Assert.isTrue(verdict.reason.contains('Marketing Cloud Engagement'),
            'The generated reason names the platforms, using their display labels');
        Assert.isTrue(verdict.reason.contains('Oracle Eloqua'));
    }

    @isTest
    static void directionMatters() {
        // eloqua -> sfmc_next is supported; the reverse is not even listed, and
        // an unlisted pair must not inherit the supported one's verdict.
        seed();
        Assert.isTrue(GtmMigrationPairs.evaluate('Eloqua', 'MCN').supported);
        Assert.isFalse(GtmMigrationPairs.evaluate('MCN', 'Eloqua').evaluated,
            'The reverse direction is unlisted, not supported');
    }

    // ------------------------------------------------------------- fail-open

    @isTest
    static void anUnlistedPairLeavesTheGateInert() {
        seed();
        GtmAssessmentScoring.PairEligibility verdict = GtmMigrationPairs.evaluate('Eloqua', 'MCE');
        Assert.isFalse(verdict.evaluated, 'Unlisted is not the same as unsupported');
        Assert.isTrue(verdict.supported, 'The default must not suppress anything');
    }

    @isTest
    static void anUnrecognisedPlatformNameLeavesTheGateInert() {
        // A prospect typing a platform nobody added an alias for is a config
        // gap. Suppressing their tier for it would punish them for our data.
        seed();
        Assert.isFalse(GtmMigrationPairs.evaluate('Adobe Campaign', 'MCN').evaluated);
        Assert.isFalse(GtmMigrationPairs.evaluate('Eloqua', null).evaluated);
        Assert.isFalse(GtmMigrationPairs.evaluate(null, null).evaluated);
    }

    @isTest
    static void noPairMetadataAtAllLeavesTheGateInert() {
        // The state the org is in before the adaptive layer populates the
        // table. An empty config table is a deployment state, not a product
        // judgement, so nothing may be suppressed because of it.
        GtmMigrationPairs.resetCache();
        GtmMigrationPairs.platformOverride = new List<GTM_Migration_Platform__mdt>{
            platform('eloqua', 'Oracle Eloqua', 'Eloqua'),
            platform('sfmc_next', 'Marketing Cloud Next', 'MCN')
        };
        GtmMigrationPairs.pairOverride = new List<GTM_Migration_Pair__mdt>();

        GtmAssessmentScoring.PairEligibility verdict = GtmMigrationPairs.evaluate('Eloqua', 'MCN');
        Assert.isFalse(verdict.evaluated);
        Assert.isTrue(verdict.supported);
    }

    @isTest
    static void anInactivePairRowIsTreatedAsUnlisted() {
        GtmMigrationPairs.resetCache();
        GtmMigrationPairs.platformOverride = new List<GTM_Migration_Platform__mdt>{
            platform('mcae', 'Account Engagement', 'Pardot'),
            platform('sfmc_next', 'Marketing Cloud Next', 'MCN')
        };
        GTM_Migration_Pair__mdt retired = pair('mcae', 'sfmc_next', false, 'No.');
        retired.Active__c = false;
        GtmMigrationPairs.pairOverride = new List<GTM_Migration_Pair__mdt>{ retired };

        Assert.isFalse(GtmMigrationPairs.evaluate('Pardot', 'MCN').evaluated);
    }

    // ------------------------------------------------- end-to-end with scoring

    @isTest
    static void anUnsupportedPairFlowsThroughToASuppressedTier() {
        // The two halves of the gate meet here: GtmMigrationPairs owns the list,
        // GtmAssessmentScoring owns the rule.
        seed();
        Map<String, Integer> perfect = new Map<String, Integer>();
        for (String dimension : GtmAssessmentScoring.DIMENSIONS) {
            perfect.put(dimension, 4);
        }

        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', 
            perfect, GtmMigrationPairs.evaluate('Pardot', 'MCN')
        );

        Assert.areEqual(32, scored.total);
        Assert.isNull(scored.tier, 'A 32/32 pair we cannot process still gets no tier');
        Assert.isTrue(scored.advisory);
        Assert.areEqual('Account Engagement is not an extractable source yet.', scored.advisoryReason);
    }

    // ------------------------------------------------- wizard platform list

    @isTest
    static void listPlatformsReturnsActiveKeyAndLabelOrderedByLabel() {
        GtmMigrationPairs.resetCache();
        GTM_Migration_Platform__mdt retired = platform('old', 'Zeta Retired', null);
        retired.Active__c = false;
        GtmMigrationPairs.platformOverride = new List<GTM_Migration_Platform__mdt>{
            platform('sfmc', 'Marketing Cloud Engagement', 'SFMC'),
            platform('eloqua', 'oracle Eloqua', null),
            retired,
            platform('', 'No Key', null),
            platform('mcae', 'Account Engagement', null)
        };
        List<GtmMigrationPairs.PlatformOption> options = GtmMigrationPairs.listPlatforms();
        Assert.areEqual(3, options.size(), 'inactive and blank-key rows are skipped');
        Assert.areEqual('mcae', options[0].key);
        Assert.areEqual('Account Engagement', options[0].label);
        Assert.areEqual('sfmc', options[1].key, 'ordered case-insensitively by label');
        Assert.areEqual('Marketing Cloud Engagement', options[1].label, 'ordered case-insensitively by label');
        Assert.areEqual('eloqua', options[2].key, 'lowercase-initial label sorts case-insensitively, last');
        Assert.areEqual('oracle Eloqua', options[2].label, 'lowercase-initial label sorts case-insensitively, last');
    }

    @isTest
    static void listPlatformsFallsBackToKeyWhenLabelBlankAndIsEmptyWhenNone() {
        GtmMigrationPairs.resetCache();
        GtmMigrationPairs.platformOverride = new List<GTM_Migration_Platform__mdt>{
            platform('hubspot', null, null)
        };
        List<GtmMigrationPairs.PlatformOption> options = GtmMigrationPairs.listPlatforms();
        Assert.areEqual(1, options.size());
        Assert.areEqual('hubspot', options[0].label);

        GtmMigrationPairs.platformOverride = new List<GTM_Migration_Platform__mdt>();
        Assert.isTrue(GtmMigrationPairs.listPlatforms().isEmpty());
    }

    @isTest
    static void resolveDefaultLabelMapsAliasesToTheDisplayLabel() {
        seed();
        Assert.areEqual('Marketing Cloud Engagement', GtmMigrationPairs.resolveDefaultLabel('MCE'));
        Assert.areEqual('Oracle Eloqua', GtmMigrationPairs.resolveDefaultLabel('eloqua'));
        Assert.isNull(GtmMigrationPairs.resolveDefaultLabel('Some Unlisted CRM'));
        Assert.isNull(GtmMigrationPairs.resolveDefaultLabel(null));
        Assert.isNull(GtmMigrationPairs.resolveDefaultLabel('  '));
    }
}
