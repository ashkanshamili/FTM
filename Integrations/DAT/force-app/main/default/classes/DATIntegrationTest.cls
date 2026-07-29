@IsTest
private class DATIntegrationTest {
    private class DATMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            String endpoint = request.getEndpoint();

            if (endpoint.endsWith('/access/v1/token/organization')) {
                response.setStatusCode(200);
                response.setBody('{"accessToken":"ORG_TOKEN"}');
                return response;
            }
            if (endpoint.endsWith('/access/v1/token/user')) {
                response.setStatusCode(200);
                response.setBody('{"accessToken":"USER_TOKEN"}');
                return response;
            }
            if (request.getMethod() == 'POST' && endpoint.endsWith('/posting/v2/loads')) {
                response.setStatusCode(201);
                response.setBody('{"id":"POST-123","shipmentId":"SHIP-456"}');
                return response;
            }
            if (request.getMethod() == 'PATCH') {
                response.setStatusCode(200);
                response.setBody('{"id":"POST-123","shipmentId":"SHIP-456"}');
                return response;
            }
            if (request.getMethod() == 'DELETE') {
                response.setStatusCode(204);
                response.setBody('');
                return response;
            }

            response.setStatusCode(404);
            response.setBody('{}');
            return response;
        }
    }

    private static void configure() {
        DATIntegrationConfig.Settings settings = new DATIntegrationConfig.Settings();
        settings.enabled = true;
        settings.partnerId = 'PARTNER-TEST';
        settings.environmentLabel = 'Test';
        settings.orgTokenTtlSeconds = 1680;
        settings.userTokenTtlSeconds = 1680;
        DATIntegrationConfig.testSettings = settings;

        DATEquipmentMapper.testMappings = new Map<String, String>{
            firstTrailerValue() => 'V'
        };
        DATTokenService.disableCacheForTests = true;
    }

    @IsTest
    static void mapperBuildsPayloadAndRejectsBadDates() {
        configure();
        FreightTM__Load__c good = loadRecord();
        Map<String, Object> payload = DATLoadMapper.buildPostPayload(good);
        System.assert(payload.containsKey('freight'));
        System.assert(payload.containsKey('lane'));
        System.assert(payload.containsKey('exposure'));

        good.FreightTM__Delivery_Date__c = good.FreightTM__Pickup_Date__c.addDays(-1);
        try {
            DATLoadMapper.buildPostPayload(good);
            System.assert(false, 'Expected bad date validation.');
        } catch (DATIntegrationException ex) {
            System.assert(ex.getMessage().contains('Delivery Date'));
        }
    }

    @IsTest
    static void tokensAndClientSuccess() {
        configure();
        Test.setMock(HttpCalloutMock.class, new DATMock());
        DATTokenService.disableCacheForTests = true;

        Test.startTest();
        String orgToken = DATTokenService.getOrganizationToken();
        String userToken = DATTokenService.getUserToken(orgToken);
        DATHttpClient.Response postResponse = DATHttpClient.postLoad(
            DATLoadMapper.buildPostPayload(loadRecord())
        );
        DATHttpClient.Response patchResponse = DATHttpClient.updateLoad(
            'POST-123',
            DATLoadMapper.buildUpdatePayload(loadRecord())
        );
        DATHttpClient.Response deleteResponse = DATHttpClient.deleteLoad('POST-123');
        Test.stopTest();

        System.assertEquals('ORG_TOKEN', orgToken);
        System.assertEquals('USER_TOKEN', userToken);
        System.assertEquals(201, postResponse.statusCode);
        System.assertEquals(200, patchResponse.statusCode);
        System.assertEquals(204, deleteResponse.statusCode);
    }

    @IsTest
    static void controllerPostFlow() {
        configure();
        FreightTM__Load__c loadToInsert = loadRecord();
        insert loadToInsert;

        DATLoadActionController.bypassPermissionForTests = true;
        Test.setMock(HttpCalloutMock.class, new DATMock());

        Test.startTest();
        DATLoadActionController.State initialState = DATLoadActionController.getState(loadToInsert.Id);
        DATLoadService.Result posted = DATLoadActionController.postLoad(loadToInsert.Id);
        Test.stopTest();

        System.assertEquals(true, initialState.canPost);
        System.assertEquals('POST-123', posted.postId);
        FreightTM__Load__c refreshed = [
            SELECT DAT_Post_Id__c, DAT_Shipment_Id__c
            FROM FreightTM__Load__c
            WHERE Id = :loadToInsert.Id
        ];
        System.assertEquals('POST-123', refreshed.DAT_Post_Id__c);
        System.assertEquals('SHIP-456', refreshed.DAT_Shipment_Id__c);
    }

    @IsTest
    static void controllerUpdateFlow() {
        configure();
        FreightTM__Load__c loadToInsert = loadRecord();
        loadToInsert.DAT_Post_Id__c = 'POST-123';
        loadToInsert.DAT_Shipment_Id__c = 'SHIP-456';
        insert loadToInsert;

        DATLoadActionController.bypassPermissionForTests = true;
        Test.setMock(HttpCalloutMock.class, new DATMock());

        Test.startTest();
        DATLoadService.Result updated = DATLoadActionController.updateLoad(loadToInsert.Id);
        Test.stopTest();
        System.assertEquals('UPDATE', updated.operation);
    }

    @IsTest
    static void controllerDeleteFlow() {
        configure();
        FreightTM__Load__c loadToInsert = loadRecord();
        loadToInsert.DAT_Post_Id__c = 'POST-123';
        loadToInsert.DAT_Shipment_Id__c = 'SHIP-456';
        insert loadToInsert;

        DATLoadActionController.bypassPermissionForTests = true;
        Test.setMock(HttpCalloutMock.class, new DATMock());

        Test.startTest();
        DATLoadService.Result deleted = DATLoadActionController.deleteLoad(loadToInsert.Id);
        Test.stopTest();
        System.assertEquals('DELETE', deleted.operation);

        FreightTM__Load__c refreshed = [
            SELECT DAT_Post_Id__c, DAT_Shipment_Id__c
            FROM FreightTM__Load__c
            WHERE Id = :loadToInsert.Id
        ];
        System.assertEquals(null, refreshed.DAT_Post_Id__c);
        System.assertEquals(null, refreshed.DAT_Shipment_Id__c);
    }

    @IsTest
    static void duplicatePostAndMissingPermissionAreBlocked() {
        configure();
        FreightTM__Load__c loadToInsert = loadRecord();
        loadToInsert.DAT_Post_Id__c = 'EXISTING';
        insert loadToInsert;

        DATLoadActionController.bypassPermissionForTests = false;
        try {
            DATLoadActionController.postLoad(loadToInsert.Id);
            System.assert(false, 'Permission should be required.');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage().contains('permission'));
        }

        DATLoadActionController.bypassPermissionForTests = true;
        try {
            DATLoadActionController.postLoad(loadToInsert.Id);
            System.assert(false, 'Duplicate post should be blocked.');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage().contains('already posted'));
        }
    }

    private static FreightTM__Load__c loadRecord() {
        return new FreightTM__Load__c(
            FreightTM__Required_Trailer__c = firstTrailerValue(),
            FreightTM__Size__c = 'FTL',
            FreightTM__Remarks__c = 'DAT unit test',
            FreightTM__Weight__c = 10000,
            FreightTM__Pickup_City__c = 'Portland',
            FreightTM__Pickup_State__c = 'OR',
            FreightTM__Pickup_Zip_Code__c = '97204',
            FreightTM__Delivery_City__c = 'Boise',
            FreightTM__Delivery_State__c = 'ID',
            FreightTM__Delivery_Zip_Code__c = '83702',
            FreightTM__Pickup_Date__c = Date.today().addDays(3),
            FreightTM__Delivery_Date__c = Date.today().addDays(4)
        );
    }

    private static String firstTrailerValue() {
        List<Schema.PicklistEntry> entries =
            FreightTM__Load__c.FreightTM__Required_Trailer__c.getDescribe().getPicklistValues();
        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return entries.isEmpty() ? 'Dry Van Trailer - Door clearance 110" tall required' : entries[0].getValue();
    }
}
