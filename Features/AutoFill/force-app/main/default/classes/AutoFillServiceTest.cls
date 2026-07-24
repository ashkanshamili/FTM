@IsTest
private class AutoFillServiceTest {

    @IsTest
    static void sameProcessingIdentifierCreatesOneTask() {
        FreightLoadSyncHandler.bypassForTests = true;
        Map<String, Object> payload = taskPayload(
            'AutoFill Idempotent Task',
            'task-item-001'
        );

        Test.startTest();
        AutoFillService.ProcessingResult first =
            AutoFillService.createFromExtractionPayloadWithStatus(
                payload,
                'delivery-task-001',
                'Webhook'
            );
        AutoFillService.ProcessingResult second =
            AutoFillService.createFromExtractionPayloadWithStatus(
                payload,
                'delivery-task-001',
                'Webhook'
            );
        Test.stopTest();

        System.assertEquals(true, first.created);
        System.assertEquals(false, second.created);
        System.assertEquals(first.recordId, second.recordId);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Task
                WHERE Subject = 'AutoFill Idempotent Task'
            ]
        );
    }

    @IsTest
    static void loadStoresUniqueProcessingKeyAndReusesIt() {
        FreightLoadSyncHandler.bypassForTests = true;
        Map<String, Object> payload = loadPayload(
            'load-item-unique-001',
            'Phoenix',
            'AZ',
            'Dallas',
            'TX'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new AutoFillTestCalloutMock()
        );

        Test.startTest();
        AutoFillService.ProcessingResult first =
            AutoFillService.createFromExtractionPayloadWithStatus(
                payload,
                'delivery-load-unique-001',
                'Webhook'
            );
        AutoFillService.ProcessingResult second =
            AutoFillService.createFromExtractionPayloadWithStatus(
                payload,
                'delivery-load-unique-001',
                'Webhook'
            );
        Test.stopTest();

        System.assertEquals(true, first.created);
        System.assertEquals(false, second.created);
        System.assertEquals(first.recordId, second.recordId);

        Id createdLoadId = first.recordId;
        Map<String, Schema.SObjectField> loadFields =
            FreightTM__Load__c.SObjectType.getDescribe().fields.getMap();
        List<String> selectedFields = new List<String>{ 'Id' };
        List<String> optionalFields = new List<String>{
            'AutoFill_Processing_Key__c',
            'AutoFill_Source__c',
            'AutoFill_Status__c',
            'Created_By_AutoFill__c',
            'AutoFill_Item_Id__c',
            'AutoFill_Extracted_Fields_JSON__c'
        };

        for (String fieldApiName : optionalFields) {
            if (loadFields.containsKey(fieldApiName)) {
                selectedFields.add(
                    loadFields.get(fieldApiName).getDescribe().getName()
                );
            }
        }







    }

    @IsTest
    static void businessFingerprintPreventsDuplicateLoadWithNewItemId() {
        FreightLoadSyncHandler.bypassForTests = true;
        Map<String, Object> firstPayload = loadPayload(
            'fingerprint-item-001',
            'Irvine',
            'CA',
            'Las Vegas',
            'NV'
        );
        Map<String, Object> secondPayload = loadPayload(
            'fingerprint-item-002',
            'Irvine',
            'CA',
            'Las Vegas',
            'NV'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new AutoFillTestCalloutMock()
        );

        Test.startTest();
        AutoFillService.ProcessingResult first =
            AutoFillService.createFromExtractionPayloadWithStatus(
                firstPayload,
                'fingerprint-delivery-001',
                'Manual Upload'
            );
        AutoFillService.ProcessingResult second =
            AutoFillService.createFromExtractionPayloadWithStatus(
                secondPayload,
                'fingerprint-delivery-002',
                'Webhook'
            );
        Test.stopTest();

        System.assertEquals(true, first.created);
        System.assertEquals(false, second.created);
        System.assertEquals(
            first.recordId,
            second.recordId,
            'The same business document must reuse the recent Load.'
        );
    }

    @IsTest
    static void normalizedLookupNamesReuseOneCarrier() {
        FreightLoadSyncHandler.bypassForTests = true;
        Schema.DescribeFieldResult carrierLookup =
            FreightTM__Load__c.SObjectType.getDescribe()
                .fields.getMap()
                .get('FreightTM__Carrier_Obj__c')
                .getDescribe();

        Test.startTest();
        Id firstCarrierId = AutoFillService.findOrCreateLookup(
            carrierLookup,
            'Concurrent Sample Carrier',
            'Carrier',
            new Map<String, Object>()
        );
        Id secondCarrierId = AutoFillService.findOrCreateLookup(
            carrierLookup,
            'Concurrent  Sample-Carrier',
            'Carrier',
            new Map<String, Object>()
        );
        Test.stopTest();

        System.assertNotEquals(null, firstCarrierId);
        System.assertEquals(firstCarrierId, secondCarrierId);
    }

    @IsTest
    static void processingIdentifierAndKeyAreDeterministic() {
        FreightLoadSyncHandler.bypassForTests = true;
        Map<String, Object> payload = new Map<String, Object>{
            'CorrelationId' => 'corr-priority-001',
            'ItemId' => 'item-fallback-001'
        };

        System.assertEquals(
            'corr-priority-001',
            AutoFillService.resolveProcessingIdentifier(
                payload,
                'delivery-fallback-001'
            )
        );
        System.assertEquals(
            'delivery-only-001',
            AutoFillService.resolveProcessingIdentifier(
                new Map<String, Object>(),
                'delivery-only-001'
            )
        );

        String firstKey = AutoFillService.buildProcessingKey(
            'EXTRACTION',
            'FreightTM__Load__c',
            'ABC-123'
        );
        String secondKey = AutoFillService.buildProcessingKey(
            'extraction',
            'FreightTM__Load__c',
            ' abc-123 '
        );

        System.assertEquals(firstKey, secondKey);
        System.assert(firstKey.startsWith('EXTRACTION:'));
        System.assertEquals(75, firstKey.length());
    }

    @IsTest
    static void cleanAndNormalizeLookupValues() {
        FreightLoadSyncHandler.bypassForTests = true;
        System.assertEquals(
            'ACME Freight LLC',
            AutoFillService.cleanDisplayValue(
                '  ACME\n Freight\tLLC  '
            )
        );
        System.assertEquals(
            'acmefreightllc',
            AutoFillService.normalizeLookupValue(
                'ACME Freight, LLC'
            )
        );
    }

    @IsTest
    static void skipsMissingInvalidPicklistAndUnusableLookupFields() {
        FreightLoadSyncHandler.bypassForTests = true;
        Map<String, Object> payload = new Map<String, Object>{
            'Success' => true,
            'ItemId' => 'skip-invalid-task-001',
            'SalesforceObjectType' => 'Task',
            'Metadata' => new Map<String, Object>{
                'salesforceParent' => new Map<String, Object>{
                    'fieldMappings' => new Map<String, Object>{
                        'Missing Field' => 'Does_Not_Exist__c'
                    }
                }
            },
            'ExtractedFields' => new Map<String, Object>{
                'Subject' => 'AutoFill Skip Invalid Fields',
                'Status' => 'Not Started',
                'Priority' => 'Not A Real Priority',
                'WhoId' => 'Unresolvable Contact Value',
                'Missing Field' => 'This value must be ignored'
            }
        };

        Test.startTest();
        AutoFillService.ProcessingResult result =
            AutoFillService.createFromExtractionPayloadWithStatus(
                payload,
                'skip-invalid-task-delivery-001',
                'Webhook'
            );
        Test.stopTest();

        System.assertEquals(true, result.created);

        Id createdTaskId = result.recordId;
        Task storedTask = [
            SELECT Id, Subject, Status, Priority, WhoId
            FROM Task
            WHERE Id = :createdTaskId
        ];

        System.assertEquals(
            'AutoFill Skip Invalid Fields',
            storedTask.Subject
        );
        System.assertEquals(
            null,
            storedTask.WhoId,
            'An unusable lookup value must be skipped.'
        );
        if (Task.Priority.getDescribe().isRestrictedPicklist()) {
            System.assertNotEquals(
                'Not A Real Priority',
                storedTask.Priority,
                'An invalid restricted picklist value must be skipped.'
            );
        } else {
            System.assertEquals(
                'Not A Real Priority',
                storedTask.Priority,
                'Unrestricted picklists accept values that are not predefined.'
            );
        }
    }

    @IsTest
    static void loadContinuesWhenContactPersonLookupCannotBeCreated() {
        FreightLoadSyncHandler.bypassForTests = true;
        Map<String, Schema.SObjectField> loadFields =
            FreightTM__Load__c.SObjectType.getDescribe().fields.getMap();
        String contactPersonFieldApiName;

        for (String fieldApiName : loadFields.keySet()) {
            Schema.DescribeFieldResult fieldDescribe =
                loadFields.get(fieldApiName).getDescribe();

            if (fieldDescribe.getLabel() == 'Contact Person' ||
                fieldApiName.equalsIgnoreCase(
                    'FreightTM__Contact_Person__c'
                )) {
                contactPersonFieldApiName = fieldApiName;
                break;
            }
        }

        System.assertNotEquals(
            null,
            contactPersonFieldApiName,
            'The Load Contact Person field must exist for this regression test.'
        );

        Map<String, Object> payload = loadPayload(
            'skip-contact-person-item-001',
            'Tempe',
            'AZ',
            'Austin',
            'TX'
        );

        ((Map<String, Object>) payload.get('ExtractedFields')).put(
            'Contact Person',
            'Contact That Cannot Be Auto Created'
        );
        payload.put(
            'Metadata',
            new Map<String, Object>{
                'salesforceParent' => new Map<String, Object>{
                    'fieldMappings' => new Map<String, Object>{
                        'Contact Person' =>
                            'freighttm__contact_person__c'
                    }
                }
            }
        );

        Test.setMock(
            HttpCalloutMock.class,
            new AutoFillTestCalloutMock()
        );

        Test.startTest();
        AutoFillService.ProcessingResult result =
            AutoFillService.createFromExtractionPayloadWithStatus(
                payload,
                'skip-contact-person-delivery-001',
                'Manual Upload'
            );
        Test.stopTest();

        System.assertEquals(
            true,
            result.created,
            'The Load must still be created when Contact Person cannot map.'
        );

        Id createdLoadId = result.recordId;
        SObject storedLoad = Database.query(
            'SELECT Id, ' + contactPersonFieldApiName +
            ' FROM FreightTM__Load__c WHERE Id = :createdLoadId'
        );

        System.assertEquals(
            null,
            storedLoad.get(contactPersonFieldApiName),
            'The invalid Contact Person value must be skipped.'
        );
    }

    @IsTest
    static void oversizedOptionalFieldIsSkippedWithoutFailingRecord() {
        FreightLoadSyncHandler.bypassForTests = true;
        String oversizedPhone = '';
        for (Integer index = 0; index < 80; index++) {
            oversizedPhone += '9';
        }

        Map<String, Object> payload = new Map<String, Object>{
            'Success' => true,
            'ItemId' => 'oversized-contact-item-001',
            'SalesforceObjectType' => 'Contact',
            'ExtractedFields' => new Map<String, Object>{
                'LastName' => 'Oversized Field Contact',
                'Phone' => oversizedPhone
            }
        };

        Test.startTest();
        AutoFillService.ProcessingResult result =
            AutoFillService.createFromExtractionPayloadWithStatus(
                payload,
                'oversized-contact-delivery-001',
                'Webhook'
            );
        Test.stopTest();

        System.assertEquals(true, result.created);

        Contact storedContact = [
            SELECT Id, LastName, Phone
            FROM Contact
            WHERE Id = :result.recordId
        ];

        System.assertEquals('Oversized Field Contact', storedContact.LastName);
        System.assertEquals(
            null,
            storedContact.Phone,
            'An oversized optional value must be skipped, not reject the record.'
        );

        System.assertEquals(
            null,
            AutoFillService.skipOversizedOptionalValue(
                oversizedPhone,
                Contact.Phone.getDescribe()
            )
        );
        System.assertEquals(
            'Valid phone',
            AutoFillService.skipOversizedOptionalValue(
                'Valid phone',
                Contact.Phone.getDescribe()
            )
        );
        System.assertEquals(
            123,
            AutoFillService.skipOversizedOptionalValue(
                123,
                Contact.Phone.getDescribe()
            )
        );
    }

    @IsTest
    static void oversizedCommodityIsSkippedForLoadWebhook() {
        FreightLoadSyncHandler.bypassForTests = true;
        Schema.DescribeFieldResult commodityDescribe =
            FreightTM__Load__c.FreightTM__Commodity__c.getDescribe();
        String oversizedCommodity = '';

        for (Integer index = 0;
             index < commodityDescribe.getLength() + 25;
             index++) {
            oversizedCommodity += 'C';
        }

        Map<String, Object> payload = loadPayload(
            'oversized-commodity-load-item-001',
            'Reno',
            'NV',
            'Boise',
            'ID'
        );
        ((Map<String, Object>) payload.get('ExtractedFields')).put(
            'FreightTM__Commodity__c',
            oversizedCommodity
        );

        Test.setMock(
            HttpCalloutMock.class,
            new AutoFillTestCalloutMock()
        );

        Test.startTest();
        AutoFillService.ProcessingResult result =
            AutoFillService.createFromExtractionPayloadWithStatus(
                payload,
                'oversized-commodity-delivery-001',
                'Webhook'
            );
        Test.stopTest();

        System.assertEquals(true, result.created);

        Id createdLoadId = result.recordId;
        SObject storedLoad = Database.query(
            'SELECT Id, FreightTM__Commodity__c, ' +
            'AutoFill_Detected_Fields__c ' +
            'FROM FreightTM__Load__c WHERE Id = :createdLoadId'
        );

        System.assertEquals(
            null,
            storedLoad.get('FreightTM__Commodity__c'),
            'Oversized Commodity must be skipped instead of failing the Load.'
        );
        System.assert(
            String.valueOf(
                storedLoad.get('AutoFill_Detected_Fields__c')
            ).contains('detectedNotSavedToLoad'),
            'The audit must show that the oversized field was not saved.'
        );
    }

    @IsTest
    static void invalidPayloadsReturnActionableErrors() {
        FreightLoadSyncHandler.bypassForTests = true;
        try {
            AutoFillService.createFromExtractionPayloadWithStatus(
                new Map<String, Object>(),
                null,
                'Webhook'
            );
            System.assert(false, 'Expected empty payload error.');
        } catch (AutoFillService.RecordCreationException e) {
            System.assert(e.getMessage().contains('payload is empty'));
        }

        try {
            AutoFillService.createFromExtractionPayloadWithStatus(
                new Map<String, Object>{
                    'SalesforceObjectType' => 'Task'
                },
                null,
                'Webhook'
            );
            System.assert(false, 'Expected ExtractedFields error.');
        } catch (AutoFillService.RecordCreationException e) {
            System.assert(e.getMessage().contains('ExtractedFields'));
        }
    }

    private static Map<String, Object> taskPayload(
        String subject,
        String itemId
    ) {
        return new Map<String, Object>{
            'Success' => true,
            'ItemId' => itemId,
            'SalesforceObjectType' => 'Task',
            'ExtractedFields' => new Map<String, Object>{
                'Subject' => subject,
                'Status' => 'Not Started',
                'Priority' => 'Normal'
            }
        };
    }

    private static Map<String, Object> loadPayload(
        String itemId,
        String pickupCity,
        String pickupState,
        String deliveryCity,
        String deliveryState
    ) {
        return new Map<String, Object>{
            'Success' => true,
            'ItemId' => itemId,
            'SalesforceObjectType' => 'FreightTM__Load__c',
            'ExtractedFields' => new Map<String, Object>{
                'FreightTM__Pickup_City__c' => pickupCity,
                'FreightTM__Pickup_State__c' => pickupState,
                'FreightTM__Delivery_City__c' => deliveryCity,
                'FreightTM__Delivery_State__c' => deliveryState
            }
        };
    }
}