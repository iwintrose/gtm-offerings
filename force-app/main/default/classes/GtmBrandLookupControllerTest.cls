@IsTest
private class GtmBrandLookupControllerTest {
    private class MockResponse implements HttpCalloutMock {
        Integer statusCode;
        String contentType;
        Blob body;

        MockResponse(Integer statusCode, String contentType, Blob body) {
            this.statusCode = statusCode;
            this.contentType = contentType;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            if (contentType != null) {
                res.setHeader('Content-Type', contentType);
            }
            if (body != null) {
                res.setBodyAsBlob(body);
            }
            return res;
        }
    }

    @IsTest
    static void returnsDataUriOnSuccessfulFirstSource() {
        Blob fakeImage = Blob.valueOf('fake-png-bytes');
        Test.setMock(HttpCalloutMock.class, new MockResponse(200, 'image/png', fakeImage));

        Test.startTest();
        String result = GtmBrandLookupController.fetchLogoDataUri('supernus.com');
        Test.stopTest();

        Assert.isNotNull(result);
        Assert.isTrue(result.startsWith('data:image/png;base64,'));
        Assert.isTrue(result.contains(EncodingUtil.base64Encode(fakeImage)));
    }

    @IsTest
    static void returnsNullWhenNoSourceReturnsAnImage() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(404, null, null));

        Test.startTest();
        String result = GtmBrandLookupController.fetchLogoDataUri('nonexistent-domain.example');
        Test.stopTest();

        Assert.isNull(result);
    }

    @IsTest
    static void rejectsBlankDomain() {
        Boolean threw = false;
        try {
            GtmBrandLookupController.fetchLogoDataUri('   ');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void treatsNonImageResponseAsNoLogo() {
        Test.setMock(
            HttpCalloutMock.class,
            new MockResponse(200, 'text/html', Blob.valueOf('<html>not an image</html>'))
        );

        Test.startTest();
        String result = GtmBrandLookupController.fetchLogoDataUri('example.com');
        Test.stopTest();

        Assert.isNull(result, 'A non-image response should not be treated as a logo');
    }
}
