@IsTest
private class AutoFillServiceCoverageTest {

    @IsTest
    static void payloadMetadataConfidenceAndAuditHelpers() {
        Map<String, Object> extracted = new Map<String, Object>{
            'Name' => new Map<String, Object>{
                'Value' => 'Coverage Account',
                'Confidence' => 0.91
            },
            'Phone' => new Map<String, Object>{
                'Text' => '555-0100'
            },
            'Unknown Field' => 'not mapped',
            'Blank Field' => ' '
        };
        Map<String, Object> payload = new Map<String, Object>{
            'ItemId' => 'coverage-item-001',
            'DocumentType' => 'Bill of Lading',
            'ClassificationConfidence' => '0.88',
            'AllFieldsDetected' => 'yes',
            'Source' => 'email webhook',
            'ExtractedFields' => extracted,
            'FieldConfidences' => new Map<String, Object>{
                'Phone' => 75
            }
        };

        System.assertEquals(
            'Coverage Account',
            AutoFillService.getFirstValue(
                new Map<String, Object>{
                    'wrapper' => new Map<String, Object>{
                        'NAME' => 'Coverage Account'
                    }
                },
                new List<String>{ 'name' }
            )
        );
        System.assertEquals(
            null,
            AutoFillService.getFirstValue(null, new List<String>{ 'x' })
        );
        System.assertEquals(
            'Coverage Account',
            AutoFillService.getFirstStringValue(
                new Map<String, Object>{ 'Name' => 'Coverage Account' },
                new List<String>{ 'name' }
            )
        );
        System.assertEquals(
            null,
            AutoFillService.getDirectStringValue(
                new Map<String, Object>{
                    'wrapper' => new Map<String, Object>{ 'Name' => 'nested' }
                },
                new List<String>{ 'Name' }
            )
        );

        System.assertEquals('Email', AutoFillService.resolveAutoFillSource(payload, null));
        System.assertEquals(
            'Manual Upload',
            AutoFillService.resolveAutoFillSource(
                new Map<String, Object>{ 'Source' => 'manual upload' },
                null
            )
        );
        System.assertEquals(
            'API Upload',
            AutoFillService.resolveAutoFillSource(
                new Map<String, Object>{ 'Source' => 'API' },
                null
            )
        );
        System.assertEquals(
            'Unknown',
            AutoFillService.resolveAutoFillSource(
                new Map<String, Object>{ 'Source' => 'fax' },
                null
            )
        );
        System.assertEquals(
            'Manual Upload',
            AutoFillService.resolveAutoFillSource(new Map<String, Object>(), 'Manual Upload')
        );

        System.assertEquals('BOL', AutoFillService.resolveDocumentType(payload, extracted));
        System.assertEquals(
            'POD',
            AutoFillService.resolveDocumentType(
                new Map<String, Object>{ 'DocType' => 'Proof of Delivery' },
                null
            )
        );
        System.assertEquals(
            'Rate Confirmation',
            AutoFillService.resolveDocumentType(
                new Map<String, Object>{ 'DocType' => 'Rate Sheet' },
                null
            )
        );
        System.assertEquals(
            'Carrier Invoice',
            AutoFillService.resolveDocumentType(
                new Map<String, Object>{ 'DocType' => 'Invoice' },
                null
            )
        );
        System.assertEquals(
            'Load Tender',
            AutoFillService.resolveDocumentType(
                new Map<String, Object>{ 'DocType' => 'Tender' },
                null
            )
        );
        System.assertEquals(
            'Other',
            AutoFillService.resolveDocumentType(
                new Map<String, Object>{ 'DocType' => 'Custom Document' },
                null
            )
        );
        System.assertEquals(
            'POD',
            AutoFillService.inferDocumentTypeFromFields(
                new Map<String, Object>{ 'Driver Signature' => 'signed' }
            )
        );
        System.assertEquals(
            'Carrier Invoice',
            AutoFillService.inferDocumentTypeFromFields(
                new Map<String, Object>{ 'Invoice Number' => 'INV-1' }
            )
        );
        System.assertEquals(
            'Rate Confirmation',
            AutoFillService.inferDocumentTypeFromFields(
                new Map<String, Object>{ 'Carrier Pay' => 500 }
            )
        );
        System.assertEquals(
            'Load Tender',
            AutoFillService.inferDocumentTypeFromFields(
                new Map<String, Object>{
                    'Pickup' => 'A',
                    'Delivery' => 'B',
                    'Required Trailer' => 'Van'
                }
            )
        );
        System.assertEquals(null, AutoFillService.inferDocumentTypeFromFields(null));

        System.assertEquals(88, AutoFillService.resolveClassificationConfidence(payload));
        System.assertEquals(
            90,
            AutoFillService.resolveOverallConfidence(
                new Map<String, Object>{ 'OverallConfidence' => 0.90 },
                extracted,
                null
            )
        );
        System.assertEquals(
            83,
            AutoFillService.resolveOverallConfidence(
                new Map<String, Object>(),
                extracted,
                new Map<String, Object>{ 'Phone' => 75 }
            )
        );

        List<Decimal> confidences = new List<Decimal>();
        AutoFillService.collectFieldConfidencesFromExtractedFields(
            extracted,
            new Map<String, Object>{ 'Phone' => 75 },
            confidences
        );
        System.assertEquals(2, confidences.size());
        AutoFillService.collectFieldConfidencesFromExtractedFields(null, null, confidences);
        AutoFillService.collectFieldConfidencesFromExtractedFields(extracted, null, null);

        System.assertEquals(
            'Coverage Account',
            AutoFillService.unwrapExtractedFieldValue(extracted.get('Name'))
        );
        Map<String, Object> unwrappedMap = new Map<String, Object>{ 'Other' => 'raw' };
        System.assertEquals(
            unwrappedMap,
            AutoFillService.unwrapExtractedFieldValue(unwrappedMap)
        );
        System.assertEquals(91, AutoFillService.normalizeConfidenceForPercent(0.91));
        System.assertEquals(null, AutoFillService.normalizeConfidenceForPercent(null));
        System.assertEquals(1234.5, AutoFillService.toDecimalOrNull('$1,234.50'));
        System.assertEquals(null, AutoFillService.toDecimalOrNull('bad'));

        Account mappedAccount = new Account(
            Name = 'Coverage Account',
            Phone = '555-0100'
        );
        Map<String, Schema.SObjectField> accountFields =
            Account.SObjectType.getDescribe().fields.getMap();
        Map<String, Object> audit = AutoFillService.buildDetectedFieldsAudit(
            extracted,
            accountFields,
            mappedAccount,
            new Map<String, Object>{ 'Phone' => 75 }
        );
        System.assertEquals(2, AutoFillService.getAuditSectionCount(audit, 'savedToLoad'));
        System.assertEquals(
            1,
            AutoFillService.getAuditSectionCount(audit, 'detectedNotSavedToLoad')
        );
        System.assertEquals(0, AutoFillService.getAuditSectionCount(null, 'x'));
        System.assertEquals(0, AutoFillService.getAuditSectionCount(audit, 'missing'));
        System.assertEquals(
            75,
            AutoFillService.getConfidenceForExtractedField(
                'phone',
                '555-0100',
                new Map<String, Object>{ 'Phone' => 75 }
            )
        );
        System.assertEquals(
            91,
            AutoFillService.extractConfidenceFromField(extracted.get('Name'))
        );
        System.assertEquals(null, AutoFillService.extractConfidenceFromField('plain'));
        System.assertEquals(
            1,
            AutoFillService.getFieldConfidences(payload).size()
        );
        System.assertEquals(
            0,
            AutoFillService.getFieldConfidences(new Map<String, Object>()).size()
        );

        System.assertEquals(null, AutoFillService.serializeRawResponse(null));
        System.assertEquals('raw', AutoFillService.serializeRawResponse('raw'));
        System.assertEquals(null, AutoFillService.serializeDetectedFields(null));
        System.assertNotEquals(null, AutoFillService.serializeDetectedFields(audit));
        System.assertEquals(true, AutoFillService.resolveAllFieldsDetected(payload));
        System.assertEquals(
            true,
            AutoFillService.resolveAllFieldsDetected(
                new Map<String, Object>{ 'MissingFields' => new List<Object>() }
            )
        );
        System.assertEquals(
            false,
            AutoFillService.resolveAllFieldsDetected(
                new Map<String, Object>{ 'MissingFields' => 'Required Field' }
            )
        );
        System.assertEquals(
            true,
            AutoFillService.resolveAllFieldsDetected(
                new Map<String, Object>{ 'LowConfidenceFields' => '' }
            )
        );
        System.assertEquals(null, AutoFillService.resolveAllFieldsDetected(new Map<String, Object>()));

        AutoFillService.ProcessingResult result = AutoFillService.buildProcessingResult(
            null,
            true,
            'Account',
            payload,
            mappedAccount,
            2,
            'Webhook'
        );
        System.assertEquals('coverage-item-001', result.itemId);
        System.assertEquals('BOL', result.detectedDocumentType);
        System.assertEquals(88, result.classificationConfidence);
        System.assertEquals(2, result.fieldCount);
        System.assertEquals('Email', result.autoFillSource);
        System.assertEquals(0, AutoFillService.getMappedFieldCount(mappedAccount));
        System.assertEquals(0, AutoFillService.getMappedFieldCount(null));
    }

    @IsTest
    static void queryDedupInsertAndLookupHelpers() {
        AutoFillService.transactionDedupCache.clear();
        AutoFillService.lookupIdCache.clear();

        Account existing = new Account(
            Name = 'Coverage Existing Account',
            Phone = '555-0200',
            Website = 'https://example.test'
        );
        insert existing;

        System.assertEquals(
            existing.Id,
            AutoFillService.queryFirstByFields(
                'Account',
                new Map<String, Object>{ 'Name' => existing.Name },
                false
            )
        );
        System.assertEquals(
            existing.Id,
            AutoFillService.queryFirstByFields(
                'Account',
                new Map<String, Object>{ 'Name' => existing.Name },
                true
            )
        );
        System.assertEquals(null, AutoFillService.queryFirstByFields(null, null, false));
        System.assertEquals(
            null,
            AutoFillService.queryFirstByFields(
                'Missing_Object__c',
                new Map<String, Object>{ 'Name' => 'x' },
                false
            )
        );
        System.assertEquals(
            null,
            AutoFillService.queryFirstByFields(
                'Account',
                new Map<String, Object>{ 'Name' => null },
                false
            )
        );

        Map<String, Schema.SObjectField> accountFields =
            Account.SObjectType.getDescribe().fields.getMap();
        System.assertEquals(
            null,
            AutoFillService.findExistingRecordByBusinessKey(
                null,
                'Account',
                accountFields
            )
        );
        System.assertEquals(
            existing.Id,
            AutoFillService.findExistingRecordByBusinessKey(
                new Account(
                    Name = existing.Name,
                    Phone = existing.Phone,
                    Website = existing.Website
                ),
                'Account',
                accountFields
            )
        );

        Account safeAccount = new Account();
        AutoFillService.safePut(safeAccount, accountFields, 'Name', 'Safe Account');
        AutoFillService.safePut(safeAccount, accountFields, 'Missing__c', 'ignored');
        AutoFillService.safePut(safeAccount, accountFields, 'Phone', null);
        AutoFillService.safePut(null, accountFields, 'Name', 'ignored');
        System.assertEquals('Safe Account', safeAccount.Name);

        System.assertEquals(
            'corr-001',
            AutoFillService.resolveProcessingIdentifier(
                new Map<String, Object>{ 'CorrelationId' => ' corr-001 ' },
                'fallback'
            )
        );
        System.assertEquals(
            'fallback',
            AutoFillService.resolveProcessingIdentifier(
                new Map<String, Object>(),
                ' fallback '
            )
        );
        System.assertEquals(
            null,
            AutoFillService.resolveProcessingIdentifier(new Map<String, Object>(), null)
        );
        System.assertEquals(null, AutoFillService.findProcessedRecord('X', null, 'Account'));
        System.assertEquals(null, AutoFillService.findProcessedRecord('X', 'id', 'Missing__c'));

        Account firstInsert = new Account(Name = 'Insert Once Account');
        AutoFillService.Resolution first = AutoFillService.insertRecordOnce(
            'EXTRACTION',
            'insert-once-001',
            'Account',
            firstInsert,
            accountFields
        );
        System.assertEquals(true, first.created);
        System.assertNotEquals(null, first.recordId);

        AutoFillService.Resolution second = AutoFillService.insertRecordOnce(
            'EXTRACTION',
            'insert-once-001',
            'Account',
            new Account(Name = 'Must Not Insert'),
            accountFields
        );
        System.assertEquals(false, second.created);
        System.assertEquals(first.recordId, second.recordId);
        System.assertEquals(
            first.recordId,
            AutoFillService.findProcessedRecord(
                'EXTRACTION',
                'insert-once-001',
                'Account'
            )
        );

        Account noIdentifier = new Account(Name = 'No Identifier Account');
        AutoFillService.Resolution noIdentifierResolution =
            AutoFillService.insertRecordOnce(
                'EXTRACTION',
                null,
                'Account',
                noIdentifier,
                accountFields
            );
        System.assertEquals(true, noIdentifierResolution.created);

        Boolean metadataError = false;
        try {
            AutoFillService.insertRecordOnce(
                'EXTRACTION',
                'bad',
                null,
                null,
                accountFields
            );
        } catch (AutoFillService.RecordCreationException e) {
            metadataError = true;
        }
        System.assertEquals(true, metadataError);

        String longSource = '';
        for (Integer index = 0; index < 4100; index++) {
            longSource += 'x';
        }
        System.assertEquals(
            73,
            AutoFillService.buildProcessingKey(null, null, longSource).length()
        );

        AutoFillService.Resolution createdLookup = AutoFillService.resolveOrCreateLookup(
            Account.SObjectType,
            'Name',
            'Lookup Coverage Account',
            new Account(Name = 'Lookup Coverage Account')
        );
        System.assertEquals(true, createdLookup.created);
        AutoFillService.Resolution reusedLookup = AutoFillService.resolveOrCreateLookup(
            Account.SObjectType,
            'Name',
            ' lookup coverage account ',
            new Account(Name = 'Should Not Insert')
        );
        System.assertEquals(false, reusedLookup.created);
        System.assertEquals(createdLookup.recordId, reusedLookup.recordId);
        System.assertEquals(
            createdLookup.recordId,
            AutoFillService.findExistingLookupId(
                'Account',
                'Name',
                'Lookup Coverage Account',
                'lookupcoverageaccount'
            )
        );
        System.assertEquals(
            null,
            AutoFillService.resolveOrCreateLookup(
                Account.SObjectType,
                'Name',
                ' ',
                new Account(Name = 'unused')
            ).recordId
        );

        Boolean lookupMetadataError = false;
        try {
            AutoFillService.resolveOrCreateLookup(null, null, 'x', null);
        } catch (AutoFillService.RecordCreationException e) {
            lookupMetadataError = true;
        }
        System.assertEquals(true, lookupMetadataError);
    }

    @IsTest
    static void v2GraphObjectAndMappingHelpers() {
        Account parentAccount = new Account(Name = 'V2 Parent Account');
        insert parentAccount;

        Map<String, Object> payload = new Map<String, Object>{
            'Metadata' => new Map<String, Object>{
                'pipeline' => 'v2',
                'salesforceParent' => new Map<String, Object>{
                    'objectApiName' => 'Account',
                    'fieldMappings' => new Map<String, Object>{
                        'Customer Name' => 'Name',
                        'Phone Number' => new Map<String, Object>{
                            'fieldApiName' => 'Phone'
                        },
                        'Invalid' => new Map<String, Object>()
                    }
                },
                'collections' => new Map<String, Object>{
                    'Contacts' => new List<Object>{
                        new Map<String, Object>{
                            'ExtractedFields' => new Map<String, Object>{
                                'Last Name' => 'Graph Child',
                                'Phone' => '555-0300'
                            }
                        },
                        'skip-this-row'
                    }
                },
                'salesforceChildren' => new Map<String, Object>{
                    'contacts' => new Map<String, Object>{
                        'objectApiName' => 'Contact',
                        'parentLookupFieldApiName' => 'AccountId',
                        'fieldMappings' => new Map<String, Object>{
                            'Last Name' => 'LastName',
                            'Phone' => 'Phone'
                        }
                    }
                }
            },
            'ExtractedFields' => new Map<String, Object>{ 'Name' => 'Parent' }
        };

        System.assertEquals('Account', AutoFillService.resolveParentObjectApiName(payload));
        System.assertEquals(
            'Contact',
            AutoFillService.resolveParentObjectApiName(
                new Map<String, Object>{ 'ParentObject' => 'Contact' }
            )
        );
        System.assertEquals(
            'FreightTM__Load__c',
            AutoFillService.resolveLegacyV2ParentObjectApiName(
                new Map<String, Object>{
                    'pipeline' => '2',
                    'ExtractedFields' => new Map<String, Object>{ 'A' => 1 }
                }
            )
        );
        System.assertEquals(
            null,
            AutoFillService.resolveLegacyV2ParentObjectApiName(
                new Map<String, Object>{ 'pipeline' => 'v1' }
            )
        );

        Map<String, Object> collections = AutoFillService.getV2Collections(payload);
        System.assertEquals(true, collections.containsKey('Contacts'));
        System.assertEquals(null, AutoFillService.getV2Collections(new Map<String, Object>()));
        System.assertEquals(0, AutoFillService.getResponseMetadata(null).size());
        System.assertEquals(
            0,
            AutoFillService.createV2ChildRecords(null, null, null)
        );
        System.assertEquals(
            1,
            AutoFillService.createV2ChildRecords(
                payload,
                parentAccount.Id,
                'Account'
            )
        );
        Contact child = [
            SELECT Id, LastName, Phone, AccountId
            FROM Contact
            WHERE AccountId = :parentAccount.Id
            LIMIT 1
        ];
        System.assertEquals('Graph Child', child.LastName);

        System.assertEquals(
            null,
            AutoFillService.extractChildRowFields('not a map')
        );
        System.assertEquals(
            'value',
            AutoFillService.extractChildRowFields(
                new Map<String, Object>{
                    'recordFields' => new Map<String, Object>{ 'Nested' => 'value' }
                }
            ).get('Nested')
        );

        Map<String, Schema.SObjectField> contactFields =
            Contact.SObjectType.getDescribe().fields.getMap();
        System.assertEquals(
            'LastName',
            AutoFillService.resolveConfiguredFieldApiName(contactFields, 'LastName')
        );
        String labelResolvedField =
            AutoFillService.resolveConfiguredFieldApiName(
                contactFields,
                'last name'
            );
        System.assert(
            labelResolvedField == null ||
            contactFields.containsKey(labelResolvedField)
        );
        System.assertEquals(
            true,
            AutoFillService.isReferenceToParent(
                Contact.AccountId.getDescribe(),
                'Account'
            )
        );
        System.assertEquals(
            false,
            AutoFillService.isReferenceToParent(
                Contact.LastName.getDescribe(),
                'Account'
            )
        );

        System.assertEquals(null, AutoFillService.resolveExistingSObjectApiName('Missing__c'));

        Map<String, String> parentMappings =
            AutoFillService.getV2ParentFieldMappings(payload);
        System.assertEquals('Name', parentMappings.get('customername'));
        System.assertEquals('Phone', parentMappings.get('phonenumber'));
        System.assertEquals(
            0,
            AutoFillService.parseFieldMappings('not a map').size()
        );

        Map<String, String> inferred =
            AutoFillService.buildFieldNameMap(contactFields);
        Map<String, String> accountInferred =
            AutoFillService.buildFieldNameMap(
                Account.SObjectType.getDescribe().fields.getMap()
            );


        Map<String, Object> source = new Map<String, Object>{
            'A' => new Map<String, Object>{ 'B' => 1 },
            'Text' => 'value'
        };
        System.assertEquals(
            source.get('A'),
            AutoFillService.getValue(source, new List<String>{ 'Missing', 'A' })
        );
        System.assertEquals(
            'value',
            AutoFillService.getStringValue(source, new List<String>{ 'Text' })
        );
        System.assertEquals(
            'value',
            AutoFillService.findDirectValue(
                source,
                new Set<String>{ 'text' }
            )
        );
        System.assertEquals(
            null,
            AutoFillService.findDirectValue(null, new Set<String>{ 'text' })
        );
        System.assertEquals(1, AutoFillService.getMapValue(source, new List<String>{ 'A' }).size());
        System.assertEquals(0, AutoFillService.getMapValue(source, new List<String>{ 'X' }).size());
        System.assertEquals('value', AutoFillService.getFirstStringFromMap(source, new List<String>{ 'Text' }));
        System.assertEquals(null, AutoFillService.getFirstObjectValue(null, null));
        System.assertEquals(false, AutoFillService.isUsableObjectApiName('null'));
        System.assertEquals(true, AutoFillService.isUsableObjectApiName('Account'));
        System.assertEquals(true, AutoFillService.namesMatch('Line Items', 'line-items'));
        System.assertEquals(false, AutoFillService.namesMatch(null, 'x'));

        Map<String, String> mappings = new Map<String, String>();
        AutoFillService.addFieldMapping(mappings, 'name', 'Name');
        AutoFillService.addFieldMapping(mappings, 'name', 'Other');
        AutoFillService.addFieldMapping(mappings, null, 'Other');
        System.assertEquals('Name', mappings.get('name'));
        System.assertNotEquals(
            null,
            AutoFillService.getCreateableNameField(
                Account.SObjectType.getDescribe()
            )
        );
    }

    @IsTest
    static void publicWrapperAndLoadMetadataHelpers() {
        AutoFillService.transactionDedupCache.clear();
        AutoFillService.lookupIdCache.clear();

        Id accountId = AutoFillService.createFromExtractionPayload(
            new Map<String, Object>{
                'SalesforceObjectType' => 'Account',
                'ItemId' => 'wrapper-item-001',
                'ExtractedFields' => new Map<String, Object>{
                    'Name' => 'AutoFill Wrapper Coverage'
                }
            }
        );
        System.assertNotEquals(null, accountId);
        System.assertEquals(
            'AutoFill Wrapper Coverage',
            [SELECT Name FROM Account WHERE Id = :accountId].Name
        );

        Map<String, Schema.SObjectField> loadFields =
            FreightTM__Load__c.SObjectType.getDescribe().fields.getMap();
        FreightTM__Load__c loadRecord = new FreightTM__Load__c();
        Map<String, Object> loadPayload = new Map<String, Object>{
            'ItemId' => 'load-helper-item',
            'Source' => 'Webhook',
            'DocumentType' => 'POD',
            'Confidence' => 0.93,
            'ExtractedFields' => new Map<String, Object>{
                'Pickup City' => 'Irvine'
            }
        };

        AutoFillService.populateAutoFillLoadFields(
            loadRecord,
            'FreightTM__Load__c',
            loadFields,
            loadPayload,
            (Map<String, Object>) loadPayload.get('ExtractedFields'),
            'Webhook'
        );
        AutoFillService.populateAutoFillLoadFields(
            loadRecord,
            'Account',
            null,
            loadPayload,
            new Map<String, Object>(),
            'Webhook'
        );

        if (loadFields.containsKey('AutoFill_Source__c')) {
            System.assert(
                AutoFillRecordEmailNotifier.isWebhookSource(
                    String.valueOf(loadRecord.get('AutoFill_Source__c'))
                ),
                'Expected an Email/Webhook source but found: ' +
                String.valueOf(loadRecord.get('AutoFill_Source__c'))
            );
        }
        if (loadFields.containsKey('AutoFill_Status__c')) {
            System.assertEquals('Draft', loadRecord.get('AutoFill_Status__c'));
        }

        AutoFillService.assignProcessingKey(
            loadRecord,
            'FreightTM__Load__c',
            loadFields,
            'EXTRACTION',
            'load-helper-processing-id'
        );
        AutoFillService.assignProcessingKey(
            null,
            'FreightTM__Load__c',
            loadFields,
            'EXTRACTION',
            'load-helper-processing-id'
        );

        if (loadFields.containsKey('AutoFill_Processing_Key__c')) {
            System.assertNotEquals(
                null,
                loadRecord.get('AutoFill_Processing_Key__c')
            );
        }

        AutoFillService.cacheProcessedRecord(
            'EXTRACTION',
            'cache-helper-id',
            'Account',
            accountId
        );
        AutoFillService.cacheProcessedRecord(
            'EXTRACTION',
            null,
            'Account',
            accountId
        );
        System.assertEquals(
            accountId,
            AutoFillService.findProcessedRecord(
                'EXTRACTION',
                'cache-helper-id',
                'Account'
            )
        );
    }

    @IsTest
    static void conversionAndSmallUtilityHelpers() {
        System.assertEquals(
            true,
            AutoFillService.convertValueForField(
                'YES',
                Task.IsReminderSet.getDescribe()
            )
        );
        System.assertEquals(
            1234,
            AutoFillService.convertValueForField(
                '1,234',
                Account.NumberOfEmployees.getDescribe()
            )
        );
        System.assertEquals(
            1234.50,
            AutoFillService.convertValueForField(
                '$1,234.50',
                Account.AnnualRevenue.getDescribe()
            )
        );
        System.assertEquals(
            Date.today(),
            AutoFillService.convertValueForField(
                String.valueOf(Date.today()) + 'T00:00:00Z',
                Task.ActivityDate.getDescribe()
            )
        );
        System.assertEquals(
            null,
            AutoFillService.convertValue('0001-01-01', Schema.DisplayType.Date)
        );
        System.assertEquals(
            null,
            AutoFillService.convertValue('0001-01-01T00:00:00Z', Schema.DisplayType.DateTime)
        );
        System.assertEquals(
            Time.newInstance(12, 30, 45, 120),
            AutoFillService.convertValue('12:30:45.12Z', Schema.DisplayType.Time)
        );
        System.assertEquals(false, AutoFillService.parseBoolean(null));
        System.assertEquals(true, AutoFillService.parseBoolean('1'));
        System.assertEquals(false, AutoFillService.parseBoolean('no'));

        List<Schema.PicklistEntry> priorities =
            Task.Priority.getDescribe().getPicklistValues();
        String activePriority;
        for (Schema.PicklistEntry entry : priorities) {
            if (entry.isActive()) {
                activePriority = entry.getValue();
                break;
            }
        }
        System.assertNotEquals(null, activePriority);
        System.assertEquals(
            activePriority,
            AutoFillService.resolveValidPicklistValue(
                activePriority.toLowerCase(),
                priorities
            )
        );
        System.assertEquals(
            null,
            AutoFillService.resolveValidPicklistValue('not-real', priorities)
        );
        Object priorityValue = AutoFillService.convertValueForField(
            activePriority,
            Task.Priority.getDescribe()
        );
        System.assertEquals(activePriority, priorityValue);

        System.assertEquals(null, AutoFillService.convertValueForField(null, null));
        System.assertEquals(null, AutoFillService.skipOversizedOptionalValue(null, null));
        System.assertEquals('text', AutoFillService.convertValue(' text ', Schema.DisplayType.String));
        System.assertEquals(null, AutoFillService.convertValue(' ', Schema.DisplayType.String));
        System.assertEquals(null, AutoFillService.cleanNumericValue('yes'));
        System.assertEquals('1234.5', AutoFillService.cleanNumericValue('€1,234.5%'));
        System.assertEquals(true, AutoFillService.isEmpty(null));
        System.assertEquals(true, AutoFillService.isEmpty(' '));
        System.assertEquals(false, AutoFillService.isEmpty(0));
        System.assertEquals('', AutoFillService.normalize(null));
        System.assertEquals('autofill', AutoFillService.normalize('Auto Fill!'));
        System.assertEquals(false, AutoFillService.isFacilityField(null));
        System.assertEquals(true, AutoFillService.isFacilityField('Pickup Facility'));
        System.assertEquals(
            'Austin',
            AutoFillService.getExtractedValue(
                new Map<String, Object>{ 'Pickup City' => 'Austin' },
                'pickup-city'
            )
        );
        System.assertEquals(
            'Phone',
            AutoFillService.findCandidateField(
                new Map<String, String>{ 'phone' => 'Phone' },
                new List<String>{ 'Missing', 'Phone' }
            )
        );
        System.assertEquals(
            null,
            AutoFillService.findCandidateField(
                new Map<String, String>(),
                new List<String>{ 'Missing' }
            )
        );

        Account facilityRecord = new Account(Name = 'Facility');
        AutoFillService.populateFacilityFields(
            facilityRecord,
            Account.SObjectType.getDescribe(),
            'Pickup Facility',
            new Map<String, Object>{ 'Pickup City' => 'Austin' }
        );
        System.assertEquals('Facility', facilityRecord.Name);
    }


    @IsTest
    static void sourcePicklistResolverUsesActiveSemanticValues() {
        Map<String, Schema.SObjectField> loadFields =
            FreightTM__Load__c.SObjectType.getDescribe().fields.getMap();

        if (!loadFields.containsKey('AutoFill_Source__c')) {
            System.assertEquals(
                null,
                AutoFillService.resolveActiveSourcePicklistValue(null, 'Email')
            );
            return;
        }

        Schema.DescribeFieldResult sourceDescribe =
            loadFields.get('AutoFill_Source__c').getDescribe();

        System.assertEquals(
            null,
            AutoFillService.resolveActiveSourcePicklistValue(null, 'Email')
        );
        System.assertEquals(
            null,
            AutoFillService.resolveActiveSourcePicklistValue(
                sourceDescribe,
                null
            )
        );

        Set<String> activeValues = new Set<String>();
        for (Schema.PicklistEntry entry : sourceDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                activeValues.add(entry.getValue());
            }
        }

        for (String requestedValue : new List<String>{
            'Email',
            'Email Webhook',
            'Manual Upload',
            'API Upload'
        }) {
            String resolvedValue =
                AutoFillService.resolveActiveSourcePicklistValue(
                    sourceDescribe,
                    requestedValue
                );

            System.assert(
                resolvedValue == null || activeValues.contains(resolvedValue),
                'The resolver must only return an active source value.'
            );
        }
    }

}