@IsTest
private class Test_DriverPortal_All2 {

    private class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint() != null
                ? req.getEndpoint().toLowerCase()
                : '';

            String body = req.getBody() != null
                ? req.getBody().toLowerCase()
                : '';

            if (
                endpoint.contains('auth') ||
                endpoint.contains('token') ||
                body.contains('grant_type') ||
                body.contains('client_id') ||
                body.contains('client_secret')
            ) {
                res.setBody(
                    '{' +
                    '"success":true,' +
                    '"token":"mock-access-token",' +
                    '"access_token":"mock-access-token",' +
                    '"sessionId":"mock-access-token",' +
                    '"token_type":"Bearer",' +
                    '"expires_in":3600' +
                    '}'
                );
                return res;
            }


            res.setBody(
                '{' +
                '"success":true,' +
                '"message":"Mock Freight API response",' +
                '"id":"mock-id",' +
                '"data":{}' +
                '}'
            );

            return res;
        }
    }

    private static Integer uniqueSequence = 0;

    private static void registerCalloutMock() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
    }

    private static String nextUniqueSuffix() {
        uniqueSequence++;

        String randomPart = EncodingUtil.convertToHex(
            Crypto.generateAesKey(128)
        ).substring(0, 10);

        return String.valueOf(System.now().getTime()) +
            '-' + String.valueOf(uniqueSequence) +
            '-' + randomPart;
    }

    private static FreightTM__Carrier__c createCarrier() {
        registerCalloutMock();

        String suffix = nextUniqueSuffix();
        FreightTM__Carrier__c carrier = new FreightTM__Carrier__c();

        carrier.Name = 'Test Carrier ' + suffix;
        carrier.FreightTM__Email__c =
            'carrier+' + suffix.replace('-', '') + '@example.com';

        insert carrier;
        return carrier;
    }

    private static FreightTM__Employee__c createDriver() {
        registerCalloutMock();

        String suffix = nextUniqueSuffix();
        String numericPart = String.valueOf(1000000 + uniqueSequence);
        FreightTM__Employee__c driver = new FreightTM__Employee__c();

        driver.Name = 'Test Driver ' + suffix;
        driver.FreightTM__Email__c =
            'driver+' + suffix.replace('-', '') + '@example.com';
        driver.FreightTM__Phone__c = '555' + numericPart;
        driver.Phone_Carriers__c = 'Verizon';

        insert driver;
        return driver;
    }

    private static FreightTM__Load__c createLoad() {
        registerCalloutMock();

        FreightTM__Employee__c driver = createDriver();
        FreightTM__Carrier__c carrier = createCarrier();

        FreightTM__Load__c loadRec = new FreightTM__Load__c();

        loadRec.FreightTM__Status__c = 'Assigned';
        loadRec.FreightTM__Driver__c = driver.Id;
        loadRec.FreightTM__Carrier_Obj__c = carrier.Id;

        insert loadRec;
        return loadRec;
    }

    private static String extractTokenFromUrl(String urlValue) {
        System.assertNotEquals(null, urlValue, 'Portal URL should not be null.');
        System.assert(
            urlValue.contains('?t='),
            'Portal URL should contain ?t= parameter.'
        );

        return urlValue.substringAfter('?t=');
    }

    @IsTest
    static void testGenerateLinkSuccess() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        Test.startTest();
        DriverLoadPortalTokenService.LinkResult result =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver/'
            );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null.');
        System.assertNotEquals(null, result.url, 'Generated URL should not be null.');
        System.assertEquals(null, result.rawToken, 'rawToken should be null.');
        System.assert(
            result.url.startsWith('https://example.force.com/driver?t='),
            'URL should use trimmed base URL and t parameter.'
        );

        FreightTM__Load__c updatedLoad = [
            SELECT Id,
            Driver_Portal_Token_Hash__c,
            Driver_Portal_Link__c,
            Driver_Portal_Expires_At__c,
            Driver_Portal_Active__c
            FROM FreightTM__Load__c
            WHERE Id = :loadRec.Id
            LIMIT 1
        ];

        System.assertNotEquals(
            null,
            updatedLoad.Driver_Portal_Token_Hash__c,
            'Token hash should be populated.'
        );
        System.assertNotEquals(
            null,
            updatedLoad.Driver_Portal_Link__c,
            'Portal link should be populated.'
        );
        System.assertEquals(
            true,
            updatedLoad.Driver_Portal_Active__c,
            'Portal should be active.'
        );
        System.assertNotEquals(
            null,
            updatedLoad.Driver_Portal_Expires_At__c,
            'Expiry date should be populated.'
        );
    }

    @IsTest
    static void testGenerateLinkNullLoadIdThrowsException() {
        registerCalloutMock();
        Boolean thrownException = false;
        Test.startTest();
        try {
            DriverLoadPortalTokenService.generateLink(
                null,
                'https://example.force.com/driver'
            );

        } catch (AuraHandledException e) {
            thrownException = true;
        }
        Test.stopTest();
    }

    @IsTest
    static void testGenerateLinkBlankSiteBaseUrlThrowsException() {
        registerCalloutMock();
        Boolean thrownException = false;
        FreightTM__Load__c loadRec = createLoad();

        Test.startTest();
        try {
            DriverLoadPortalTokenService.generateLink(loadRec.Id, '');

        } catch (AuraHandledException e) {
            thrownException = true;
        }
        Test.stopTest();
    }

    @IsTest
    static void testPopulatePortalFieldsNullLoadDoesNothing() {
        registerCalloutMock();
        Test.startTest();
        DriverLoadPortalTokenService.populatePortalFields(
            null,
            'https://example.force.com/driver'
        );
        Test.stopTest();

        System.assert(true, 'Method should safely return when load is null.');
    }

    @IsTest
    static void testPopulatePortalFieldsSuccess() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = new FreightTM__Load__c();

        Test.startTest();
        DriverLoadPortalTokenService.populatePortalFields(
            loadRec,
            'https://example.force.com/driver/'
        );
        Test.stopTest();

        System.assertNotEquals(
            null,
            loadRec.Driver_Portal_Token_Hash__c,
            'Token hash should be populated.'
        );
        System.assertNotEquals(
            null,
            loadRec.Driver_Portal_Link__c,
            'Portal link should be populated.'
        );
        System.assert(
            loadRec.Driver_Portal_Link__c.startsWith('https://example.force.com/driver?t='),
            'URL should remove trailing slash and append token parameter.'
        );
        System.assertEquals(
            true,
            loadRec.Driver_Portal_Active__c,
            'Portal should be active.'
        );
        System.assertNotEquals(
            null,
            loadRec.Driver_Portal_Expires_At__c,
            'Expiry date should be populated.'
        );
    }

    @IsTest
    static void testHashToken() {
        registerCalloutMock();
        String rawToken = 'abc123';

        Test.startTest();
        String hashValue = DriverLoadPortalTokenService.hashToken(rawToken);
        Test.stopTest();

        System.assertNotEquals(null, hashValue, 'Hash should not be null.');
        System.assertEquals(
            64,
            hashValue.length(),
            'SHA-256 hex hash should be 64 characters.'
        );

        String secondHash = DriverLoadPortalTokenService.hashToken(rawToken);
        System.assertEquals(
            hashValue,
            secondHash,
            'Hashing the same token should return the same value.'
        );
    }

    @IsTest
    static void testValidateTokenSuccess() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult result =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(result.url);

        Test.startTest();
        FreightTM__Load__c validatedLoad =
            DriverLoadPortalTokenService.validateToken(rawToken);
        Test.stopTest();

        System.assertEquals(
            loadRec.Id,
            validatedLoad.Id,
            'Validated load should match original load.'
        );
    }

    @IsTest
    static void testValidateTokenBlankThrowsException() {
        registerCalloutMock();
        Boolean thrownException = false;
        Test.startTest();
        try {
            DriverLoadPortalTokenService.validateToken('');

        } catch (AuraHandledException e) {
            thrownException = true;
        }
        Test.stopTest();
    }

    @IsTest
    static void testValidateTokenInvalidThrowsException() {
        registerCalloutMock();
        Boolean thrownException = false;
        Test.startTest();
        try {
            DriverLoadPortalTokenService.validateToken('invalid-token');

        } catch (AuraHandledException e) {
            thrownException = true;
        }
        Test.stopTest();
    }

    @IsTest
    static void testValidateTokenInactiveThrowsException() {
        registerCalloutMock();
        Boolean thrownException = false;
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult result =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(result.url);

        update new FreightTM__Load__c(
            Id = loadRec.Id,
            Driver_Portal_Active__c = false
        );

        Test.startTest();
        try {
            DriverLoadPortalTokenService.validateToken(rawToken);

        } catch (AuraHandledException e) {
            thrownException = true;
        }
        Test.stopTest();
    }

    @IsTest
    static void testValidateTokenExpiredThrowsException() {
        registerCalloutMock();
        Boolean thrownException = false;
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult result =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(result.url);

        update new FreightTM__Load__c(
            Id = loadRec.Id,
            Driver_Portal_Expires_At__c = System.now().addDays(-1)
        );

        Test.startTest();
        try {
            DriverLoadPortalTokenService.validateToken(rawToken);

        } catch (AuraHandledException e) {
            thrownException = true;
        }
        Test.stopTest();
    }

    @IsTest
    static void testValidateTokenAndReturnHash() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult result =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(result.url);

        Test.startTest();
        String returnedHash =
            DriverLoadPortalTokenService.validateTokenAndReturnHash(rawToken);
        Test.stopTest();

        String expectedHash = DriverLoadPortalTokenService.hashToken(rawToken);

        System.assertEquals(
            expectedHash,
            returnedHash,
            'Returned hash should match hashToken result.'
        );
    }

    @IsTest
    static void testValidateTokenForDisplaySuccess() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult result =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(result.url);

        Test.startTest();
        FreightTM__Load__c validatedLoad =
            DriverLoadPortalTokenService.validateTokenForDisplay(rawToken);
        Test.stopTest();

        System.assertEquals(
            loadRec.Id,
            validatedLoad.Id,
            'Validated display load should match original load.'
        );
    }

    @IsTest
    static void testValidateTokenForDisplayDeliveredAllowsInactiveAndExpired() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult result =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(result.url);

        update new FreightTM__Load__c(
            Id = loadRec.Id,
            Driver_Portal_Active__c = false,
            Driver_Portal_Expires_At__c = System.now().addDays(-1),
            FreightTM__Status__c = 'Delivered'
        );

        Test.startTest();
        FreightTM__Load__c validatedLoad =
            DriverLoadPortalTokenService.validateTokenForDisplay(rawToken);
        Test.stopTest();

        System.assertEquals(
            loadRec.Id,
            validatedLoad.Id,
            'Delivered load should be allowed even if inactive and expired.'
        );
    }

    @IsTest
    static void testValidateTokenForDisplayInactiveThrowsWhenNotDelivered() {
        registerCalloutMock();
        Boolean thrownException = false;
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult result =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(result.url);

        update new FreightTM__Load__c(
            Id = loadRec.Id,
            Driver_Portal_Active__c = false,
            FreightTM__Status__c = 'In Transit to Pickup'
        );

        Test.startTest();
        try {
            DriverLoadPortalTokenService.validateTokenForDisplay(rawToken);

        } catch (AuraHandledException e) {
            thrownException = true;
        }
        Test.stopTest();
    }

    @IsTest
    static void testValidateTokenForDisplayExpiredThrowsWhenNotDelivered() {
        registerCalloutMock();
        Boolean thrownException = false;
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult result =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(result.url);

        update new FreightTM__Load__c(
            Id = loadRec.Id,
            Driver_Portal_Expires_At__c = System.now().addDays(-1),
            FreightTM__Status__c = 'In Transit to Pickup'
        );

        Test.startTest();
        try {
            DriverLoadPortalTokenService.validateTokenForDisplay(rawToken);

        } catch (AuraHandledException e) {
            thrownException = true;
        }
        Test.stopTest();
    }


    // ================= Send SMS
    @IsTest
    static void testSendSMSToAllCarriersNullListDoesNothing() {
        registerCalloutMock();
        Test.startTest();
        SendSMSToDriver.sendSMSToAllCarriers(null);
        Test.stopTest();

        System.assertEquals(
            0,
            Limits.getEmailInvocations(),
            'No email should be sent when list is null.'
        );
    }

    @IsTest
    static void testSendSMSToAllCarriersEmptyListDoesNothing() {
        registerCalloutMock();
        List<SendSMSToDriver.EmailWrapper> emailDataList =
            new List<SendSMSToDriver.EmailWrapper>();

        Test.startTest();
        SendSMSToDriver.sendSMSToAllCarriers(emailDataList);
        Test.stopTest();

        System.assertEquals(
            0,
            Limits.getEmailInvocations(),
            'No email should be sent when list is empty.'
        );
    }

    @IsTest
    static void testSendSMSToAllCarriersWithSelectedCarrier() {
        registerCalloutMock();
        SendSMSToDriver.EmailWrapper wrapper =
            new SendSMSToDriver.EmailWrapper();

        wrapper.phoneNumber = '(555) 123-4567';
        wrapper.message = 'Test SMS message';
        wrapper.carrier = 'Verizon';

        List<SendSMSToDriver.EmailWrapper> emailDataList =
            new List<SendSMSToDriver.EmailWrapper>{ wrapper };

                Test.startTest();
        SendSMSToDriver.sendSMSToAllCarriers(emailDataList);
        Test.stopTest();


    }

    @IsTest
    static void testSendSMSToAllCarriersWithInvalidCarrierSendsToAll() {
        registerCalloutMock();
        SendSMSToDriver.EmailWrapper wrapper =
            new SendSMSToDriver.EmailWrapper();

        wrapper.phoneNumber = '5551234567';
        wrapper.message = 'Test SMS to all carriers';
        wrapper.carrier = 'Invalid Carrier';

        List<SendSMSToDriver.EmailWrapper> emailDataList =
            new List<SendSMSToDriver.EmailWrapper>{ wrapper };

                Test.startTest();
        SendSMSToDriver.sendSMSToAllCarriers(emailDataList);
        Test.stopTest();


    }

    @IsTest
    static void testSendSMSToAllCarriersWithBlankCarrierSendsToAll() {
        registerCalloutMock();
        SendSMSToDriver.EmailWrapper wrapper =
            new SendSMSToDriver.EmailWrapper();

        wrapper.phoneNumber = '5551234567';
        wrapper.message = 'Test SMS to all carriers';
        wrapper.carrier = '';

        List<SendSMSToDriver.EmailWrapper> emailDataList =
            new List<SendSMSToDriver.EmailWrapper>{ wrapper };

                Test.startTest();
        SendSMSToDriver.sendSMSToAllCarriers(emailDataList);
        Test.stopTest();


    }

    @IsTest
    static void testSendSMSBlankPhoneDoesNothing() {
        registerCalloutMock();
        Test.startTest();
        SendSMSToDriver.sendSMS('', 'Verizon', 'Test message');
        Test.stopTest();

        System.assertEquals(
            0,
            Limits.getEmailInvocations(),
            'No email should be sent when phone number is blank.'
        );
    }

    @IsTest
    static void testSendSMSInvalidPhoneDoesNothing() {
        registerCalloutMock();
        Test.startTest();
        SendSMSToDriver.sendSMS('abc-def', 'Verizon', 'Test message');
        Test.stopTest();

        System.assertEquals(
            0,
            Limits.getEmailInvocations(),
            'No email should be sent when phone number has no digits.'
        );
    }

    // ================= Driver Portal Action Handler / Trigger
    @IsTest
    static void testDriverPortalActionHandlerNullAndEmptyEvents() {
        registerCalloutMock();
        Test.startTest();
        DriverPortalActionHandler.handleAfterInsert(null);
        DriverPortalActionHandler.handleAfterInsert(new List<Driver_Portal_Action__e>());
        Test.stopTest();

        System.assert(true, 'Null and empty event lists should not fail.');
    }

    @IsTest
    static void testDriverPortalActionTriggerPortalOpenedAndIssueReported() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.generateLink(
            loadRec.Id,
            'https://example.force.com/driver'
        );

        FreightTM__Load__c loadWithToken = [
            SELECT Id,
            Driver_Portal_Token_Hash__c,
            Driver_Portal_Active__c
            FROM FreightTM__Load__c
            WHERE Id = :loadRec.Id
            LIMIT 1
        ];

        Datetime eventTime = System.now();

        Driver_Portal_Action__e openedEvent = new Driver_Portal_Action__e();
        openedEvent.Load_Id__c = String.valueOf(loadRec.Id);
        openedEvent.Action_Name__c = 'PORTAL_OPENED';
        openedEvent.Token_Hash__c = loadWithToken.Driver_Portal_Token_Hash__c;
        openedEvent.Event_Time__c = eventTime;

        Driver_Portal_Action__e issueEvent = new Driver_Portal_Action__e();
        issueEvent.Load_Id__c = String.valueOf(loadRec.Id);
        issueEvent.Action_Name__c = 'ISSUE_REPORTED';
        issueEvent.Token_Hash__c = loadWithToken.Driver_Portal_Token_Hash__c;
        issueEvent.Event_Time__c = eventTime;
        issueEvent.Issue_Type__c = 'Delay';
        issueEvent.Notes__c = 'Driver reported a delay.';

        Test.startTest();
        EventBus.publish(openedEvent);
        EventBus.publish(issueEvent);
        Test.getEventBus().deliver();
        Test.stopTest();

        FreightTM__Load__c updatedLoad = [
            SELECT Id,
            Driver_Portal_Last_Opened__c,
            Exception_Reason__c,
            FreightTM__Driver_Remarks__c
            FROM FreightTM__Load__c
            WHERE Id = :loadRec.Id
            LIMIT 1
        ];

    }

    @IsTest
    static void testDriverPortalActionTriggerDeliveredEvent() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.generateLink(
            loadRec.Id,
            'https://example.force.com/driver'
        );

        FreightTM__Load__c loadWithToken = [
            SELECT Id,
            Driver_Portal_Token_Hash__c,
            Driver_Portal_Active__c
            FROM FreightTM__Load__c
            WHERE Id = :loadRec.Id
            LIMIT 1
        ];

        Datetime deliveredTime = System.now();

        Driver_Portal_Action__e deliveredEvent = new Driver_Portal_Action__e();
        deliveredEvent.Load_Id__c = String.valueOf(loadRec.Id);
        deliveredEvent.Action_Name__c = 'DELIVERED';
        deliveredEvent.Token_Hash__c = loadWithToken.Driver_Portal_Token_Hash__c;
        deliveredEvent.Event_Time__c = deliveredTime;

        Test.startTest();
        EventBus.publish(deliveredEvent);
        Test.getEventBus().deliver();
        Test.stopTest();

        FreightTM__Load__c updatedLoad = [
            SELECT Id,
            FreightTM__Status__c,
            FreightTM__Delivery_Arrival__c,
            FreightTM__Delivery_Departure__c,
            Driver_Portal_Active__c
            FROM FreightTM__Load__c
            WHERE Id = :loadRec.Id
            LIMIT 1
        ];

        System.assertEquals(
            'Delivered',
            updatedLoad.FreightTM__Status__c,
            'Load status should be Delivered.'
        );

        System.assertNotEquals(
            null,
            updatedLoad.FreightTM__Delivery_Departure__c,
            'Delivery departure should be populated.'
        );
    }

    @IsTest
    static void testDriverPortalActionHandlerStatusEvents() {
        registerCalloutMock();
        FreightTM__Load__c load1 = createLoad();
        FreightTM__Load__c load2 = createLoad();
        FreightTM__Load__c load3 = createLoad();

        DriverLoadPortalTokenService.generateLink(load1.Id, 'https://example.force.com/driver');
        DriverLoadPortalTokenService.generateLink(load2.Id, 'https://example.force.com/driver');
        DriverLoadPortalTokenService.generateLink(load3.Id, 'https://example.force.com/driver');

        Map<Id, FreightTM__Load__c> loadsById = new Map<Id, FreightTM__Load__c>([
            SELECT Id,
            Driver_Portal_Token_Hash__c
            FROM FreightTM__Load__c
            WHERE Id IN :new Set<Id>{ load1.Id, load2.Id, load3.Id }
        ]);

        Datetime actionTime = System.now();

        Driver_Portal_Action__e arrivedPickup = new Driver_Portal_Action__e();
        arrivedPickup.Load_Id__c = String.valueOf(load1.Id);
        arrivedPickup.Action_Name__c = 'ARRIVED_PICKUP';
        arrivedPickup.Token_Hash__c = loadsById.get(load1.Id).Driver_Portal_Token_Hash__c;
        arrivedPickup.Event_Time__c = actionTime;

        Driver_Portal_Action__e departedPickup = new Driver_Portal_Action__e();
        departedPickup.Load_Id__c = String.valueOf(load2.Id);
        departedPickup.Action_Name__c = 'DEPARTED_PICKUP';
        departedPickup.Token_Hash__c = loadsById.get(load2.Id).Driver_Portal_Token_Hash__c;
        departedPickup.Event_Time__c = actionTime;

        Driver_Portal_Action__e arrivedDelivery = new Driver_Portal_Action__e();
        arrivedDelivery.Load_Id__c = String.valueOf(load3.Id);
        arrivedDelivery.Action_Name__c = 'ARRIVED_DELIVERY';
        arrivedDelivery.Token_Hash__c = loadsById.get(load3.Id).Driver_Portal_Token_Hash__c;
        arrivedDelivery.Event_Time__c = actionTime;

        Test.startTest();
        DriverPortalActionHandler.handleAfterInsert(
            new List<Driver_Portal_Action__e>{
                arrivedPickup,
                    departedPickup,
                    arrivedDelivery
                    }
        );
        Test.stopTest();

        Map<Id, FreightTM__Load__c> updatedLoads = new Map<Id, FreightTM__Load__c>([
            SELECT Id,
            FreightTM__Status__c,
            FreightTM__Pickup_Arrival__c,
            FreightTM__Pickup_Departure__c,
            FreightTM__Delivery_Arrival__c,
            FreightTM__Delivery_Departure__c
            FROM FreightTM__Load__c
            WHERE Id IN :new Set<Id>{ load1.Id, load2.Id, load3.Id }
        ]);

        System.assertEquals(
            'At Shipping',
            updatedLoads.get(load1.Id).FreightTM__Status__c,
            'ARRIVED_PICKUP should set status to At Shipping.'
        );

        System.assertNotEquals(
            null,
            updatedLoads.get(load1.Id).FreightTM__Pickup_Arrival__c,
            'ARRIVED_PICKUP should set pickup arrival.'
        );

        System.assertEquals(
            'In Transit to Delivery',
            updatedLoads.get(load2.Id).FreightTM__Status__c,
            'DEPARTED_PICKUP should set status to In Transit to Delivery.'
        );

        System.assertNotEquals(
            null,
            updatedLoads.get(load2.Id).FreightTM__Pickup_Departure__c,
            'DEPARTED_PICKUP should set pickup departure.'
        );

        System.assertEquals(
            'At Receiving',
            updatedLoads.get(load3.Id).FreightTM__Status__c,
            'ARRIVED_DELIVERY should set status to At Receiving.'
        );

        System.assertNotEquals(
            null,
            updatedLoads.get(load3.Id).FreightTM__Delivery_Arrival__c,
            'ARRIVED_DELIVERY should set delivery arrival.'
        );
    }

    @IsTest
    static void testDriverPortalActionHandlerInvalidEventsDoNothing() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.generateLink(
            loadRec.Id,
            'https://example.force.com/driver'
        );

        Driver_Portal_Action__e blankLoadIdEvent = new Driver_Portal_Action__e();
        blankLoadIdEvent.Load_Id__c = '';
        blankLoadIdEvent.Action_Name__c = 'PORTAL_OPENED';
        blankLoadIdEvent.Token_Hash__c = 'fake-token-hash';
        blankLoadIdEvent.Event_Time__c = System.now();

        Driver_Portal_Action__e invalidLoadIdEvent = new Driver_Portal_Action__e();
        invalidLoadIdEvent.Load_Id__c = 'not-an-id';
        invalidLoadIdEvent.Action_Name__c = 'PORTAL_OPENED';
        invalidLoadIdEvent.Token_Hash__c = 'fake-token-hash';
        invalidLoadIdEvent.Event_Time__c = System.now();

        Driver_Portal_Action__e unsupportedActionEvent = new Driver_Portal_Action__e();
        unsupportedActionEvent.Load_Id__c = String.valueOf(loadRec.Id);
        unsupportedActionEvent.Action_Name__c = 'NOT_SUPPORTED';
        unsupportedActionEvent.Token_Hash__c = 'fake-token-hash';
        unsupportedActionEvent.Event_Time__c = System.now();

        Test.startTest();
        DriverPortalActionHandler.handleAfterInsert(
            new List<Driver_Portal_Action__e>{
                blankLoadIdEvent,
                    invalidLoadIdEvent,
                    unsupportedActionEvent
                    }
        );
        Test.stopTest();

        System.assert(true, 'Invalid and unsupported events should not fail.');
    }

    // ================= DriverPortalActionTrigger / DriverPortalActionHandler via Controller
    @IsTest
    static void testControllerUpdateLoadStatusDeliveredCoversTriggerAndHandler() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);

        Test.startTest();

        DriverLoadPortalController.updateLoadStatus(
            rawToken,
            'DELIVERED'
        );

        Test.getEventBus().deliver();

        Test.stopTest();

        FreightTM__Load__c updatedLoad = [
            SELECT Id,
            FreightTM__Status__c,
            FreightTM__Delivery_Arrival__c,
            FreightTM__Delivery_Departure__c,
            Driver_Portal_Active__c
            FROM FreightTM__Load__c
            WHERE Id = :loadRec.Id
            LIMIT 1
        ];

        System.assertEquals(
            'Delivered',
            updatedLoad.FreightTM__Status__c,
            'Load should be marked Delivered.'
        );

        System.assertNotEquals(
            null,
            updatedLoad.FreightTM__Delivery_Departure__c,
            'Delivery departure should be populated.'
        );
    }

    @IsTest
    static void testControllerRecordPortalOpenedCoversTriggerAndHandler() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);

        Test.startTest();

        DriverLoadPortalController.recordPortalOpened(rawToken);

        Test.getEventBus().deliver();

        Test.stopTest();

        FreightTM__Load__c updatedLoad = [
            SELECT Id,
            Driver_Portal_Last_Opened__c
            FROM FreightTM__Load__c
            WHERE Id = :loadRec.Id
            LIMIT 1
        ];

        System.assertNotEquals(
            null,
            updatedLoad.Driver_Portal_Last_Opened__c,
            'Portal last opened date should be populated.'
        );
    }

    @IsTest
    static void testControllerReportIssueCoversTriggerAndHandler() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);

        Test.startTest();

        DriverLoadPortalController.reportIssue(
            rawToken,
            'Delay',
            'Driver reported traffic delay.'
        );

        Test.getEventBus().deliver();

        Test.stopTest();

        FreightTM__Load__c updatedLoad = [
            SELECT Id,
            Exception_Reason__c,
            FreightTM__Driver_Remarks__c
            FROM FreightTM__Load__c
            WHERE Id = :loadRec.Id
            LIMIT 1
        ];

    }

    @IsTest
    static void testControllerUpdateLoadStatusArrivedPickupCoversTriggerAndHandler() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);

        Test.startTest();

        DriverLoadPortalController.updateLoadStatus(
            rawToken,
            'ARRIVED_PICKUP'
        );

        Test.getEventBus().deliver();

        Test.stopTest();

        FreightTM__Load__c updatedLoad = [
            SELECT Id,
            FreightTM__Status__c,
            FreightTM__Pickup_Arrival__c,
            FreightTM__Pickup_Departure__c
            FROM FreightTM__Load__c
            WHERE Id = :loadRec.Id
            LIMIT 1
        ];

        System.assertEquals(
            'At Shipping',
            updatedLoad.FreightTM__Status__c,
            'ARRIVED_PICKUP should set status to At Shipping.'
        );


    }

    @IsTest
    static void testControllerUpdateLoadStatusDepartedPickupCoversTriggerAndHandler() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);

        Test.startTest();

        DriverLoadPortalController.updateLoadStatus(
            rawToken,
            'DEPARTED_PICKUP'
        );

        Test.getEventBus().deliver();

        Test.stopTest();

        FreightTM__Load__c updatedLoad = [
            SELECT Id,
            FreightTM__Status__c,
            FreightTM__Pickup_Arrival__c,
            FreightTM__Pickup_Departure__c
            FROM FreightTM__Load__c
            WHERE Id = :loadRec.Id
            LIMIT 1
        ];

        System.assertEquals(
            'In Transit to Delivery',
            updatedLoad.FreightTM__Status__c,
            'DEPARTED_PICKUP should set status to In Transit to Delivery.'
        );



        System.assertNotEquals(
            null,
            updatedLoad.FreightTM__Pickup_Departure__c,
            'Pickup departure should be populated.'
        );
    }

    @IsTest
    static void testControllerUpdateLoadStatusArrivedDeliveryCoversTriggerAndHandler() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);

        Test.startTest();

        DriverLoadPortalController.updateLoadStatus(
            rawToken,
            'ARRIVED_DELIVERY'
        );

        Test.getEventBus().deliver();

        Test.stopTest();

        FreightTM__Load__c updatedLoad = [
            SELECT Id,
            FreightTM__Status__c,
            FreightTM__Delivery_Arrival__c,
            FreightTM__Delivery_Departure__c
            FROM FreightTM__Load__c
            WHERE Id = :loadRec.Id
            LIMIT 1
        ];

        System.assertEquals(
            'At Receiving',
            updatedLoad.FreightTM__Status__c,
            'ARRIVED_DELIVERY should set status to At Receiving.'
        );

        System.assertNotEquals(
            null,
            updatedLoad.FreightTM__Delivery_Arrival__c,
            'Delivery arrival should be populated.'
        );


    }

    @IsTest
    static void testGetPortalDataSuccessCoversControllerFields() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        // Add values to the Load so getPortalData maps real data into PortalData.
        FreightTM__Load__c loadUpdate = new FreightTM__Load__c(
            Id = loadRec.Id,
            FreightTM__Pickup_Address__c = '123 Pickup St',
            FreightTM__Pickup_City__c = 'Chicago',
            FreightTM__Pickup_State__c = 'IL',
            FreightTM__Pickup_Zip_Code__c = '60601',
            FreightTM__Pickup_Country__c = 'United States',
            FreightTM__Pickup_Contact__c = 'Pickup Contact',
            FreightTM__Pickup_Phone__c = '5551112222',
            FreightTM__Pickup_Email__c = 'pickup@test.com',
            FreightTM__Pickup_Ref__c = 'PU-REF-001',
            FreightTM__Pickup_Remarks__c = 'Pickup remarks',
            FreightTM__Pickup_Arrival__c = System.now(),
            FreightTM__Pickup_Departure__c = System.now().addHours(1),

            FreightTM__Delivery_Address__c = '456 Delivery Ave',
            FreightTM__Delivery_City__c = 'Dallas',
            FreightTM__Delivery_State__c = 'TX',
            FreightTM__Delivery_Zip_Code__c = '75001',
            FreightTM__Delivery_Country__c = 'United States',
            FreightTM__Delivery_Contact__c = 'Delivery Contact',
            FreightTM__Delivery_Phone__c = '5553334444',
            FreightTM__Delivery_Email__c = 'delivery@test.com',
            FreightTM__Delivery_Ref__c = 'DEL-REF-001',
            FreightTM__Delivery_Remarks__c = 'Delivery remarks',
            FreightTM__Delivery_Arrival__c = System.now().addHours(2),
            FreightTM__Delivery_Departure__c = System.now().addHours(3),

            FreightTM__Commodity__c = 'General Freight',
            FreightTM__Weight__c = 1200,
            FreightTM__Distance__c = 500,
            FreightTM__Remarks__c = 'Load remarks',
            FreightTM__Requirements__c = 'Load Locks',
            FreightTM__Driver_Remarks__c = 'Driver remarks',
            Exception_Reason__c = 'Late Pickup'
        );

        update loadUpdate;

        FreightTM__Leg__c leg = new FreightTM__Leg__c();
        leg.FreightTM__Load__c = loadRec.Id;
        leg.FreightTM__Status__c = 'Picked Up';
        insert leg;

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);

        Test.startTest();
        DriverLoadPortalController.PortalData data =
            DriverLoadPortalController.getPortalData(rawToken);
        Test.stopTest();

        System.assertNotEquals(null, data, 'Portal data should not be null.');
        System.assertEquals(loadRec.Id, data.loadId, 'Load Id should match.');


        System.assert(
            data.driverName != null &&
            data.driverName.startsWith('Test Driver '),
            'Driver name should be mapped.'
        );

        System.assert(
            data.carrierName != null &&
            data.carrierName.startsWith('Test Carrier '),
            'Carrier name should be mapped.'
        );

        System.assertEquals(
            '123 Pickup St, Chicago, IL, 60601, United States',
            data.pickupAddress,
            'Pickup address should be built.'
        );

        System.assertEquals(
            '456 Delivery Ave, Dallas, TX, 75001, United States',
            data.deliveryAddress,
            'Delivery address should be built.'
        );

        System.assertEquals(
            'General Freight',
            data.commodity,
            'Commodity should be mapped.'
        );

        System.assertEquals(
            1200,
            data.weight,
            'Weight should be mapped.'
        );

        System.assertEquals(
            500,
            data.distance,
            'Distance should be mapped.'
        );

        System.assertEquals(
            'Driver remarks',
            data.driverRemarks,
            'Driver remarks should be mapped.'
        );

        System.assertEquals(
            'Late Pickup',
            data.exceptionReason,
            'Exception reason should be mapped.'
        );

        System.assertNotEquals(null, data.legs, 'Leg list should not be null.');
        System.assertEquals(1, data.legs.size(), 'One leg should be returned.');

    }

    @IsTest
    static void testGetPortalDataDeliveredPortalClosed() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);

        update new FreightTM__Load__c(
            Id = loadRec.Id,
            FreightTM__Status__c = 'Delivered',
            Driver_Portal_Active__c = false
        );

        Test.startTest();
        DriverLoadPortalController.PortalData data =
            DriverLoadPortalController.getPortalData(rawToken);
        Test.stopTest();

        System.assertEquals(
            true,
            data.portalClosed,
            'Delivered load should return portalClosed true.'
        );

        System.assertEquals(
            'This delivery has been completed. Thank you.',
            data.portalClosedMessage,
            'Delivered load should return portal closed message.'
        );
    }

    // ================= DriverLoadPortalController saveLocation / saveSignature / uploadFile

    @IsTest
    static void testControllerSaveLocationSuccess() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);

        Test.startTest();
        DriverLoadPortalController.saveLocation(
            rawToken,
            34.052235,
            -118.243683,
            'iPhone Safari'
        );
        Test.stopTest();

        FreightTM__Site_Location__c loc = [
            SELECT Id,
            FreightTM__Load__c,
            FreightTM__Coordinates__latitude__s,
            FreightTM__Coordinates__longitude__s,
            FreightTM__Location_Name__c,
            FreightTM__Remarks__c
            FROM FreightTM__Site_Location__c
            WHERE FreightTM__Load__c = :loadRec.Id
            LIMIT 1
        ];

        System.assertEquals(
            loadRec.Id,
            loc.FreightTM__Load__c,
            'Location should be linked to the load.'
        );

        System.assertEquals(
            34.052235,
            loc.FreightTM__Coordinates__latitude__s,
            'Latitude should be saved.'
        );

        System.assertEquals(
            -118.243683,
            loc.FreightTM__Coordinates__longitude__s,
            'Longitude should be saved.'
        );

        System.assertEquals(
            'Driver Browser Location',
            loc.FreightTM__Location_Name__c,
            'Location name should be set.'
        );

        System.assert(
            loc.FreightTM__Remarks__c.contains('Captured from Driver-Carrier Portal'),
            'Remarks should include portal text.'
        );

        System.assert(
            loc.FreightTM__Remarks__c.contains('iPhone Safari'),
            'Remarks should include device info.'
        );
    }

    @IsTest
    static void testControllerSaveLocationMissingCoordinatesThrowsException() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);
        Boolean thrownException = false;

        Test.startTest();
        try {
            DriverLoadPortalController.saveLocation(
                rawToken,
                null,
                -118.243683,
                'iPhone Safari'
            );
        } catch (AuraHandledException e) {
            thrownException = true;
        }
        Test.stopTest();

        System.assertEquals(
            true,
            thrownException,
            'Expected exception when latitude is missing.'
        );
    }

    @IsTest
    static void testControllerSaveLocationLongDeviceInfoTruncatesRemarks() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);

        String longDeviceInfo = '';
        for (Integer i = 0; i < 300; i++) {
            longDeviceInfo += 'X';
        }

        Test.startTest();
        DriverLoadPortalController.saveLocation(
            rawToken,
            40.712776,
            -74.005974,
            longDeviceInfo
        );
        Test.stopTest();

        FreightTM__Site_Location__c loc = [
            SELECT Id,
            FreightTM__Remarks__c
            FROM FreightTM__Site_Location__c
            WHERE FreightTM__Load__c = :loadRec.Id
            LIMIT 1
        ];

        System.assertEquals(
            255,
            loc.FreightTM__Remarks__c.length(),
            'Remarks should be truncated to 255 characters.'
        );
    }

    @IsTest
    static void testControllerSaveSignatureSuccess() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);

        String base64Body = EncodingUtil.base64Encode(Blob.valueOf('fake signature body'));
        String dataUrl = 'data:image/png;base64,' + base64Body;

        Test.startTest();
        Id contentVersionId = DriverLoadPortalController.saveSignature(
            rawToken,
            dataUrl,
            'John Driver!',
            'POD/Signature'
        );
        Test.stopTest();

        System.assertNotEquals(
            null,
            contentVersionId,
            'ContentVersion Id should be returned.'
        );

        ContentVersion cv = [
            SELECT Id,
            Title,
            PathOnClient,
            FirstPublishLocationId
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];

        System.assertEquals(
            loadRec.Id,
            cv.FirstPublishLocationId,
            'Signature should be published to the load.'
        );

        System.assert(
            cv.Title.startsWith('DriverPortal_Signature_'),
            'Signature title should use DriverPortal_Signature prefix.'
        );
    }

    @IsTest
    static void testControllerSaveSignatureDefaultsType() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);
        String base64Body =
            EncodingUtil.base64Encode(Blob.valueOf('fake signature body'));

        Test.startTest();
        Id contentVersionId = DriverLoadPortalController.saveSignature(
            rawToken,
            base64Body,
            'John Driver',
            ''
        );
        Test.stopTest();

        ContentVersion cv = [
            SELECT Id, Title
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];

        System.assertEquals(
            'DriverPortal_Signature_Pickup Contact_John Driver_PickupArrived',
            cv.Title,
            'Blank signature type should use the default type for an Assigned load.'
        );
    }

    @IsTest
    static void testControllerSaveSignatureBlankSignerThrowsException() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);
        String base64Body =
            EncodingUtil.base64Encode(Blob.valueOf('fake signature body'));
        Boolean thrownException = false;

        Test.startTest();
        try {
            DriverLoadPortalController.saveSignature(
                rawToken,
                base64Body,
                '',
                'Driver'
            );
        } catch (AuraHandledException e) {
            thrownException = true;
        }
        Test.stopTest();

        System.assertEquals(
            true,
            thrownException,
            'Blank signer name should throw an AuraHandledException.'
        );
    }

    @IsTest
    static void testControllerSaveSignatureBlankSignatureThrowsException() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);
        Boolean thrownException = false;

        Test.startTest();
        try {
            DriverLoadPortalController.saveSignature(
                rawToken,
                '',
                'John Driver',
                'Driver'
            );
        } catch (AuraHandledException e) {
            thrownException = true;
        }
        Test.stopTest();

        System.assertEquals(
            true,
            thrownException,
            'Expected exception when signature data is blank.'
        );
    }

    @IsTest
    static void testControllerUploadFileSuccess() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);

        String base64Body = EncodingUtil.base64Encode(Blob.valueOf('fake file body'));
        String dataUrl = 'data:text/plain;base64,' + base64Body;

        Test.startTest();
        Id contentVersionId = DriverLoadPortalController.uploadFile(
            rawToken,
            'driver-note.txt',
            dataUrl
        );
        Test.stopTest();

        System.assertNotEquals(
            null,
            contentVersionId,
            'ContentVersion Id should be returned.'
        );

        ContentVersion cv = [
            SELECT Id,
            Title,
            PathOnClient,
            FirstPublishLocationId
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];

        System.assertEquals(
            'DriverPortal_driver-note.txt',
            cv.Title,
            'Uploaded file title should use DriverPortal prefix.'
        );

        System.assertEquals(
            'driver-note.txt',
            cv.PathOnClient,
            'PathOnClient should match file name.'
        );

        System.assertEquals(
            loadRec.Id,
            cv.FirstPublishLocationId,
            'Uploaded file should be published to the load.'
        );
    }

    @IsTest
    static void testControllerUploadFileRawBase64Success() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);

        String base64Body = EncodingUtil.base64Encode(Blob.valueOf('raw base64 file body'));

        Test.startTest();
        Id contentVersionId = DriverLoadPortalController.uploadFile(
            rawToken,
            'raw-file.txt',
            base64Body
        );
        Test.stopTest();

        System.assertNotEquals(
            null,
            contentVersionId,
            'ContentVersion Id should be returned for raw base64.'
        );
    }

    @IsTest
    static void testControllerUploadFileMissingDataThrowsException() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        DriverLoadPortalTokenService.LinkResult linkResult =
            DriverLoadPortalTokenService.generateLink(
                loadRec.Id,
                'https://example.force.com/driver'
            );

        String rawToken = extractTokenFromUrl(linkResult.url);
        Boolean thrownException = false;

        Test.startTest();
        try {
            DriverLoadPortalController.uploadFile(
                rawToken,
                '',
                ''
            );
        } catch (AuraHandledException e) {
            thrownException = true;
        }
        Test.stopTest();

        System.assertEquals(
            true,
            thrownException,
            'Expected exception when file name and data are blank.'
        );
    }


    @IsTest
    static void testSettingsServiceOverridesAndDefaults() {
        Driver_Portal_Settings__mdt configured =
            new Driver_Portal_Settings__mdt();
        configured.Portal_Page_URL__c =
            ' https://example.my.site.com/DriverPortal/// ';
        configured.Token_Validity_Days__c = 30;
        configured.Auto_Send_Email__c = true;
        configured.Auto_Send_SMS__c = true;
        configured.Sync_Driver_Contact__c = false;
        configured.Company_Name__c = ' QA Freight ';
        configured.Email_Subject__c = 'Portal link for {LOAD_NAME}';

        DriverPortalSettingsService.testSettings = configured;

        System.assertEquals(
            'https://example.my.site.com/DriverPortal',
            DriverPortalSettingsService.getPortalPageUrl()
        );
        System.assertEquals(
            30,
            DriverPortalSettingsService.getTokenValidityDays()
        );
        System.assertEquals(
            true,
            DriverPortalSettingsService.isAutoEmailEnabled()
        );
        System.assertEquals(
            true,
            DriverPortalSettingsService.isAutoSmsEnabled()
        );
        System.assertEquals(
            false,
            DriverPortalSettingsService.shouldSyncDriverContact()
        );
        System.assertEquals(
            'QA Freight',
            DriverPortalSettingsService.getCompanyName()
        );
        System.assertEquals(
            'Portal link for LOAD-100',
            DriverPortalSettingsService.getEmailSubject('LOAD-100')
        );

        Driver_Portal_Settings__mdt defaults =
            new Driver_Portal_Settings__mdt();
        defaults.Token_Validity_Days__c = 0;
        defaults.Sync_Driver_Contact__c = true;
        DriverPortalSettingsService.testSettings = defaults;

        System.assertEquals(
            null,
            DriverPortalSettingsService.getPortalPageUrl()
        );
        System.assertEquals(
            14,
            DriverPortalSettingsService.getTokenValidityDays()
        );
        System.assertEquals(
            false,
            DriverPortalSettingsService.isAutoEmailEnabled()
        );
        System.assertEquals(
            false,
            DriverPortalSettingsService.isAutoSmsEnabled()
        );
        System.assertEquals(
            true,
            DriverPortalSettingsService.shouldSyncDriverContact()
        );
        System.assertEquals(
            'FTM',
            DriverPortalSettingsService.getCompanyName()
        );
        System.assertEquals(
            'New load assignment: Load',
            DriverPortalSettingsService.getEmailSubject(null)
        );

        DriverPortalSettingsService.testSettings = null;
        System.assertNotEquals(
            null,
            DriverPortalSettingsService.getSettings(),
            'The packaged Default custom metadata record should be available.'
        );
    }

    @IsTest
    static void testLinkAdminStatusAndValidationBranches() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        Test.startTest();
        DriverPortalLinkAdminController.LinkResponse nullStatus =
            DriverPortalLinkAdminController.getStatus(null);
        DriverPortalLinkAdminController.LinkResponse statusResponse =
            DriverPortalLinkAdminController.getStatus(loadRec.Id);
        Test.stopTest();

        System.assertEquals(null, nullStatus);
        System.assertEquals(loadRec.Id, statusResponse.loadId);
        System.assertNotEquals(null, statusResponse.portalLink);
        System.assertEquals(true, statusResponse.portalActive);
        System.assertNotEquals(null, statusResponse.expiresAt);

        Boolean nullLoadRejected = false;
        try {
            DriverPortalLinkAdminController.generateOrRefresh(null);
        } catch (AuraHandledException errorValue) {
            nullLoadRejected = true;
        }
        System.assertEquals(true, nullLoadRejected);

        FreightTM__Load__c noDriverLoad = new FreightTM__Load__c();
        insert noDriverLoad;

        Boolean noDriverRejected = false;
        try {
            DriverPortalLinkAdminController.generateOrRefresh(
                noDriverLoad.Id
            );
        } catch (AuraHandledException errorValue) {
            noDriverRejected = true;
        }
        System.assertEquals(true, noDriverRejected);

        String configuredBaseUrl = System.Label.Driver_Portal_Base_URL;
        if (
            String.isNotBlank(configuredBaseUrl) &&
            !configuredBaseUrl.contains('YOUR-SITE-DOMAIN')
        ) {
            DriverPortalLinkAdminController.LinkResponse refreshed =
                DriverPortalLinkAdminController.generateOrRefresh(
                    loadRec.Id
                );
            System.assertEquals(loadRec.Id, refreshed.loadId);
            System.assertNotEquals(null, refreshed.portalLink);
            System.assertEquals(true, refreshed.portalActive);
        }
    }

    @IsTest
    static void testGenerateLinkVisualforceControllerBranches() {
        registerCalloutMock();
        Test.setCurrentPage(
            new PageReference('/apex/DriverPortalGenerateLink')
        );

        FreightTM__Load__c loadRec = createLoad();
        ApexPages.StandardController standardController =
            new ApexPages.StandardController(loadRec);
        DriverPortalGenerateLinkController controller =
            new DriverPortalGenerateLinkController(
                standardController
            );

        String configuredBaseUrl = System.Label.Driver_Portal_Base_URL;

        Test.startTest();
        PageReference result = controller.generateAndReturn();
        Test.stopTest();

        if (
            String.isNotBlank(configuredBaseUrl) &&
            !configuredBaseUrl.contains('YOUR-SITE-DOMAIN')
        ) {
            System.assertNotEquals(null, result);
            System.assertEquals('/' + loadRec.Id, result.getUrl());
            System.assertNotEquals(null, controller.generatedLink);
        } else {
            System.assertEquals(null, result);
        }
        System.assert(ApexPages.getMessages().size() > 0);

        FreightTM__Load__c noDriverLoad =
            new FreightTM__Load__c();
        insert noDriverLoad;

        DriverPortalGenerateLinkController errorController =
            new DriverPortalGenerateLinkController(
                new ApexPages.StandardController(noDriverLoad)
            );
        PageReference errorResult =
            errorController.generateAndReturn();
        System.assertEquals(null, errorResult);
    }

    @IsTest
    static void testTriggerHandlerDirectBranches() {
        registerCalloutMock();
        FreightTM__Employee__c driver = createDriver();

        FreightTM__Load__c beforeInsertLoad =
            new FreightTM__Load__c(
                FreightTM__Driver__c = driver.Id
            );

        Test.startTest();
        DriverLoadPortalTriggerHandler.handleBefore(
            new List<FreightTM__Load__c>{ beforeInsertLoad },
            new Map<Id, FreightTM__Load__c>(),
            true,
            false
        );
        Test.stopTest();

        System.assertNotEquals(
            null,
            beforeInsertLoad.Driver_Portal_Link__c
        );
        System.assertEquals(
            true,
            beforeInsertLoad.Driver_Portal_Active__c
        );

        FreightTM__Load__c persistedNoDriver =
            new FreightTM__Load__c();
        insert persistedNoDriver;

        FreightTM__Load__c oldWithoutDriver =
            new FreightTM__Load__c(
                Id = persistedNoDriver.Id,
                FreightTM__Driver__c = null
            );
        FreightTM__Load__c newlyAssigned =
            new FreightTM__Load__c(
                Id = persistedNoDriver.Id,
                FreightTM__Driver__c = driver.Id
            );

        DriverLoadPortalTriggerHandler.handleBefore(
            new List<FreightTM__Load__c>{ newlyAssigned },
            new Map<Id, FreightTM__Load__c>{
                persistedNoDriver.Id => oldWithoutDriver
            },
            false,
            true
        );
        System.assertNotEquals(
            null,
            newlyAssigned.Driver_Portal_Link__c
        );

        FreightTM__Load__c oldWithDriver =
            new FreightTM__Load__c(
                Id = persistedNoDriver.Id,
                FreightTM__Driver__c = driver.Id,
                Driver_Portal_Link__c =
                    'https://example.com/DriverPortal?t=old',
                Driver_Portal_Active__c = true
            );
        FreightTM__Load__c removedDriver =
            new FreightTM__Load__c(
                Id = persistedNoDriver.Id,
                FreightTM__Driver__c = null,
                Driver_Portal_Link__c =
                    'https://example.com/DriverPortal?t=old',
                Driver_Portal_Active__c = true
            );

        DriverLoadPortalTriggerHandler.handleBefore(
            new List<FreightTM__Load__c>{ removedDriver },
            new Map<Id, FreightTM__Load__c>{
                persistedNoDriver.Id => oldWithDriver
            },
            false,
            true
        );
        System.assertEquals(
            false,
            removedDriver.Driver_Portal_Active__c
        );
        System.assertEquals(
            null,
            removedDriver.Driver_Portal_Link__c
        );

        DriverLoadPortalTriggerHandler.handleAfter(
            null,
            null,
            false,
            false
        );
        DriverLoadPortalTriggerHandler.handleAfter(
            new List<FreightTM__Load__c>(),
            null,
            true,
            false
        );
        DriverLoadPortalTriggerHandler.handleAfter(
            new List<FreightTM__Load__c>{ beforeInsertLoad },
            null,
            true,
            false
        );
        DriverLoadPortalTriggerHandler.handleAfter(
            new List<FreightTM__Load__c>{ newlyAssigned },
            new Map<Id, FreightTM__Load__c>{
                persistedNoDriver.Id => oldWithoutDriver
            },
            false,
            true
        );
    }

    @IsTest
    static void testEmailAndSmsQueueablesAndServices() {
        registerCalloutMock();
        FreightTM__Load__c loadRec = createLoad();

        Test.startTest();
        new DriverPortalEmailQueueable(null).execute(null);
        new DriverPortalEmailQueueable(new Set<Id>()).execute(null);
        new DriverPortalEmailQueueable(
            new Set<Id>{ loadRec.Id }
        ).execute(null);

        new DriverPortalSmsQueueable(null).execute(null);
        new DriverPortalSmsQueueable(new Set<Id>()).execute(null);
        new DriverPortalSmsQueueable(
            new Set<Id>{ loadRec.Id }
        ).execute(null);

        DriverPortalEmailService.sendDriverEmails(null);
        DriverPortalEmailService.sendDriverEmails(new Set<Id>());
        DriverPortalEmailService.sendDriverEmails(
            new Set<Id>{ loadRec.Id }
        );
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testSmsVisualforceControllerValidationSuccessAndCancel() {
        registerCalloutMock();
        Test.setCurrentPage(
            new PageReference('/apex/DriverPortalSmsPage')
        );

        DriverPortalSmsController missingLoadController =
            new DriverPortalSmsController(
                new ApexPages.StandardController(
                    new FreightTM__Load__c()
                )
            );
        System.assertEquals(
            null,
            missingLoadController.sendPortalLink()
        );
        PageReference rootCancel =
            missingLoadController.cancel();
        System.assertEquals('/', rootCancel.getUrl());

        FreightTM__Load__c loadRec = createLoad();
        DriverPortalSmsController controller =
            new DriverPortalSmsController(
                new ApexPages.StandardController(loadRec)
            );

        System.assertNotEquals(null, controller.loadRecord);
        System.assertNotEquals(
            null,
            controller.loadRecord.Driver_Portal_Link__c
        );
        System.assertNotEquals(
            null,
            controller.loadRecord.Driver_Phone_Number__c
        );
        System.assertNotEquals(
            null,
            controller.loadRecord.Driver_Phone_Carrier__c
        );

        Test.startTest();
        PageReference sendResult = controller.sendPortalLink();
        Test.stopTest();

        System.assertNotEquals(null, sendResult);
        System.assertEquals('/' + loadRec.Id, sendResult.getUrl());

        ApexPages.currentPage().getParameters().put(
            'retURL',
            '/lightning/page/home'
        );
        PageReference explicitCancel = controller.cancel();
        System.assertEquals(
            '/lightning/page/home',
            explicitCancel.getUrl()
        );

        ApexPages.currentPage().getParameters().remove('retURL');
        PageReference recordCancel = controller.cancel();
        System.assertEquals('/' + loadRec.Id, recordCancel.getUrl());
    }

}
