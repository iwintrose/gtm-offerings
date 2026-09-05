/**
 * Creating an offering has to work the moment it is asked for. Offerings live
 * in custom metadata, which only deploys asynchronously, so an offering that
 * existed only as metadata would vanish from its own app until the deployment
 * landed. Its pages are ordinary records, and they are what make it real.
 */
@isTest
private class GtmOfferingCreationTest {

    @isTest
    static void aNewOfferingExistsImmediately() {
        Test.startTest();
        String key = GtmPageContentController.createOffering('Data Cloud Accelerator');
        Test.stopTest();

        System.assertEquals('data-cloud-accelerator', key, 'the key comes from the name');

        Map<String, String> byField = new Map<String, String>();
        for (MA_Page_Content__c c : [
            SELECT Field_Key__c, Text_Value__c, Rich_Value__c
            FROM MA_Page_Content__c WHERE Offering_Key__c = :key
        ]) {
            byField.put(c.Field_Key__c,
                c.Text_Value__c != null ? c.Text_Value__c : c.Rich_Value__c);
        }
        System.assertEquals('Data Cloud Accelerator', byField.get('name'));
        System.assertEquals('DC', byField.get('mark'), 'initials, so the tile has a badge');
        System.assertNotEquals(null, byField.get('description'));

        Boolean onHome = false;
        for (GtmPageContentController.OfferingSummary o : GtmPageContentController.getHomeSummary().offerings) {
            if (o.offeringKey == key) onHome = true;
        }
        System.assert(onHome, 'it must appear without waiting for a metadata deployment');
    }

    @isTest
    static void aNameThatIsAlreadyTakenIsRefused() {
        GtmPageContentController.createOffering('Twice Over');
        Boolean refused = false;
        Test.startTest();
        try { GtmPageContentController.createOffering('Twice Over'); }
        catch (Exception e) { refused = true; }
        Test.stopTest();
        System.assert(refused, 'a second offering must not quietly share the first one\'s pages');
    }

    @isTest
    static void aNameWithNothingInItIsRefused() {
        Integer refusals = 0;
        Test.startTest();
        try { GtmPageContentController.createOffering('   '); } catch (Exception e) { refusals++; }
        try { GtmPageContentController.createOffering('!!!'); } catch (Exception e) { refusals++; }
        try { GtmPageContentController.createOffering('gtm');  } catch (Exception e) { refusals++; }
        Test.stopTest();
        System.assertEquals(3, refusals,
            'blank, punctuation-only, and the reserved framework key are all refused');
    }
}
