@IsTest
private class AutoFillControllerCoverageTest {


    private class ExtractedItemsMock implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;

        ExtractedItemsMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('GET', request.getMethod());
            System.assert(
                request.getEndpoint().contains(
                    '/api/EmailExtractor/extracted-items'
                )
            );
            System.assertEquals(
                'Bearer coverage-token',
                request.getHeader('Authorization')
            );

            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(responseBody);
            return response;
        }
    }

    private static AutoFillController.UploadFile upload(
        String name,
        String typeValue,
        String content
    ) {
        AutoFillController.UploadFile file =
            new AutoFillController.UploadFile();
        file.fileName = name;
        file.contentType = typeValue;
        file.base64Data = EncodingUtil.base64Encode(Blob.valueOf(content));
        return file;
    }

    @IsTest
    static void basicAndMultipartHelpersCoverBranches() {
        System.assertEquals(
            'No delete result was returned.',
            AutoFillController.buildDatabaseErrorMessage(null)
        );
        System.assertEquals(
            'No delete result was returned.',
            AutoFillController.buildDatabaseErrorMessage(
                new List<Database.DeleteResult>()
            )
        );

        System.assertEquals(false, AutoFillController.parseBoolean(null));
        System.assertEquals(true, AutoFillController.parseBoolean(' YES '));
        System.assertEquals(true, AutoFillController.parseBoolean(1));
        System.assertEquals(false, AutoFillController.parseBoolean('no'));
        System.assertEquals(true, AutoFillController.isEmpty(null));
        System.assertEquals(true, AutoFillController.isEmpty('  '));
        System.assertEquals(false, AutoFillController.isEmpty(0));
        System.assertEquals('', AutoFillController.normalize(null));
        System.assertEquals('autofill', AutoFillController.normalize('Auto Fill!'));

        System.assertEquals(
            false,
            AutoFillController.hasUsableUploadFile(null)
        );
        System.assertEquals(
            false,
            AutoFillController.hasUsableUploadFile(
                new List<AutoFillController.UploadFile>{
                    null,
                    new AutoFillController.UploadFile()
                }
            )
        );
        System.assertEquals(
            true,
            AutoFillController.hasUsableUploadFile(
                new List<AutoFillController.UploadFile>{
                    upload('a.txt', null, 'hello')
                }
            )
        );

        Blob emptyMultipart = AutoFillController.buildMultipartBody(
            'BOUNDARY',
            new Map<String, String>{ 'EmailContent' => 'hello' },
            null
        );
        System.assert(emptyMultipart.toString().contains('EmailContent'));
        System.assert(emptyMultipart.toString().contains('--BOUNDARY--'));

        AutoFillController.UploadFile unsafeName = upload(
            'bad"\r\nname.pdf',
            null,
            'PDF content'
        );
        Blob fileMultipart = AutoFillController.buildMultipartBody(
            'BOUNDARY2',
            new Map<String, String>(),
            new List<AutoFillController.UploadFile>{
                null,
                new AutoFillController.UploadFile(),
                unsafeName
            }
        );
        String multipartText = fileMultipart.toString();
        System.assert(multipartText.contains('application/octet-stream'));
        System.assert(multipartText.contains('badname.pdf'));
    }

    @IsTest
    static void webhookFileExtractionCoversSupportedShapesAndDeduplication() {
        String pdf = EncodingUtil.base64Encode(Blob.valueOf('pdf source file'));
        String image = EncodingUtil.base64Encode(Blob.valueOf('image source file'));
        String text = EncodingUtil.base64Encode(Blob.valueOf('text source file'));

        Object payload = new Map<String, Object>{
            'Payload' => JSON.serialize(
                new Map<String, Object>{
                    'Documents' => new List<Object>{
                        new Map<String, Object>{
                            'FileName' => 'source.pdf',
                            'MimeType' => 'application/pdf',
                            'Content' => 'data:application/pdf;base64,' + pdf
                        },
                        new Map<String, Object>{
                            'FileName' => 'source.pdf',
                            'MimeType' => 'application/pdf',
                            'Content' => pdf
                        },
                        new Map<String, Object>{
                            'ContentType' => 'image/png',
                            'Base64Data' => image
                        },
                        new Map<String, Object>{
                            'FileName' => 'invalid.bin',
                            'Base64Data' => 'not-base64!'
                        }
                    },
                    'Attachments' => new Map<String, Object>{
                        'email.txt' => text,
                        'notAFileName' => text,
                        'not-string.pdf' => 5
                    }
                }
            )
        };

        List<AutoFillController.UploadFile> files =
            AutoFillController.extractWebhookUploadFiles(payload);
        System.assertEquals(3, files.size());
        Set<String> fileNames = new Set<String>();
        Boolean foundGeneratedName = false;
        for (AutoFillController.UploadFile file : files) {
            fileNames.add(file.fileName);
            if (file.fileName.startsWith('AutoFill-email-document-')) {
                foundGeneratedName = true;
            }
        }
        System.assert(fileNames.contains('source.pdf'));
        System.assert(fileNames.contains('email.txt'));
        System.assertEquals(true, foundGeneratedName);

        List<AutoFillController.UploadFile> directResult =
            new List<AutoFillController.UploadFile>();
        Set<String> seen = new Set<String>();
        AutoFillController.collectWebhookUploadFiles(
            null,
            directResult,
            seen,
            0,
            false
        );
        AutoFillController.collectWebhookUploadFiles(
            new Map<String, Object>(),
            null,
            seen,
            0,
            false
        );
        AutoFillController.collectWebhookUploadFiles(
            payload,
            directResult,
            seen,
            8,
            false
        );
        System.assertEquals(0, directResult.size());

        AutoFillController.collectWebhookFilesFromNamedEntries(
            null,
            directResult,
            seen
        );
        AutoFillController.collectWebhookFilesFromNamedEntries(
            new Map<String, Object>{ 'a.pdf' => pdf },
            directResult,
            seen
        );
        System.assertEquals(1, directResult.size());
    }

    @IsTest
    static void webhookFileUtilityHelpersCoverValidationBranches() {
        String validBase64 = EncodingUtil.base64Encode(
            Blob.valueOf('valid content')
        );
        System.assertEquals(false, AutoFillController.looksLikeWebhookFileName(null));
        System.assertEquals(false, AutoFillController.looksLikeWebhookFileName('file'));
        System.assertEquals(true, AutoFillController.looksLikeWebhookFileName('file.pdf'));
        System.assertEquals(true, AutoFillController.isWebhookJsonWrapperKey('Extraction Result'));
        System.assertEquals(false, AutoFillController.isWebhookJsonWrapperKey('other'));
        System.assertEquals(null, AutoFillController.tryDeserializeWebhookJson(null));
        System.assertEquals(null, AutoFillController.tryDeserializeWebhookJson('plain'));
        System.assertEquals(null, AutoFillController.tryDeserializeWebhookJson('{bad'));
        System.assert(
            AutoFillController.tryDeserializeWebhookJson('{"x":1}')
            instanceof Map<String, Object>
        );

        System.assertEquals(
            null,
            AutoFillController.buildWebhookUploadFile(null, true, 1)
        );
        System.assertEquals(
            null,
            AutoFillController.buildWebhookUploadFile(
                new Map<String, Object>{ 'Name' => 'not-file.pdf' },
                false,
                1
            )
        );
        System.assertEquals(
            null,
            AutoFillController.buildWebhookUploadFile(
                new Map<String, Object>{ 'Base64Data' => validBase64 },
                false,
                1
            )
        );
        AutoFillController.UploadFile defaultNamed =
            AutoFillController.buildWebhookUploadFile(
                new Map<String, Object>{
                    'ContentType' => 'application/pdf',
                    'Data' => new Map<String, Object>{
                        'Base64' => validBase64
                    }
                },
                true,
                4
            );
        System.assertNotEquals(null, defaultNamed);
        System.assertEquals(
            'AutoFill-email-document-4.pdf',
            defaultNamed.fileName
        );

        System.assertEquals(
            false,
            AutoFillController.hasExplicitWebhookFileDataKey(null)
        );
        System.assertEquals(
            true,
            AutoFillController.hasExplicitWebhookFileDataKey(
                new Map<String, Object>{ 'File Content' => validBase64 }
            )
        );
        System.assertEquals(
            validBase64,
            AutoFillController.getWebhookBase64Value(
                new Map<String, Object>{
                    'Content' => new Map<String, Object>{
                        'Base64' => validBase64
                    }
                }
            )
        );
        System.assertEquals(
            null,
            AutoFillController.getWebhookBase64Value(
                new Map<String, Object>{ 'Other' => 'x' }
            )
        );
        System.assertEquals(
            null,
            AutoFillController.getDirectWebhookString(null, null)
        );
        System.assertEquals(
            null,
            AutoFillController.getDirectWebhookString(
                new Map<String, Object>{ 'Name' => 'null' },
                new Set<String>{ 'name' }
            )
        );
        System.assertEquals(
            '5',
            AutoFillController.getDirectWebhookString(
                new Map<String, Object>{ 'Name' => 5 },
                new Set<String>{ 'name' }
            )
        );

        System.assertEquals(true, AutoFillController.isWebhookFileCollectionKey('Source Documents'));
        System.assertEquals(false, AutoFillController.isWebhookFileCollectionKey('Fields'));
        System.assertEquals(null, AutoFillController.normalizeWebhookBase64(null));
        System.assertEquals(null, AutoFillController.normalizeWebhookBase64('a'));
        System.assertEquals(
            validBase64,
            AutoFillController.normalizeWebhookBase64(
                'data:application/octet-stream;base64,' + validBase64
            )
        );
        System.assertEquals(true, AutoFillController.isValidWebhookBase64(validBase64));
        System.assertEquals(false, AutoFillController.isValidWebhookBase64('abc'));

        System.assertEquals('AutoFill-email-document-1.bin', AutoFillController.buildDefaultWebhookFileName(null, null));
        System.assertEquals('AutoFill-email-document-2.png', AutoFillController.buildDefaultWebhookFileName('image/png', 2));
        System.assertEquals('AutoFill-email-document-2.jpg', AutoFillController.buildDefaultWebhookFileName('image/jpeg', 2));
        System.assertEquals('AutoFill-email-document-2.gif', AutoFillController.buildDefaultWebhookFileName('image/gif', 2));
        System.assertEquals('AutoFill-email-document-2.tif', AutoFillController.buildDefaultWebhookFileName('image/tiff', 2));
        System.assertEquals('AutoFill-email-document-2.docx', AutoFillController.buildDefaultWebhookFileName('application/vnd.openxmlformats-officedocument.wordprocessingml.document', 2));
        System.assertEquals('AutoFill-email-document-2.doc', AutoFillController.buildDefaultWebhookFileName('application/msword', 2));

        AutoFillController.UploadFile longFile = upload('sample.pdf', 'application/pdf', 'content');
        String dedup = AutoFillController.buildWebhookFileDedupKey(longFile);
        System.assert(dedup.startsWith('samplepdf|'));
        System.assertNotEquals(null, AutoFillController.buildWebhookFileDedupKey(null));
    }

    @IsTest
    static void savesGenericFilesAndHandlesInvalidFileData() {
        Account parent = new Account(Name = 'AutoFill Generic File Parent');
        insert parent;

        System.assertEquals(
            0,
            AutoFillController.saveUploadedFilesToRecord(
                null,
                null,
                null,
                'Account'
            )
        );
        System.assertEquals(
            0,
            AutoFillController.saveUploadedFilesToRecord(
                parent.Id,
                new List<AutoFillController.UploadFile>{
                    null,
                    new AutoFillController.UploadFile()
                },
                null,
                'Account'
            )
        );

        Test.startTest();
        Integer saved = AutoFillController.saveUploadedFilesToRecord(
            parent.Id,
            new List<AutoFillController.UploadFile>{
                upload('folder\\invoice.pdf', 'application/pdf', 'invoice')
            },
            'generic-item',
            'Account'
        );
        Test.stopTest();
        System.assertEquals(1, saved);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :parent.Id]
        );

        AutoFillController.UploadFile invalid =
            new AutoFillController.UploadFile();
        invalid.fileName = 'invalid.pdf';
        invalid.base64Data = '%%%invalid%%%';
        Boolean thrown = false;
        try {
            AutoFillController.saveUploadedFilesToRecord(
                parent.Id,
                new List<AutoFillController.UploadFile>{ invalid },
                null,
                'Account'
            );
        } catch (Exception e) {
            thrown = true;
        }
        System.assertEquals(true, thrown);

        System.assertEquals(
            0,
            AutoFillController.saveWebhookFilesToRecord(
                null,
                new Map<String, Object>(),
                null,
                null
            )
        );
        System.assertEquals(
            0,
            AutoFillController.saveWebhookFilesToRecord(
                parent.Id,
                new Map<String, Object>{ 'Fields' => 'no files' },
                null,
                null
            )
        );
    }

    @IsTest
    static void auditFileNameConfidenceAndDescribeHelpersCoverBranches() {
        System.assertEquals(0, AutoFillController.parseDetectedFieldsAudit(null).size());
        System.assertEquals(0, AutoFillController.parseDetectedFieldsAudit('[]').size());
        System.assertEquals(0, AutoFillController.parseDetectedFieldsAudit('{bad').size());
        Map<String, Object> audit = new Map<String, Object>{
            'savedToLoad' => new List<Object>{ 'row' }
        };
        System.assertEquals(
            1,
            AutoFillController.getOrCreateAuditList(audit, 'savedToLoad').size()
        );
        System.assertEquals(
            0,
            AutoFillController.getOrCreateAuditList(audit, 'missing').size()
        );
        System.assertEquals(0, AutoFillController.deleteAutoFillFilesForLoad(null));
        System.assertEquals(
            0,
            AutoFillController.getAutoFillDocumentIdsFromAudit(
                null,
                null
            ).size()
        );

        System.assertEquals('AutoFill Upload', AutoFillController.buildAutoFillFileDescription(null));
        System.assert(AutoFillController.buildAutoFillFileDescription('item').contains('item'));
        System.assertEquals('', AutoFillController.sanitizeFileName(null));
        System.assertEquals('folder_file.pdf', AutoFillController.sanitizeFileName(' folder/file.pdf '));
        String longName = '';
        for (Integer i = 0; i < 300; i++) {
            longName += 'a';
        }
        System.assertEquals(255, AutoFillController.sanitizeFileName(longName).length());
        System.assertEquals('AutoFill upload', AutoFillController.removeFileExtension(null));
        System.assertEquals('file', AutoFillController.removeFileExtension('file.pdf'));
        System.assertEquals('file', AutoFillController.removeFileExtension('file'));

        System.assertEquals(
            50,
            AutoFillController.resolveClassificationConfidence(
                new Map<String, Object>{ 'classificationConfidence' => 0.5 }
            )
        );
        System.assertEquals(null, AutoFillController.normalizeConfidenceForPercent(null));
        System.assertEquals(90, AutoFillController.normalizeConfidenceForPercent(90));
        System.assertEquals(null, AutoFillController.serializeDetectedFields(null));
        System.assertNotEquals(
            null,
            AutoFillController.serializeDetectedFields(
                new Map<String, Object>{ 'a' => 1 }
            )
        );

        Account accountRecord = new Account();
        AutoFillController.safePutByDescribe(accountRecord, 'Name', 'Test Account');
        AutoFillController.safePutByDescribe(accountRecord, 'Missing__c', 'x');
        AutoFillController.safePutByDescribe(accountRecord, 'Phone', null);
        System.assertEquals('Test Account', accountRecord.Name);

        Boolean nullLoadThrown = false;
        try {
            AutoFillController.getAutoFillLoadForUpdate(null);
        } catch (AuraHandledException e) {
            nullLoadThrown = true;
        }
        System.assertEquals(true, nullLoadThrown);
    }

    @IsTest
    static void documentAndDraftHelpersCoverNestedAndOptionalBranches() {
        Map<String, Object> body = new Map<String, Object>{
            'wrapper' => new Map<String, Object>{
                'Id' => 'doc-id',
                'ItemId' => 'item-id',
                'FileName' => 'document.pdf',
                'Status' => 'Completed',
                'WebhookStatus' => 'Delivered',
                'DetectedDocumentType' => 'POD',
                'OverallConfidence' => '0.88',
                'ClassificationConfidence' => '92%',
                'ProcessedAt' => 'now',
                'ExtractedFields' => new Map<String, Object>{
                    'A Field' => new Map<String, Object>{
                        'Value' => 'A',
                        'Score' => 0.7
                    },
                    'B Field' => null,
                    'C Field' => new Map<String, Object>{ 'Other' => 'raw' }
                }
            }
        };
        AutoFillController.DocumentScanResult result =
            AutoFillController.buildDocumentScanResult(body, '{raw}');
        System.assertEquals('doc-id', result.id);
        System.assertEquals(88, result.confidence);
        System.assertEquals(92, result.classificationConfidence);
        System.assertEquals(3, result.extractedFields.size());
        System.assertEquals('{raw}', result.rawJson);

        System.assertEquals(
            null,
            AutoFillController.getFirstValue(null, null)
        );
        System.assertEquals(
            'nested',
            AutoFillController.getFirstStringValue(
                new Map<String, Object>{
                    'wrapper' => new Map<String, Object>{ 'Target' => 'nested' }
                },
                new List<String>{ 'target' }
            )
        );
        System.assertEquals(null, AutoFillController.toDecimalOrNull(null));
        System.assertEquals(1234.5, AutoFillController.toDecimalOrNull('$1,234.50'));
        System.assertEquals(null, AutoFillController.toDecimalOrNull('bad'));
        System.assertEquals('Uploaded file', AutoFillController.buildContentDocumentDisplayName(null, null));
        System.assertEquals('file.pdf', AutoFillController.buildContentDocumentDisplayName('file', 'PDF'));
        System.assertEquals('file.pdf', AutoFillController.buildContentDocumentDisplayName('file.pdf', 'pdf'));

        System.assertEquals(null, AutoFillController.resolveDraftSourceLabel(null, null));
        System.assertEquals('Email', AutoFillController.resolveDraftSourceLabel('Webhook', null));
        System.assertEquals('Manual Upload', AutoFillController.resolveDraftSourceLabel('manual', null));
        System.assertEquals('API Upload', AutoFillController.resolveDraftSourceLabel('api', null));
        System.assertEquals('Other Source', AutoFillController.resolveDraftSourceLabel(' Other Source ', null));
        System.assertEquals(
            'Email',
            AutoFillController.resolveDraftSourceLabel(
                null,
                '{"Source":"Email Webhook"}'
            )
        );
        System.assertEquals(null, AutoFillController.resolveDraftSourceLabel(null, '{bad'));
        System.assertEquals('', AutoFillController.resolveDraftSourceText(null));
        System.assertEquals('', AutoFillController.resolveDraftSourceText('{bad'));
        System.assertEquals(
            'email body',
            AutoFillController.resolveDraftSourceText(
                '{"payload":[{"EmailBody":"email body"}]}'
            )
        );
        System.assertEquals(
            '',
            AutoFillController.resolveDraftSourceText('{"SourceText":"text"}')
        );
        System.assertEquals(
            null,
            AutoFillController.findNestedSourceText(null, null)
        );

        System.assertEquals(0, AutoFillController.buildDraftSearchTokens(null).size());
        System.assertEquals(
            5,
            AutoFillController.buildDraftSearchTokens(
                'Irvine, CA -> Phoenix, AZ extra token'
            ).size()
        );
        System.assertEquals('Route not available', AutoFillController.buildDraftRoute(null, null, null, null));
        System.assertEquals('Phoenix, AZ', AutoFillController.buildDraftRoute(null, null, 'Phoenix', 'AZ'));
        System.assertEquals('Irvine, CA', AutoFillController.buildDraftRoute('Irvine', 'CA', null, null));
        System.assert(AutoFillController.buildDraftRoute('Irvine', 'CA', 'Phoenix', 'AZ').contains('→'));
        System.assertEquals('', AutoFillController.joinLocation(null, null));
    }

    @IsTest
    static void optionalAndExtractedItemHelpersCoverAllTypes() {
        Account accountRecord = new Account(
            Name = 'Optional Test',
            AnnualRevenue = 123.45
        );
        Map<String, Schema.SObjectField> accountFields =
            Account.SObjectType.getDescribe().fields.getMap();
        System.assertEquals(
            'Optional Test',
            AutoFillController.getOptionalString(
                accountRecord,
                accountFields,
                'Name'
            )
        );
        System.assertEquals(
            '',
            AutoFillController.getOptionalString(null, accountFields, 'Name')
        );
        System.assertEquals(
            123.45,
            AutoFillController.getOptionalDecimal(
                accountRecord,
                accountFields,
                'AnnualRevenue'
            )
        );
        System.assertEquals(
            123,
            AutoFillController.getOptionalInteger(
                accountRecord,
                accountFields,
                'AnnualRevenue'
            )
        );

        Task taskRecord = new Task(IsReminderSet = true);
        Map<String, Schema.SObjectField> taskFields =
            Task.SObjectType.getDescribe().fields.getMap();
        System.assertEquals(
            true,
            AutoFillController.getOptionalBoolean(
                taskRecord,
                taskFields,
                'IsReminderSet'
            )
        );
        System.assertEquals(
            false,
            AutoFillController.getOptionalBoolean(null, taskFields, 'IsReminderSet')
        );

        Map<String, Object> source = new Map<String, Object>{
            'Id' => 5,
            'NullValue' => null
        };
        System.assertEquals('5', AutoFillController.getExtractedItemsString(source, 'Id'));
        System.assertEquals('', AutoFillController.getExtractedItemsString(source, 'Missing'));
        System.assertEquals('', AutoFillController.getExtractedItemsString(source, 'NullValue'));
        System.assertEquals(12, AutoFillController.parseExtractedItemsInteger('12'));
        System.assertEquals(0, AutoFillController.parseExtractedItemsInteger(null));
        System.assertEquals(0, AutoFillController.parseExtractedItemsInteger('bad'));
        System.assertEquals('', AutoFillController.buildExtractedItemsFieldSummary(null));
        String summary = AutoFillController.buildExtractedItemsFieldSummary(
            new Map<String, Object>{
                'A' => 1,
                'B' => '',
                'C' => 3,
                'D' => 4,
                'E' => 5
            }
        );
        System.assert(summary.contains('blank'));
        System.assertEquals(4, summary.split('\\|').size());
    }

    @IsTest
    static void extractedItemsEndpointCoversSuccessResponse() {
        AutoFillController.testAccessToken = 'coverage-token';
        Test.setMock(
            HttpCalloutMock.class,
            new ExtractedItemsMock(
                200,
                JSON.serialize(new Map<String, Object>{
                    'Page' => 2,
                    'PageSize' => 5,
                    'Total' => 1,
                    'Items' => new List<Object>{
                        'skip-row',
                        new Map<String, Object>{
                            'Id' => 'item-1',
                            'TenantId' => 'tenant-1',
                            'ExtractedAt' => '2026-07-22T10:00:00Z',
                            'SalesforceObjectType' => 'Account',
                            'SalesforceRecordId' => '001000000000001',
                            'SenderEmail' => 'sender@example.com',
                            'ExtractedFields' => new Map<String, Object>{
                                'Name' => 'Extracted Account',
                                'Phone' => null
                            }
                        },
                        new Map<String, Object>{
                            'Id' => 'item-2',
                            'ExtractedFields' => 'not-a-map'
                        }
                    }
                })
            )
        );

        Test.startTest();
        AutoFillController.ExtractedItemsResult result =
            AutoFillController.getExtractedItems(2, 5);
        Test.stopTest();

        System.assertEquals(2, result.page);
        System.assertEquals(5, result.pageSize);
        System.assertEquals(1, result.total);
        System.assertEquals(2, result.items.size());
        System.assert(result.items[0].extractedFieldsSummary.contains('Name'));
        System.assertEquals('', result.items[1].extractedFieldsJson);
    }

    @IsTest
    static void extractedItemsEndpointSurfacesHttpFailure() {
        AutoFillController.testAccessToken = 'coverage-token';
        Test.setMock(
            HttpCalloutMock.class,
            new ExtractedItemsMock(503, 'service unavailable')
        );

        Boolean failed = false;
        try {
            AutoFillController.getExtractedItems(0, 0);
        } catch (AuraHandledException expected) {
            failed = true;
        }
        System.assertEquals(true, failed);
    }



    private static void putCreateableValue(
        SObject recordToUpdate,
        Map<String, Schema.SObjectField> fields,
        String fieldApiName,
        Object value
    ) {
        if (recordToUpdate == null ||
            fields == null ||
            !fields.containsKey(fieldApiName)) {
            return;
        }

        Schema.DescribeFieldResult fieldDescribe =
            fields.get(fieldApiName).getDescribe();

        if (fieldDescribe.isCreateable() &&
            !fieldDescribe.isCalculated() &&
            !fieldDescribe.isAutoNumber()) {
            recordToUpdate.put(fieldApiName, value);
        }
    }

    private static Id createAuditCoverageLoad() {
        FreightLoadSyncHandler.bypassForTests = true;
        Test.setMock(
            HttpCalloutMock.class,
            new AutoFillTestCalloutMock()
        );

        Account customer = new Account(
            Name = 'AutoFill Audit Coverage ' + System.now().getTime()
        );
        insert customer;

        Schema.SObjectType loadType =
            Schema.getGlobalDescribe().get('FreightTM__Load__c');
        System.assertNotEquals(null, loadType);

        Map<String, Schema.SObjectField> loadFields =
            loadType.getDescribe().fields.getMap();
        SObject loadRecord = loadType.newSObject();

        putCreateableValue(
            loadRecord,
            loadFields,
            'FreightTM__Customer__c',
            customer.Id
        );
        putCreateableValue(
            loadRecord,
            loadFields,
            'FreightTM__Pickup_City__c',
            'Irvine'
        );
        putCreateableValue(
            loadRecord,
            loadFields,
            'FreightTM__Delivery_City__c',
            'Phoenix'
        );
        putCreateableValue(
            loadRecord,
            loadFields,
            'FreightTM__Pickup_Date__c',
            Date.today()
        );
        putCreateableValue(
            loadRecord,
            loadFields,
            'FreightTM__Delivery_Date__c',
            Date.today().addDays(1)
        );
        putCreateableValue(
            loadRecord,
            loadFields,
            'FreightTM__Status__c',
            'Assigned'
        );
        putCreateableValue(
            loadRecord,
            loadFields,
            'AutoFill_Status__c',
            'Draft'
        );
        putCreateableValue(
            loadRecord,
            loadFields,
            'AutoFill_Detected_Fields__c',
            JSON.serialize(new Map<String, Object>{
                'savedToLoad' => new List<Object>(),
                'detectedNotSavedToLoad' => new List<Object>(),
                'rawDetectedFields' => new List<Object>()
            })
        );

        AutoFillSafeDml.insertRecord(loadRecord);
        return (Id) loadRecord.get('Id');
    }

    @IsTest
    static void attachedFileAuditAndNestedSourceCoverRemainingBranches() {
        Id loadId = createAuditCoverageLoad();
        Map<String, Schema.SObjectField> loadFields =
            FreightTM__Load__c.SObjectType.getDescribe().fields.getMap();

        if (!loadFields.containsKey('AutoFill_Detected_Fields__c')) {
            System.assertEquals(
                null,
                AutoFillController.findNestedSourceText(
                    null,
                    new Set<String>{ 'emailcontent' }
                )
            );
            return;
        }

        List<ContentVersion> versionsToInsert = new List<ContentVersion>{
            new ContentVersion(
                Title = 'existing-autofill-source',
                PathOnClient = 'existing-autofill-source.pdf',
                VersionData = Blob.valueOf('existing source'),
                FirstPublishLocationId = loadId,
                Description = 'AutoFill Upload | ItemId: existing-audit'
            ),
            new ContentVersion(
                Title = 'new-autofill-source',
                PathOnClient = 'new-autofill-source.pdf',
                VersionData = Blob.valueOf('new source'),
                FirstPublishLocationId = loadId,
                Description = 'AutoFill Upload | ItemId: new-audit'
            )
        };
        insert versionsToInsert;

        Set<Id> insertedVersionIds = new Set<Id>();
        for (ContentVersion insertedVersion : versionsToInsert) {
            insertedVersionIds.add(insertedVersion.Id);
        }

        List<ContentVersion> insertedVersions = [
            SELECT Id, ContentDocumentId, Title, PathOnClient, Description
            FROM ContentVersion
            WHERE Id IN :insertedVersionIds
            ORDER BY Title
        ];

        ContentVersion existingVersion;
        ContentVersion newVersion;
        for (ContentVersion version : insertedVersions) {
            if (version.Title == 'existing-autofill-source') {
                existingVersion = version;
            } else if (version.Title == 'new-autofill-source') {
                newVersion = version;
            }
        }

        System.assertNotEquals(null, existingVersion);
        System.assertNotEquals(null, newVersion);

        Map<String, Object> initialAudit = new Map<String, Object>{
            'savedToLoad' => new List<Object>{
                'ignore-non-map-row',
                new Map<String, Object>{
                    'fieldName' => 'Missing document ID',
                    'contentDocumentId' => null
                },
                new Map<String, Object>{
                    'fieldName' => 'Existing file',
                    'contentDocumentId' =>
                        String.valueOf(existingVersion.ContentDocumentId)
                },
                new Map<String, Object>{
                    'fieldName' => 'Malformed document ID',
                    'contentDocumentId' => 'not-an-id'
                }
            },
            'detectedNotSavedToLoad' => 'not-a-list',
            'rawDetectedFields' => new List<Object>()
        };

        SObject auditUpdate =
            Schema.getGlobalDescribe().get('FreightTM__Load__c').newSObject();
        auditUpdate.put('Id', loadId);
        auditUpdate.put(
            'AutoFill_Detected_Fields__c',
            JSON.serialize(initialAudit)
        );
        update auditUpdate;

        AutoFillController.appendAttachedFilesToDetectedAudit(null, null);
        AutoFillController.appendAttachedFilesToDetectedAudit(
            loadId,
            new List<ContentVersion>()
        );

        List<ContentVersion> versionsForAudit =
            new List<ContentVersion>{
                existingVersion,
                newVersion,
                new ContentVersion(Title = 'missing-document-id')
            };

        Test.startTest();
        AutoFillController.appendAttachedFilesToDetectedAudit(
            loadId,
            versionsForAudit
        );
        Test.stopTest();

        String detectedFieldName =
            loadFields.get('AutoFill_Detected_Fields__c')
                .getDescribe()
                .getName();
        List<SObject> refreshedLoads = Database.query(
            'SELECT ' + detectedFieldName +
            ' FROM FreightTM__Load__c WHERE Id = :loadId LIMIT 1'
        );
        Map<String, Object> updatedAudit =
            AutoFillController.parseDetectedFieldsAudit(
                String.valueOf(
                    refreshedLoads[0].get('AutoFill_Detected_Fields__c')
                )
            );
        List<Object> savedRows =
            AutoFillController.getOrCreateAuditList(
                updatedAudit,
                'savedToLoad'
            );

        Boolean foundNewFile = false;
        for (Object rowObject : savedRows) {
            if (!(rowObject instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> row = (Map<String, Object>) rowObject;
            if (
                String.valueOf(row.get('contentDocumentId')) ==
                String.valueOf(newVersion.ContentDocumentId)
            ) {
                foundNewFile = true;
                System.assertEquals(
                    'new-autofill-source.pdf',
                    String.valueOf(row.get('value'))
                );
                System.assertEquals(
                    'Uploaded File 1',
                    String.valueOf(row.get('fieldName'))
                );
            }
        }
        System.assertEquals(true, foundNewFile);

        Set<Id> linkedDocumentIds = new Set<Id>{
            existingVersion.ContentDocumentId,
            newVersion.ContentDocumentId
        };
        Set<Id> auditDocumentIds =
            AutoFillController.getAutoFillDocumentIdsFromAudit(
                loadId,
                linkedDocumentIds
            );
        System.assert(auditDocumentIds.contains(existingVersion.ContentDocumentId));
        System.assert(auditDocumentIds.contains(newVersion.ContentDocumentId));

        Map<String, Object> nestedPayload = new Map<String, Object>{
            'wrapper' => new List<Object>{
                'skip-scalar',
                new Map<String, Object>{
                    'EmailContent' => 'nested email body'
                }
            }
        };
        System.assertEquals(
            'nested email body',
            AutoFillController.findNestedSourceText(
                nestedPayload,
                new Set<String>{ 'emailcontent' }
            )
        );
        System.assertEquals(
            null,
            AutoFillController.findNestedSourceText(
                'scalar',
                new Set<String>{ 'emailcontent' }
            )
        );
    }

}