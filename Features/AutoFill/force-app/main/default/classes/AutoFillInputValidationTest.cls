@IsTest
private class AutoFillInputValidationTest {
    private static String expectedEmailContent;

    private class FailureResponseMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('POST', request.getMethod());
            System.assert(
                request.getEndpoint().contains(
                    '/api/EmailExtractor/process-email-with-files'
                )
            );
            System.assertNotEquals(null, request.getBodyAsBlob());

            String requestBody = request.getBodyAsBlob().toString();
            System.assert(
                requestBody.contains(
                    'name="EmailContent"\r\n\r\n' +
                    expectedEmailContent +
                    '\r\n'
                ),
                'The expected EmailContent value was not sent.'
            );

            HttpResponse response = new HttpResponse();
            response.setStatusCode(400);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"Success":false,"Message":"Mock response"}');
            return response;
        }
    }

    private static void configureCalloutMock(String expectedValue) {
        expectedEmailContent = expectedValue;
        AutoFillController.testAccessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new FailureResponseMock());
    }

    @IsTest
    static void notesOnlyPassesInputValidation() {
        configureCalloutMock('Notes-only submission');

        Test.startTest();
        AutoFillController.ApiResult result =
            AutoFillController.sendEmailContent(
                'Notes-only submission',
                new List<AutoFillController.UploadFile>()
            );
        Test.stopTest();

        System.assertEquals(400, result.statusCode);
        System.assertEquals(false, result.success);
    }

    @IsTest
    static void attachmentOnlyPassesInputValidation() {
        configureCalloutMock('text');

        AutoFillController.UploadFile file =
            new AutoFillController.UploadFile();
        file.fileName = 'document.pdf';
        file.contentType = 'application/pdf';
        file.base64Data = EncodingUtil.base64Encode(
            Blob.valueOf('PDF test bytes')
        );

        Test.startTest();
        AutoFillController.ApiResult result =
            AutoFillController.sendEmailContent(
                '',
                new List<AutoFillController.UploadFile>{ file }
            );
        Test.stopTest();

        System.assertEquals(400, result.statusCode);
        System.assertEquals(false, result.success);
    }

    @IsTest
    static void bothEmptyAreRejectedBeforeCallout() {
        Boolean wasRejected = false;

        try {
            AutoFillController.sendEmailContent(
                '   ',
                new List<AutoFillController.UploadFile>()
            );
        } catch (AuraHandledException expectedException) {
            wasRejected = true;
        }

        System.assertEquals(
            true,
            wasRejected,
            'Both empty inputs must be rejected.'
        );
    }
}