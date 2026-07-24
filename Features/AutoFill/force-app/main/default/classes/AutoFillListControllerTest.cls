@IsTest
private class AutoFillListControllerTest {

    private class ApiMock implements HttpCalloutMock {
        private Integer statusCode;

        ApiMock(Integer statusCode) {
            this.statusCode = statusCode;
        }

        public HttpResponse respond(HttpRequest request) {
            String endpoint = String.valueOf(request.getEndpoint());
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            if (endpoint.contains('/api/auth/login') ||
                endpoint.contains('/api/auth/refresh')) {
                response.setStatusCode(200);
                response.setBody(
                    '{"token":"list-controller-test-token","expiresIn":3600}'
                );
                return response;
            }

            if (endpoint.contains('/api/loads')) {
                response.setStatusCode(200);
                response.setBody('{}');
                return response;
            }

            System.assertEquals('POST', request.getMethod());
            System.assert(
                endpoint.contains(
                    '/api/EmailExtractor/process-email-with-files'
                )
            );
            System.assertEquals(
                'Bearer list-controller-test-token',
                request.getHeader('Authorization')
            );
            System.assert(
                request.getHeader('Content-Type')
                    .startsWith('multipart/form-data; boundary=')
            );
            System.assertNotEquals(null, request.getBodyAsBlob());

            String body = request.getBodyAsBlob().toString();
            System.assert(body.contains('EmailContent'));
            System.assert(body.contains('Attachments'));

            response.setStatusCode(statusCode);
            response.setBody(
                statusCode >= 200 && statusCode < 300
                    ? '{"success":true}'
                    : '{"success":false}'
            );
            return response;
        }
    }

    private static FreightTM__Load__c createLoad(
        String citySuffix
    ) {
        FreightTM__Load__c loadRecord =
            new FreightTM__Load__c(
                FreightTM__Pickup_City__c =
                    'Dallas ' + citySuffix,
                FreightTM__Delivery_City__c =
                    'Houston ' + citySuffix,
                FreightTM__Pickup_Date__c = Date.today(),
                FreightTM__Delivery_Date__c =
                    Date.today().addDays(1),
                FreightTM__Status__c = 'Assigned'
            );
        insert loadRecord;
        return loadRecord;
    }

    private static AutoFillListController
        buildController(
            List<FreightTM__Load__c> selectedLoads
        ) {
        List<FreightTM__Load__c> allLoads = [
            SELECT Id, Name
            FROM FreightTM__Load__c
            ORDER BY CreatedDate
        ];

        ApexPages.StandardSetController setController =
            new ApexPages.StandardSetController(allLoads);

        setController.setSelected(selectedLoads);

        return new AutoFillListController(
            setController
        );
    }

    private static String getLastMessageSummary() {
        List<ApexPages.Message> messages =
            ApexPages.getMessages();

        System.assert(
            !messages.isEmpty(),
            'Expected an ApexPages message.'
        );

        return messages[messages.size() - 1].getSummary();
    }

    @IsTest
    static void sendToApi_validatesSelectionAndInputs() {
        Test.setMock(HttpCalloutMock.class, new ApiMock(200));
        FreightTM__Load__c firstLoad = createLoad('One');
        FreightTM__Load__c secondLoad = createLoad('Two');

        AutoFillListController noSelection =
            buildController(
                new List<FreightTM__Load__c>()
            );

        System.assertEquals(null, noSelection.sendToApi());
        System.assertEquals(1, ApexPages.getMessages().size());
        System.assertEquals(
            'Please select one Load record.',
            getLastMessageSummary()
        );

        AutoFillListController multipleSelection =
            buildController(
                new List<FreightTM__Load__c>{
                    firstLoad,
                    secondLoad
                }
            );

        multipleSelection.emailContent = 'Description';
        multipleSelection.uploadedFile1 =
            Blob.valueOf('file');
        multipleSelection.sendToApi();

        System.assertEquals(
            'Please select only one Load record.',
            getLastMessageSummary()
        );

        AutoFillListController missingDescription =
            buildController(
                new List<FreightTM__Load__c>{
                    firstLoad
                }
            );

        missingDescription.uploadedFile1 =
            Blob.valueOf('file');
        missingDescription.sendToApi();

        System.assertEquals(
            'Description is required.',
            getLastMessageSummary()
        );

        AutoFillListController missingFiles =
            buildController(
                new List<FreightTM__Load__c>{
                    firstLoad
                }
            );

        missingFiles.emailContent = 'Description';
        missingFiles.sendToApi();

        System.assertEquals(
            'Please upload at least one file.',
            getLastMessageSummary()
        );
    }

    private static AutoFillListController
        buildReadyCalloutController() {
        FreightTM__Load__c loadRecord = createLoad('Callout');

        AutoFillListController controller =
            buildController(
                new List<FreightTM__Load__c>{
                    loadRecord
                }
            );

        controller.emailContent =
            'Process attached documents.';
        controller.uploadedFile1 =
            Blob.valueOf('first-file');
        controller.uploadedFile1Name =
            'first.pdf';
        controller.uploadedFile2 =
            Blob.valueOf('second-file');
        controller.uploadedFile2Name =
            null;

        AutoFillListController.testAccessToken =
            'list-controller-test-token';

        return controller;
    }

    @IsTest
    static void sendToApi_handlesSuccessfulCallout() {
        AutoFillListController controller =
            buildReadyCalloutController();

        Test.setMock(
            HttpCalloutMock.class,
            new ApiMock(200)
        );


        Test.startTest();
        PageReference result = controller.sendToApi();
        Test.stopTest();

        System.assertEquals(null, result);
        System.assertEquals(
            'Email content and attachments were sent successfully.',
            getLastMessageSummary()
        );
    }

    @IsTest
    static void sendToApi_handlesFailedCallout() {
        AutoFillListController controller =
            buildReadyCalloutController();

        Test.setMock(
            HttpCalloutMock.class,
            new ApiMock(500)
        );


        Test.startTest();
        controller.sendToApi();
        Test.stopTest();

        System.assert(
            getLastMessageSummary()
                .contains('API call failed. Status: 500')
        );
    }

    @IsTest
    static void cancel_returnsLoadListPage() {
        AutoFillListController controller =
            buildController(
                new List<FreightTM__Load__c>()
            );

        PageReference result = controller.cancel();

        System.assertEquals(
            '/lightning/o/FreightTM__Load__c/list',
            result.getUrl()
        );
        System.assertEquals(true, result.getRedirect());
    }
}