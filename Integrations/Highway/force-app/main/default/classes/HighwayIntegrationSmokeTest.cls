@IsTest
private class HighwayIntegrationSmokeTest {
    private class HighwayMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('[{"id":101,"carrier_detail":{"id":202}}]');
            return response;
        }
    }

    @IsTest
    static void utilityMethodsAndCallout() {
        System.assertEquals('Main Street 123', HighwayAPIService.formatAddress('123 Main Street'));
        System.assertEquals('United States', HighwayAPIService.getFullCountryName('US'));
        System.assertEquals('John Smith', HighwayAPIService.getFirstTwoWords('John Smith Jones'));
        System.assertEquals(Date.newInstance(2026, 7, 29), HighwayAPIService.parseDateSafely('2026-07-29T10:00:00Z', 1900));

        HighwayAPIService.IdsWrapper ids = HighwayAPIService.extractCarrierIds('[{"id":101,"carrier_detail":{"id":202}}]', false);
        System.assertEquals(1, ids.carrierIds.size());
        System.assertEquals(202, ids.carrierIds[0]);

        Test.setMock(HttpCalloutMock.class, new HighwayMock());
        HighwayAPIService.HIGHWAY_API_KEY = 'test-key';
        HttpResponse response = HighwayAPIService.makeApiCall('https://staging.highway.com/mock', 'GET');
        System.assertEquals(200, response.getStatusCode());
    }

    @IsTest
    static void webhookRejectsWrongToken() {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/highway/webhook/';
        request.httpMethod = 'POST';
        request.addParameter('token', 'wrong');
        request.requestBody = Blob.valueOf('{}');
        RestContext.request = request;
        RestContext.response = new RestResponse();
        HighwayWebhookController.webhookSecretOverride = 'expected';

        HighwayWebhookController.handleWebhook();
        System.assertEquals(401, RestContext.response.statusCode);
    }

    @IsTest
    static void visualforceControllersHandleMissingLoadId() {
        Test.setCurrentPage(Page.HighwaySendRatecon);
        HighwaySendRateConVFController firstController = new HighwaySendRateConVFController();
        firstController.send();
        System.assertEquals(false, firstController.success);

        Test.setCurrentPage(Page.HighwaySendTotalRateCon);
        HighwaySendTotalRateConVFController totalController = new HighwaySendTotalRateConVFController();
        totalController.send();
        System.assertEquals(false, totalController.success);
    }

    @IsTest
    static void contractFileBatchHandlesEmptyInput() {
        ContractFileBatch batch = new ContractFileBatch(
            new List<HighwayAPIService.ContractFileData>()
        );

        batch.execute(null, new List<HighwayAPIService.ContractFileData>());
        batch.finish(null);
        System.assertNotEquals(null, batch.start(null));
    }
}