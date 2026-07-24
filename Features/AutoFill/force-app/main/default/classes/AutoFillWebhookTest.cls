@IsTest
private class AutoFillWebhookTest {

    private static final String TEST_SECRET =
        'test-webhook-secret';
    private static final Long TEST_TIMESTAMP =
        1716292845L;

    private static AutoFillWebhook.WebhookResponse
        invokeWebhook(
            Object payload,
            String deliveryId
        ) {
        return invokeRawWebhook(
            JSON.serialize(payload),
            true,
            deliveryId
        );
    }

    private static AutoFillWebhook.WebhookResponse
        invokeRawWebhook(
            String body,
            Boolean includeSignature,
            String deliveryId
        ) {
        RestRequest request = new RestRequest();
        request.requestUri =
            '/services/apexrest/freightgraph/autofill-email-extraction';
        request.httpMethod = 'POST';

        if (body != null) {
            request.requestBody = Blob.valueOf(body);
        }

        AutoFillWebhookAuthenticator.testSecret =
            TEST_SECRET;
        AutoFillWebhookAuthenticator.testReplayWindow =
            300;
        AutoFillWebhookAuthenticator.testCurrentTimestamp =
            TEST_TIMESTAMP;

        if (includeSignature && body != null) {
            String timestamp = String.valueOf(TEST_TIMESTAMP);
            Blob hmac = Crypto.generateMac(
                'HmacSHA256',
                Blob.valueOf(timestamp + '.' + body),
                Blob.valueOf(TEST_SECRET)
            );

            request.addHeader(
                'X-FreightGraph-Timestamp',
                timestamp
            );
            request.addHeader(
                'X-FreightGraph-Signature',
                'sha256=' +
                EncodingUtil.convertToHex(hmac).toLowerCase()
            );
            request.addHeader(
                'X-FreightGraph-Delivery-Id',
                deliveryId
            );
        }

        RestContext.request = request;
        RestContext.response = new RestResponse();

        return AutoFillWebhook.handlePost();
    }

    private static Map<String, Object> buildTaskPayload(
        String subject
    ) {
        return new Map<String, Object>{
            'Success' => true,
            'SalesforceObjectType' => 'Task',
            'ExtractedFields' => new Map<String, Object>{
                'Subject' => subject,
                'Status' => 'Not Started',
                'Priority' => 'Normal',
                'Description' => 'Created by webhook unit test'
            }
        };
    }

    @IsTest
    static void handlePost_createsTaskAndReturnsCreated() {
        Test.startTest();
        AutoFillWebhook.WebhookResponse response =
            invokeWebhook(
                buildTaskPayload('Webhook Task'),
                'delivery-create-task'
            );
        Test.stopTest();

        System.assertEquals(
            201,
            RestContext.response.statusCode,
            response.message
        );
        System.assertEquals(true, response.success);
        System.assertEquals('CREATED', response.code);
        System.assertNotEquals(null, response.recordId);

        Task createdTask = [
            SELECT Subject, Status, Priority, Description
            FROM Task
            WHERE Id = :response.recordId
        ];

        System.assertEquals('Webhook Task', createdTask.Subject);
        System.assertEquals('Not Started', createdTask.Status);
        System.assertEquals('Normal', createdTask.Priority);
        System.assertEquals(
            'Created by webhook unit test',
            createdTask.Description
        );
    }

    @IsTest
    static void handlePost_savesReturnedEmailDocumentsForPreview() {
        Map<String, Object> payload =
            buildTaskPayload('Webhook Task With Source File');
        String fileBody = EncodingUtil.base64Encode(
            Blob.valueOf('Webhook PDF test content')
        );

        payload.put(
            'Documents',
            new List<Object>{
                new Map<String, Object>{
                    'FileName' => 'email-rate-confirmation.pdf',
                    'ContentType' => 'application/pdf',
                    'Base64Data' =>
                        'data:application/pdf;base64,' + fileBody
                }
            }
        );
        payload.put('ItemId', 'email-item-001');

        Test.startTest();
        AutoFillWebhook.WebhookResponse response =
            invokeWebhook(
                payload,
                'delivery-task-with-source-file'
            );
        Test.stopTest();

        System.assertEquals(true, response.success, response.message);
        System.assertEquals('CREATED', response.code);
        System.assertNotEquals(null, response.recordId);

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :response.recordId
        ];

        System.assertEquals(1, links.size());

        ContentVersion savedVersion = [
            SELECT Title,
                   FileType,
                   FileExtension,
                   Description,
                   VersionData
            FROM ContentVersion
            WHERE IsLatest = true
            AND ContentDocumentId = :links[0].ContentDocumentId
            LIMIT 1
        ];

        System.assertEquals(
            'email-rate-confirmation',
            savedVersion.Title
        );
        System.assertEquals('pdf', savedVersion.FileExtension);
        System.assert(
            savedVersion.Description.startsWith('AutoFill Upload')
        );
        System.assert(
            savedVersion.Description.contains('email-item-001')
        );
        System.assertEquals(
            'Webhook PDF test content',
            savedVersion.VersionData.toString()
        );

        List<AutoFillController.AutoFillFilePreviewRow> previews =
            AutoFillController.getLoadFilePreviews(response.recordId);

        System.assertEquals(1, previews.size());
        System.assertEquals(
            'email-rate-confirmation.pdf',
            previews[0].title
        );
        System.assertEquals(true, previews[0].isPdf);
    }

    @IsTest
    static void handlePost_doesNotDuplicateFilesOnWebhookRetry() {
        Map<String, Object> payload =
            buildTaskPayload('Idempotent Task With File');
        payload.put(
            'Attachments',
            new List<Object>{
                new Map<String, Object>{
                    'name' => 'source.png',
                    'mimeType' => 'image/png',
                    'fileContent' => EncodingUtil.base64Encode(
                        Blob.valueOf('PNG test content')
                    )
                }
            }
        );

        AutoFillWebhook.WebhookResponse first =
            invokeWebhook(
                payload,
                'delivery-idempotent-task-file'
            );
        AutoFillWebhook.WebhookResponse second =
            invokeWebhook(
                payload,
                'delivery-idempotent-task-file'
            );

        System.assertEquals(true, first.success, first.message);
        System.assertEquals(true, second.success, second.message);
        System.assertEquals(first.recordId, second.recordId);
        System.assertEquals('ALREADY_PROCESSED', second.code);

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :first.recordId
            ]
        );
    }

    @IsTest
    static void handlePost_reusesDeliveryIdempotently() {
        Map<String, Object> payload =
            buildTaskPayload('Idempotent Task');

        AutoFillWebhook.WebhookResponse first =
            invokeWebhook(
                payload,
                'delivery-idempotent-task'
            );

        AutoFillWebhook.WebhookResponse second =
            invokeWebhook(
                payload,
                'delivery-idempotent-task'
            );

        System.assertEquals(true, first.success, first.message);
        System.assertEquals(true, second.success, second.message);
        System.assertEquals(first.recordId, second.recordId);
        System.assertEquals('ALREADY_PROCESSED', second.code);
        System.assertEquals(200, RestContext.response.statusCode);
    }

    @IsTest
    static void handlePost_rejectsEmptyAndInvalidJson() {
        AutoFillWebhook.WebhookResponse emptyBody =
            invokeRawWebhook(
                null,
                false,
                'delivery-empty'
            );

        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(false, emptyBody.success);
        System.assertEquals('EMPTY_BODY', emptyBody.code);

        AutoFillWebhook.WebhookResponse invalidJson =
            invokeRawWebhook(
                '{invalid JSON',
                true,
                'delivery-invalid-json'
            );

        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(false, invalidJson.success);
        System.assertEquals('INVALID_JSON', invalidJson.code);
    }

    @IsTest
    static void handlePost_rejectsMissingAuthentication() {
        AutoFillWebhook.WebhookResponse response =
            invokeRawWebhook(
                JSON.serialize(
                    buildTaskPayload('Unsigned Task')
                ),
                false,
                'delivery-unsigned'
            );

        System.assertEquals(401, RestContext.response.statusCode);
        System.assertEquals(false, response.success);
        System.assertEquals('MISSING_SIGNATURE', response.code);
    }

    @IsTest
    static void handlePost_rejectsFailedExtractionAndMissingObject() {
        AutoFillWebhook.WebhookResponse failedExtraction =
            invokeWebhook(
                new Map<String, Object>{
                    'Success' => false,
                    'Message' => 'Document extraction failed'
                },
                'delivery-failed-extraction'
            );

        System.assertEquals(422, RestContext.response.statusCode);
        System.assertEquals(false, failedExtraction.success);
        System.assertEquals(
            'INVALID_PAYLOAD',
            failedExtraction.code
        );
        System.assert(
            failedExtraction.message.contains(
                'Document extraction failed'
            )
        );

        AutoFillWebhook.WebhookResponse missingObject =
            invokeWebhook(
                new Map<String, Object>{
                    'ExtractedFields' =>
                        new Map<String, Object>{
                            'Description' => 'Missing object type'
                        }
                },
                'delivery-missing-object'
            );

        System.assertEquals(422, RestContext.response.statusCode);
        System.assertEquals(false, missingObject.success);
        System.assertEquals('RECORD_CREATION_FAILED', missingObject.code);
        System.assert(
            missingObject.message.contains('parent Salesforce object')
        );
    }

    @IsTest
    static void autoFillService_createsTaskDirectly() {
        Map<String, Object> payload =
            buildTaskPayload('Direct Service Task');

        Test.startTest();
        AutoFillService.ProcessingResult result =
            AutoFillService.createFromExtractionPayloadWithStatus(
                    payload,
                    'direct-service-delivery'
                );
        Test.stopTest();

        System.assertEquals(true, result.created);
        System.assertNotEquals(null, result.recordId);
        System.assertEquals(
            Task.SObjectType,
            result.recordId.getSObjectType()
        );

        Task storedTask = [
            SELECT Subject, Description
            FROM Task
            WHERE Id = :result.recordId
        ];

        System.assertEquals(
            'Direct Service Task',
            storedTask.Subject
        );
        System.assertEquals(
            'Created by webhook unit test',
            storedTask.Description
        );
    }

    @IsTest
    static void authenticator_coversValidationFailures() {
        AutoFillWebhookAuthenticator.AuthenticationResult
            nullRequest =
                AutoFillWebhookAuthenticator.authenticate(
                    null,
                    '{}'
                );

        System.assertEquals(false, nullRequest.valid);
        System.assertEquals('INVALID_REQUEST', nullRequest.code);

        RestRequest missingHeaders = new RestRequest();

        AutoFillWebhookAuthenticator.AuthenticationResult
            missingSignature =
                AutoFillWebhookAuthenticator.authenticate(
                    missingHeaders,
                    '{}'
                );

        System.assertEquals(false, missingSignature.valid);
        System.assertEquals(
            'MISSING_SIGNATURE',
            missingSignature.code
        );

        RestRequest invalidPrefix = new RestRequest();
        invalidPrefix.addHeader(
            'X-FreightGraph-Timestamp',
            String.valueOf(TEST_TIMESTAMP)
        );
        invalidPrefix.addHeader(
            'X-FreightGraph-Signature',
            'not-sha256'
        );

        AutoFillWebhookAuthenticator.AuthenticationResult
            badPrefix =
                AutoFillWebhookAuthenticator.authenticate(
                    invalidPrefix,
                    '{}'
                );

        System.assertEquals(
            'INVALID_SIGNATURE_FORMAT',
            badPrefix.code
        );

        RestRequest invalidTimestamp = new RestRequest();
        invalidTimestamp.addHeader(
            'X-FreightGraph-Timestamp',
            'not-a-time'
        );
        invalidTimestamp.addHeader(
            'X-FreightGraph-Signature',
            'sha256=' +
            '00000000000000000000000000000000' +
            '00000000000000000000000000000000'
        );

        AutoFillWebhookAuthenticator.AuthenticationResult
            badTimestamp =
                AutoFillWebhookAuthenticator.authenticate(
                    invalidTimestamp,
                    '{}'
                );

        System.assertEquals(
            'INVALID_TIMESTAMP',
            badTimestamp.code
        );
    }

    @IsTest
    static void authenticator_acceptsValidAndRejectsStale() {
        String body = '{"test":true}';
        String timestamp = String.valueOf(TEST_TIMESTAMP);
        Blob hmac = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(timestamp + '.' + body),
            Blob.valueOf(TEST_SECRET)
        );

        RestRequest validRequest = new RestRequest();
        validRequest.addHeader(
            'X-FreightGraph-Timestamp',
            timestamp
        );
        validRequest.addHeader(
            'X-FreightGraph-Signature',
            'sha256=' +
            EncodingUtil.convertToHex(hmac).toLowerCase()
        );
        validRequest.addHeader(
            'X-FreightGraph-Delivery-Id',
            'auth-valid-delivery'
        );

        AutoFillWebhookAuthenticator.testSecret =
            TEST_SECRET;
        AutoFillWebhookAuthenticator.testReplayWindow =
            300;
        AutoFillWebhookAuthenticator.testCurrentTimestamp =
            TEST_TIMESTAMP;

        AutoFillWebhookAuthenticator.AuthenticationResult
            validResult =
                AutoFillWebhookAuthenticator.authenticate(
                    validRequest,
                    body
                );

        System.assertEquals(true, validResult.valid);
        System.assertEquals('AUTHENTICATED', validResult.code);
        System.assertEquals(
            'auth-valid-delivery',
            validResult.deliveryId
        );

        Long staleTimestamp = TEST_TIMESTAMP - 301;
        String staleTimestampText =
            String.valueOf(staleTimestamp);
        Blob staleHmac = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(
                staleTimestampText + '.' + body
            ),
            Blob.valueOf(TEST_SECRET)
        );

        RestRequest staleRequest = new RestRequest();
        staleRequest.addHeader(
            'X-FreightGraph-Timestamp',
            staleTimestampText
        );
        staleRequest.addHeader(
            'X-FreightGraph-Signature',
            'sha256=' +
            EncodingUtil.convertToHex(staleHmac).toLowerCase()
        );

        AutoFillWebhookAuthenticator.AuthenticationResult
            staleResult =
                AutoFillWebhookAuthenticator.authenticate(
                    staleRequest,
                    body
                );

        System.assertEquals(false, staleResult.valid);
        System.assertEquals('STALE_WEBHOOK', staleResult.code);
    }

    @IsTest
    static void authenticator_helpers_coverEdgeCases() {
        System.assertEquals(
            true,
            AutoFillWebhookAuthenticator.secureStringEquals(
                'same',
                'same'
            )
        );
        System.assertEquals(
            false,
            AutoFillWebhookAuthenticator.secureStringEquals(
                'same',
                'diff'
            )
        );
        System.assertEquals(
            false,
            AutoFillWebhookAuthenticator.secureStringEquals(
                null,
                null
            )
        );

        System.assertEquals(
            1716292845L,
            AutoFillWebhookAuthenticator.normalizeTimestampForReplayCheck(
                    1716292845000L
                )
        );
        System.assertEquals(
            -1716292845L,
            AutoFillWebhookAuthenticator.normalizeTimestampForReplayCheck(
                    -1716292845000L
                )
        );
        System.assertEquals(
            null,
            AutoFillWebhookAuthenticator.normalizeTimestampForReplayCheck(null)
        );
    }

    @IsTest
    static void service_reusesAndCachesAccountLookup() {
        Account existingAccount = new Account(
            Name = 'Webhook Existing Account'
        );
        insert existingAccount;

        Schema.DescribeFieldResult accountLookup =
            Contact.AccountId.getDescribe();

        Test.startTest();
        Id reusedId = AutoFillService.findOrCreateLookup(
            accountLookup,
            'Webhook-Existing Account',
            'AccountId',
            new Map<String, Object>()
        );
        Id firstNewId = AutoFillService.findOrCreateLookup(
            accountLookup,
            'Webhook New Account',
            'AccountId',
            new Map<String, Object>()
        );
        Id cachedNewId = AutoFillService.findOrCreateLookup(
            accountLookup,
            'Webhook-New Account',
            'AccountId',
            new Map<String, Object>()
        );
        Test.stopTest();

        System.assertEquals(existingAccount.Id, reusedId);
        System.assertEquals(firstNewId, cachedNewId);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Account
                WHERE Name LIKE 'Webhook%New%Account%'
            ]
        );
    }

    @IsTest
    static void service_populatesFacilityAddressFields() {
        Schema.DescribeSObjectResult laneQuoteDescribe =
            Schema.getGlobalDescribe()
                .get('FreightTM__Lane_Quote__c')
                .getDescribe();
        Schema.DescribeFieldResult pickupFacilityLookup;

        for (Schema.SObjectField fieldToken :
             laneQuoteDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe =
                fieldToken.getDescribe();
            String normalizedLabel = fieldDescribe
                .getLabel()
                .toLowerCase()
                .replaceAll('[^a-z0-9]', '');

            if (
                normalizedLabel == 'pickupfacility' &&
                fieldDescribe.getType() ==
                    Schema.DisplayType.Reference
            ) {
                pickupFacilityLookup = fieldDescribe;
                break;
            }
        }

        System.assertNotEquals(null, pickupFacilityLookup);
        List<Schema.SObjectType> referenceTypes =
            pickupFacilityLookup.getReferenceTo();
        System.assertEquals(1, referenceTypes.size());

        Schema.SObjectType facilityType = referenceTypes[0];
        Schema.DescribeSObjectResult facilityDescribe =
            facilityType.getDescribe();
        Map<String, Object> extractedFields =
            new Map<String, Object>{
                'Pickup City' => 'Cary',
                'Pickup State/Province' => 'CA',
                'Pickup Street' => '2500 Regency Pkwy',
                'Pickup Zip Code' => '34565',
                'Pickup Country' => 'USA',
                'Delivery City' => 'Los Angeles',
                'Delivery State/Province' => 'CA',
                'Delivery Street' => '100 Delivery Street',
                'Delivery Zip Code' => '90001',
                'Delivery Country' => 'USA'
            };

        SObject pickupFacility = facilityType.newSObject();
        SObject deliveryFacility = facilityType.newSObject();

        Test.startTest();
        AutoFillService.populateFacilityFields(
            pickupFacility,
            facilityDescribe,
            'Pickup Facility',
            extractedFields
        );
        AutoFillService.populateFacilityFields(
            deliveryFacility,
            facilityDescribe,
            'Delivery Facility',
            extractedFields
        );
        Test.stopTest();

        List<Object> pickupValues =
            pickupFacility.getPopulatedFieldsAsMap().values();
        List<Object> deliveryValues =
            deliveryFacility.getPopulatedFieldsAsMap().values();

        System.assert(pickupValues.contains('Cary'));
        System.assert(pickupValues.contains('2500 Regency Pkwy'));
        System.assert(pickupValues.contains('34565'));
        System.assert(deliveryValues.contains('Los Angeles'));
        System.assert(deliveryValues.contains('100 Delivery Street'));
        System.assert(deliveryValues.contains('90001'));
    }

    @IsTest
    static void authenticator_rejectsMalformedHexSignatures() {
        String timestamp = String.valueOf(TEST_TIMESTAMP);
        AutoFillWebhookAuthenticator.testSecret = TEST_SECRET;
        AutoFillWebhookAuthenticator.testReplayWindow = 300;
        AutoFillWebhookAuthenticator.testCurrentTimestamp =
            TEST_TIMESTAMP;

        RestRequest invalidHexRequest = new RestRequest();
        invalidHexRequest.addHeader(
            'X-FreightGraph-Timestamp',
            timestamp
        );
        invalidHexRequest.addHeader(
            'X-FreightGraph-Signature',
            'sha256=' +
            'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz' +
            'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz'
        );

        AutoFillWebhookAuthenticator.AuthenticationResult invalidHex =
            AutoFillWebhookAuthenticator.authenticate(
                invalidHexRequest,
                '{}'
            );

        RestRequest shortSignatureRequest = new RestRequest();
        shortSignatureRequest.addHeader(
            'X-FreightGraph-Timestamp',
            timestamp
        );
        shortSignatureRequest.addHeader(
            'X-FreightGraph-Signature',
            'sha256=abc123'
        );

        AutoFillWebhookAuthenticator.AuthenticationResult shortValue =
            AutoFillWebhookAuthenticator.authenticate(
                shortSignatureRequest,
                '{}'
            );

        System.assertEquals(
            'INVALID_SIGNATURE_FORMAT',
            invalidHex.code
        );
        System.assertEquals(
            'INVALID_SIGNATURE_FORMAT',
            shortValue.code
        );
    }

    @IsTest
    static void service_helpers_coverConversions() {
        System.assertEquals(
            false,
            AutoFillService.parseBoolean(null)
        );
        System.assertEquals(
            true,
            AutoFillService.parseBoolean(true)
        );
        System.assertEquals(
            true,
            AutoFillService.parseBoolean('yes')
        );
        System.assertEquals(
            false,
            AutoFillService.parseBoolean('no')
        );

        System.assertEquals(
            Time.newInstance(10, 20, 0, 0),
            AutoFillService.parseTime('10:20Z')
        );
        System.assertEquals(
            Time.newInstance(10, 20, 30, 120),
            AutoFillService.parseTime(
                '10:20:30.12'
            )
        );

        Boolean invalidTimeThrown = false;

        try {
            AutoFillService.parseTime('invalid');
        } catch (Exception expectedException) {
            invalidTimeThrown = true;
        }

        System.assertEquals(true, invalidTimeThrown);

        System.assertEquals(
            null,
            AutoFillService.cleanNumericValue('true')
        );
        System.assertEquals(
            '1234.50',
            AutoFillService.cleanNumericValue(
                '$1,234.50'
            )
        );
        System.assertEquals(
            null,
            AutoFillService.cleanNumericValue('$')
        );
    }
}