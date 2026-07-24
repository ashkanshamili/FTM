@IsTest
private class AutoFillWebhookCompatibilityTest {

    private static final Long TEST_TIMESTAMP = 1784286000L;
    private static final String TEST_SECRET =
        'autofill-webhook-compatibility-secret';

    @IsTest
    static void adapterNormalizesLegacyV1PascalCasePayload() {
        Map<String, Object> rawPayload = new Map<String, Object>{
            'Success' => true,
            'LoadDetails' => new Map<String, Object>{
                'LoadId' => 'legacy-load-001',
                'Origin' => 'Dallas',
                'Destination' => 'Houston',
                'Weight' => 1200,
                'EquipmentType' => 'Van',
                'PickupDate' => '2026-07-17',
                'DeliveryDate' => '2026-07-18',
                'ConfirmationNumber' => 'CONF-001'
            }
        };

        Map<String, Object> normalized =
            AutoFillWebhookPayloadAdapter.normalize(rawPayload);

        System.assertEquals(
            'FreightTM__Load__c',
            normalized.get('SalesforceObjectType')
        );

        Map<String, Object> fields = (Map<String, Object>)
            normalized.get('ExtractedFields');

        System.assertEquals(
            'Dallas',
            fields.get('FreightTM__Pickup_City__c')
        );
        System.assertEquals(
            'Houston',
            fields.get('FreightTM__Delivery_City__c')
        );
        System.assertEquals(
            'Van',
            fields.get('FreightTM__Required_Trailer__c')
        );
        System.assertEquals('legacy-load-001', normalized.get('ItemId'));
        System.assertEquals('Webhook', normalized.get('AutoFillSource'));
    }

    @IsTest
    static void adapterNormalizesWrappedV2PayloadWithoutObjectName() {
        Map<String, Object> rawPayload = new Map<String, Object>{
            'event' => 'extraction.completed',
            'data' => new Map<String, Object>{
                'Success' => true,
                'ItemId' => 'v2-item-001',
                'Metadata' => new Map<String, Object>{
                    'pipeline' => 'v2'
                },
                'ExtractedFields' => new Map<String, Object>{
                    'Pickup City' => 'Phoenix',
                    'Delivery City' => 'Tucson'
                }
            }
        };

        Map<String, Object> normalized =
            AutoFillWebhookPayloadAdapter.normalize(rawPayload);

        System.assertEquals(
            'FreightTM__Load__c',
            normalized.get('SalesforceObjectType')
        );
        System.assertEquals('v2-item-001', normalized.get('ItemId'));

        Map<String, Object> fields = (Map<String, Object>)
            normalized.get('ExtractedFields');
        System.assertEquals('Phoenix', fields.get('Pickup City'));
        System.assertEquals('Tucson', fields.get('Delivery City'));
    }

    @IsTest
    static void adapterKeepsExplicitGenericObject() {
        Map<String, Object> normalized =
            AutoFillWebhookPayloadAdapter.normalize(
                new Map<String, Object>{
                    'Success' => true,
                    'SalesforceObjectType' => 'Task',
                    'ExtractedFields' => new Map<String, Object>{
                        'Subject' => 'Generic webhook task'
                    }
                }
            );

        System.assertEquals(
            'Task',
            normalized.get('SalesforceObjectType')
        );
    }

    @IsTest
    static void compatibleAuthenticatorAcceptsBase64SignatureAndMilliseconds() {
        String body = '{"test":true}';
        String timestamp = String.valueOf(TEST_TIMESTAMP * 1000);
        Blob mac = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(timestamp + '.' + body),
            Blob.valueOf(TEST_SECRET)
        );

        RestRequest request = new RestRequest();
        request.requestUri =
            '/services/apexrest/freightgraph/autofill-email-extraction';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(body);
        request.addHeader(
            'X-Webhook-Timestamp',
            timestamp
        );
        request.addHeader(
            'X-Webhook-Signature',
            EncodingUtil.base64Encode(mac)
        );
        request.addHeader(
            'X-Request-Id',
            'compat-delivery-001'
        );

        AutoFillWebhookAuthenticator.testSecret = TEST_SECRET;
        AutoFillWebhookAuthenticator.testReplayWindow = 300;
        AutoFillWebhookAuthenticator.testCurrentTimestamp =
            TEST_TIMESTAMP;

        AutoFillWebhookAuthenticator.AuthenticationResult result =
            AutoFillWebhookAuthenticator.authenticateWebhook(
                request,
                body
            );

        System.assertEquals(true, result.valid, result.message);
        System.assertEquals('AUTHENTICATED', result.code);
        System.assertEquals(
            'compat-delivery-001',
            result.deliveryId
        );
    }

    @IsTest
    static void v2WebhookCreatesDraftLoadFromWrappedPayload() {
        Map<String, Object> payload = new Map<String, Object>{
            'event' => 'extraction.completed',
            'data' => new Map<String, Object>{
                'Success' => true,
                'ItemId' => 'webhook-v2-draft-001',
                'Metadata' => new Map<String, Object>{
                    'pipeline' => 'v2'
                },
                'ExtractedFields' => new Map<String, Object>{
                    'FreightTM__Pickup_City__c' => 'Mesa',
                    'FreightTM__Delivery_City__c' => 'Tempe',
                    'FreightTM__Pickup_Date__c' =>
                        String.valueOf(Date.today()),
                    'FreightTM__Delivery_Date__c' =>
                        String.valueOf(Date.today().addDays(1))
                }
            }
        };

        String body = JSON.serialize(payload);
        String timestamp = String.valueOf(TEST_TIMESTAMP);
        Blob mac = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(timestamp + '.' + body),
            Blob.valueOf(TEST_SECRET)
        );

        RestRequest request = new RestRequest();
        request.requestUri =
            '/services/apexrest/freightgraph/autofill-email-extraction';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(body);
        request.addHeader(
            'X-FreightGraph-Timestamp',
            timestamp
        );
        request.addHeader(
            'X-FreightGraph-Signature',
            'sha256=' +
            EncodingUtil.convertToHex(mac).toLowerCase()
        );
        request.addHeader(
            'X-FreightGraph-Delivery-Id',
            'webhook-v2-delivery-001'
        );

        AutoFillWebhookAuthenticator.testSecret = TEST_SECRET;
        AutoFillWebhookAuthenticator.testReplayWindow = 300;
        AutoFillWebhookAuthenticator.testCurrentTimestamp =
            TEST_TIMESTAMP;
        RestContext.request = request;
        RestContext.response = new RestResponse();
        Test.setMock(
            HttpCalloutMock.class,
            new AutoFillTestCalloutMock()
        );

        Test.startTest();
        AutoFillWebhook.WebhookResponse webhookResult =
            AutoFillWebhook.handlePost();
        Test.stopTest();

        System.assertEquals(true, webhookResult.success, webhookResult.message);
        System.assertNotEquals(null, webhookResult.recordId);
        System.assertEquals(201, RestContext.response.statusCode);

        Id createdLoadId = webhookResult.recordId;
        SObject createdLoad = Database.query(
            'SELECT Id, AutoFill_Status__c, AutoFill_Source__c ' +
            'FROM FreightTM__Load__c ' +
            'WHERE Id = :createdLoadId'
        );

        System.assertEquals('Draft', createdLoad.get('AutoFill_Status__c'));
        System.assert(
            AutoFillRecordEmailNotifier.isWebhookSource(
                String.valueOf(createdLoad.get('AutoFill_Source__c'))
            ),
            'Expected an Email/Webhook source but found: ' +
            String.valueOf(createdLoad.get('AutoFill_Source__c'))
        );
    }

    @IsTest
    static void directV2WebhookWithNullObjectTypeCreatesDraftLoad() {
        Map<String, Object> payload = new Map<String, Object>{
            'Success' => true,
            'SalesforceObjectType' => null,
            'ItemId' => 'webhook-v2-direct-null-object-001',
            'Metadata' => new Map<String, Object>{
                'pipeline' => 'v2'
            },
            'ExtractedFields' => new Map<String, Object>{
                'Pickup City' => 'Newark',
                'Pickup State/Province' => 'NJ',
                'Delivery City' => 'Baltimore',
                'Delivery State/Province' => 'MD',
                'Pickup Date' => String.valueOf(Date.today()),
                'Delivery Date' => String.valueOf(Date.today().addDays(1))
            }
        };

        String body = JSON.serialize(payload);
        String timestamp = String.valueOf(TEST_TIMESTAMP);
        Blob mac = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(timestamp + '.' + body),
            Blob.valueOf(TEST_SECRET)
        );

        RestRequest request = new RestRequest();
        request.requestUri =
            '/services/apexrest/freightgraph/autofill-email-extraction';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(body);
        request.addHeader(
            'X-FreightGraph-Timestamp',
            timestamp
        );
        request.addHeader(
            'X-FreightGraph-Signature',
            'sha256=' +
            EncodingUtil.convertToHex(mac).toLowerCase()
        );
        request.addHeader(
            'X-FreightGraph-Delivery-Id',
            'webhook-v2-direct-null-object-delivery-001'
        );

        AutoFillWebhookAuthenticator.testSecret = TEST_SECRET;
        AutoFillWebhookAuthenticator.testReplayWindow = 300;
        AutoFillWebhookAuthenticator.testCurrentTimestamp =
            TEST_TIMESTAMP;
        RestContext.request = request;
        RestContext.response = new RestResponse();
        Test.setMock(
            HttpCalloutMock.class,
            new AutoFillTestCalloutMock()
        );

        Test.startTest();
        AutoFillWebhook.WebhookResponse webhookResult =
            AutoFillWebhook.handlePost();
        Test.stopTest();

        System.assertEquals(true, webhookResult.success, webhookResult.message);
        System.assertNotEquals(null, webhookResult.recordId);
        System.assertEquals(201, RestContext.response.statusCode);
        System.assertEquals(
            FreightTM__Load__c.SObjectType,
            webhookResult.recordId.getSObjectType()
        );
    }

    @IsTest
    static void directWebhookAddsEmailSourceWhenSourceIsMissing() {
        Map<String, Object> payload = new Map<String, Object>{
            'Success' => true,
            'SalesforceObjectType' => 'FreightTM__Load__c',
            'ItemId' => 'webhook-direct-source-001',
            'ExtractedFields' => new Map<String, Object>{
                'FreightTM__Pickup_City__c' => 'Chicago',
                'FreightTM__Delivery_City__c' => 'Detroit',
                'FreightTM__Pickup_Date__c' =>
                    String.valueOf(Date.today()),
                'FreightTM__Delivery_Date__c' =>
                    String.valueOf(Date.today().addDays(1))
            }
        };

        String body = JSON.serialize(payload);
        String timestamp = String.valueOf(TEST_TIMESTAMP);
        Blob mac = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(timestamp + '.' + body),
            Blob.valueOf(TEST_SECRET)
        );

        RestRequest request = new RestRequest();
        request.requestUri =
            '/services/apexrest/freightgraph/autofill-email-extraction';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(body);
        request.addHeader('X-FreightGraph-Timestamp', timestamp);
        request.addHeader(
            'X-FreightGraph-Signature',
            'sha256=' + EncodingUtil.convertToHex(mac).toLowerCase()
        );
        request.addHeader(
            'X-FreightGraph-Delivery-Id',
            'webhook-direct-source-delivery-001'
        );

        AutoFillWebhookAuthenticator.testSecret = TEST_SECRET;
        AutoFillWebhookAuthenticator.testReplayWindow = 300;
        AutoFillWebhookAuthenticator.testCurrentTimestamp = TEST_TIMESTAMP;
        RestContext.request = request;
        RestContext.response = new RestResponse();
        Test.setMock(
            HttpCalloutMock.class,
            new AutoFillTestCalloutMock()
        );

        Test.startTest();
        AutoFillWebhook.WebhookResponse webhookResult =
            AutoFillWebhook.handlePost();
        Test.stopTest();

        System.assertEquals(true, webhookResult.success, webhookResult.message);
        Id createdLoadId = webhookResult.recordId;
        SObject createdLoad = Database.query(
            'SELECT AutoFill_Source__c, AutoFill_Raw_Response__c ' +
            'FROM FreightTM__Load__c WHERE Id = :createdLoadId'
        );

        System.assert(
            AutoFillRecordEmailNotifier.isWebhookSource(
                String.valueOf(createdLoad.get('AutoFill_Source__c'))
            ),
            'Expected an Email/Webhook source but found: ' +
            String.valueOf(createdLoad.get('AutoFill_Source__c'))
        );
        String rawResponse = String.valueOf(
            createdLoad.get('AutoFill_Raw_Response__c')
        );
        System.assert(
            rawResponse.contains('"AutoFillSource":"Webhook"'),
            rawResponse
        );
    }

    @IsTest
    static void unifiedWebhookAcceptsLegacyPascalCasePayload() {
        String body = JSON.serialize(
            new Map<String, Object>{
                'Success' => true,
                'LoadDetails' => new Map<String, Object>{
                    'LoadId' => 'webhook-v1-draft-001',
                    'Origin' => 'Austin',
                    'Destination' => 'Waco',
                    'PickupDate' => String.valueOf(Date.today()),
                    'DeliveryDate' =>
                        String.valueOf(Date.today().addDays(1))
                }
            }
        );

        String timestamp = String.valueOf(TEST_TIMESTAMP);
        Blob mac = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(timestamp + '.' + body),
            Blob.valueOf(TEST_SECRET)
        );

        RestRequest request = new RestRequest();
        request.requestUri =
            '/services/apexrest/freightgraph/autofill-email-extraction';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(body);
        request.addHeader('X-FreightGraph-Timestamp', timestamp);
        request.addHeader(
            'X-FreightGraph-Signature',
            'sha256=' + EncodingUtil.convertToHex(mac).toLowerCase()
        );
        request.addHeader(
            'X-FreightGraph-Delivery-Id',
            'webhook-v1-delivery-001'
        );

        AutoFillWebhookAuthenticator.testSecret = TEST_SECRET;
        AutoFillWebhookAuthenticator.testReplayWindow = 300;
        AutoFillWebhookAuthenticator.testCurrentTimestamp = TEST_TIMESTAMP;
        RestContext.request = request;
        RestContext.response = new RestResponse();
        Test.setMock(
            HttpCalloutMock.class,
            new AutoFillTestCalloutMock()
        );

        Test.startTest();
        AutoFillWebhook.WebhookResponse webhookResult =
            AutoFillWebhook.handlePost();
        Test.stopTest();

        System.assertEquals(true, webhookResult.success, webhookResult.message);
        System.assertNotEquals(null, webhookResult.recordId);
        Id createdLoadId = webhookResult.recordId;
        SObject createdLoad = Database.query(
            'SELECT Id, AutoFill_Status__c, AutoFill_Source__c, ' +
            'FreightTM__Pickup_City__c, FreightTM__Delivery_City__c ' +
            'FROM FreightTM__Load__c ' +
            'WHERE Id = :createdLoadId'
        );

        System.assertEquals('Draft', createdLoad.get('AutoFill_Status__c'));
        System.assert(
            AutoFillRecordEmailNotifier.isWebhookSource(
                String.valueOf(createdLoad.get('AutoFill_Source__c'))
            ),
            'Expected an Email/Webhook source but found: ' +
            String.valueOf(createdLoad.get('AutoFill_Source__c'))
        );
        System.assertEquals(
            'Austin',
            createdLoad.get('FreightTM__Pickup_City__c')
        );
        System.assertEquals(
            'Waco',
            createdLoad.get('FreightTM__Delivery_City__c')
        );
    }
}