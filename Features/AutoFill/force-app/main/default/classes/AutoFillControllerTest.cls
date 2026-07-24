@IsTest
private class AutoFillControllerTest {
    private static final String LANE_QUOTE_OBJECT =
        'FreightTM__Lane_Quote__c';
    
    private class EmailExtractorMock
        implements HttpCalloutMock {
            
            private Integer statusCode;
            private String responseBody;
            
            EmailExtractorMock(
                Integer statusCode,
                String responseBody
            ) {
                this.statusCode = statusCode;
                this.responseBody = responseBody;
            }
            
            public HttpResponse respond(HttpRequest request) {
                System.assertEquals(
                    'Bearer test-token',
                    request.getHeader('Authorization')
                );

                if (request.getMethod() == 'POST') {
                    System.assert(
                        request.getEndpoint().contains(
                            '/api/EmailExtractor/process-email-with-files'
                        )
                    );
                    
                    System.assert(
                        request.getHeader('Content-Type')
                        .startsWith('multipart/form-data; boundary=')
                    );
                    
                    System.assertNotEquals(
                        null,
                        request.getBodyAsBlob()
                    );
                } else {
                    System.assertEquals(
                        'GET',
                        request.getMethod()
                    );

                    System.assert(
                        request.getEndpoint().contains(
                            '/api/Ai-scanning/documents/'
                        )
                    );
                }
                
                HttpResponse response = new HttpResponse();
                response.setStatusCode(statusCode);
                response.setHeader(
                    'Content-Type',
                    'application/json'
                );
                response.setBody(responseBody);
                
                return response;
            }
        }
    
    private static List<
        AutoFillController.UploadFile
        > createFiles() {
            AutoFillController.UploadFile file =
                new AutoFillController.UploadFile();
            
            file.fileName = 'lane-quote-test.pdf';
            file.contentType = 'application/pdf';
            file.base64Data = EncodingUtil.base64Encode(
                Blob.valueOf('Test PDF content')
            );
            
            return new List<
                AutoFillController.UploadFile
                >{
                    file
                        };
                            }
    
    private static String createApiResponse(
        Boolean success,
        String message,
        String objectApiName,
        Map<String, Object> extractedFields
    ) {
        Map<String, Object> response =
            new Map<String, Object>{
                'Success' => success,
                    'Message' => message,
                    'Errors' => new List<Object>(),
                    'ExtractedFields' => extractedFields
                    };
                        
                        if (objectApiName != null) {
                            response.put(
                                'SalesforceObjectType',
                                objectApiName
                            );
                        }
        
        return JSON.serialize(response);
    }
    
    private static void configureMock(
        Integer statusCode,
        String responseBody
    ) {
        AutoFillController.testAccessToken =
            'test-token';
        
        Test.setMock(
            HttpCalloutMock.class,
            new EmailExtractorMock(
                statusCode,
                responseBody
            )
        );
    }
    
    @IsTest
    static void sendEmailContentCreatesLaneQuoteAndFacility() {
        Map<String, Object> extractedFields =
            new Map<String, Object>{
                'Description' => 'Testing new quote',
                    'Branch' => 'DRAYAGE',
                    'Status.' => 'Received',
                    
                    // This invalid numeric value should be skipped.
                    'Customer Rate' => 'True',
                    
                    'Intermodal' => 'true',
                    'New Client' => 'true',
                    
                    'Pickup Facility' =>
                    'Test Facility ' +
                    String.valueOf(DateTime.now().getTime()),
                    
                    'Pickup City' => 'Cary',
                    'Pickup State/Province' => 'CA',
                    'Pickup Street' => '2500 Regency Pkwy',
                    'Pickup Zip Code' => '34565',
                    'Pickup Country' => 'United States'
                    };
                        
                        String responseBody = createApiResponse(
                            true,
                            'Email with files processed successfully',
                            LANE_QUOTE_OBJECT,
                            extractedFields
                        );
        
        configureMock(200, responseBody);
        
        Test.startTest();
        
        AutoFillController.ApiResult result =
            AutoFillController.sendEmailContent(
                'Create a lane quote for the attached document.',
                createFiles()
            );
        
        Test.stopTest();
        
        System.assertEquals(
            true,
            result.success,
            result.message
        );
        
        System.assertEquals(
            200,
            result.statusCode
        );
        
        System.assertEquals(
            LANE_QUOTE_OBJECT,
            result.objectType
        );
        
        System.assertNotEquals(
            null,
            result.recordId
        );
        
        System.assertEquals(
            responseBody,
            result.responseBody
        );
        
        Id createdRecordId = result.recordId;
        
        SObject createdRecord = Database.query(
            'SELECT Id FROM ' +
            LANE_QUOTE_OBJECT +
            ' WHERE Id = :createdRecordId'
        );
        
        System.assertEquals(
            result.recordId,
            createdRecord.get('Id')
        );
    }
    
    @IsTest
    static void getExtractedDocumentReturnsFieldRows() {
        Map<String, Object> response = new Map<String, Object>{
            'Id' => 'doc-1',
            'ItemId' => 'item-123',
            'FileName' => 'rate-confirmation.pdf',
            'Status' => 'Processed',
            'WebhookStatus' => 'Completed',
            'DetectedDocumentType' => 'Rate Confirmation',
            'Confidence' => 91.5,
            'ProcessedAt' => '2026-07-05T05:54:30.542Z',
            'ExtractedFields' => new Map<String, Object>{
                'Origin' => 'Chicago, IL',
                'Destination' => 'Fort Worth, TX'
            }
        };

        configureMock(200, JSON.serialize(response));

        Test.startTest();

        AutoFillController.DocumentScanResult result =
            AutoFillController.getExtractedDocument('item-123');

        Test.stopTest();

        System.assertEquals('item-123', result.itemId);
        System.assertEquals('Rate Confirmation', result.detectedDocumentType);
        System.assertEquals(2, result.extractedFields.size());
    }

    @IsTest
    static void returnsErrorForHttpFailure() {
        configureMock(
            500,
            '{"message":"Internal server error"}'
        );
        
        Test.startTest();
        
        AutoFillController.ApiResult result =
            AutoFillController.sendEmailContent(
                'Test HTTP error',
                createFiles()
            );
        
        Test.stopTest();
        
        System.assertEquals(false, result.success);
        System.assertEquals(500, result.statusCode);
        
        System.assert(
            result.message.contains(
                'API call failed with status 500'
            )
        );
    }
    
    @IsTest
    static void returnsErrorForInvalidJson() {
        configureMock(
            200,
            'This is not JSON'
        );
        
        Test.startTest();
        
        AutoFillController.ApiResult result =
            AutoFillController.sendEmailContent(
                'Test invalid JSON',
                createFiles()
            );
        
        Test.stopTest();
        
        System.assertEquals(false, result.success);
        System.assertEquals(200, result.statusCode);
        
        System.assert(
            result.message.contains(
                'The API returned invalid JSON'
            )
        );
    }
    
    @IsTest
    static void returnsApiFailureMessage() {
        String responseBody = createApiResponse(
            false,
            'The document could not be processed.',
            null,
            new Map<String, Object>()
        );
        
        configureMock(200, responseBody);
        
        Test.startTest();
        
        AutoFillController.ApiResult result =
            AutoFillController.sendEmailContent(
                'Test API failure',
                createFiles()
            );
        
        Test.stopTest();
        
        System.assertEquals(false, result.success);
        
        System.assertEquals(
            'The document could not be processed.',
            result.message
        );
    }
    
    @IsTest
    static void rejectsUnknownObjectApiName() {
        String responseBody = createApiResponse(
            true,
            'Processing successful',
            'Not_A_Real_Object__c',
            new Map<String, Object>{
                'Name' => 'Unknown object test'
            }
        );

        configureMock(200, responseBody);

        Test.startTest();

        AutoFillController.ApiResult result =
            AutoFillController.sendEmailContent(
                'Test unknown object',
                createFiles()
            );

        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(null, result.recordId);
        System.assert(
            result.message.contains(
                'parent Salesforce object API name'
            ),
            result.message
        );
    }
    
    @IsTest
    static void returnsErrorWhenObjectTypeIsMissing() {
        String responseBody = createApiResponse(
            true,
            'Processing successful',
            null,
            new Map<String, Object>{
                'Description' => 'Missing object type'
                    }
        );
        
        configureMock(200, responseBody);
        
        Test.startTest();
        
        AutoFillController.ApiResult result =
            AutoFillController.sendEmailContent(
                'Test missing object type',
                createFiles()
            );
        
        Test.stopTest();
        
        System.assertEquals(false, result.success);
        
        System.assert(
            result.message.contains(
                'parent Salesforce object API name'
            )
        );
    }
    
    @IsTest
    static void acceptsNotesWithoutAttachments() {
        String responseBody = createApiResponse(
            true,
            'Processing successful',
            'Task',
            new Map<String, Object>{
                'Subject' => 'Notes only AutoFill',
                'Status' => 'Not Started',
                'Priority' => 'Normal'
            }
        );

        configureMock(200, responseBody);

        Test.startTest();
        AutoFillController.ApiResult result =
            AutoFillController.sendEmailContent(
                'Create a task from these notes.',
                new List<
                    AutoFillController.UploadFile
                >()
            );
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals('Task', result.objectType);
        System.assertNotEquals(null, result.recordId);
    }

    @IsTest
    static void acceptsAttachmentsWithoutNotes() {
        String responseBody = createApiResponse(
            true,
            'Processing successful',
            'Task',
            new Map<String, Object>{
                'Subject' => 'Attachment only AutoFill',
                'Status' => 'Not Started',
                'Priority' => 'Normal'
            }
        );

        configureMock(200, responseBody);

        Test.startTest();
        AutoFillController.ApiResult result =
            AutoFillController.sendEmailContent(
                '   ',
                createFiles()
            );
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals('Task', result.objectType);
        System.assertNotEquals(null, result.recordId);
    }

    @IsTest
    static void rejectsWhenNotesAndFilesAreBothMissing() {
        Boolean exceptionThrown = false;

        try {
            AutoFillController.sendEmailContent(
                '   ',
                new List<
                    AutoFillController.UploadFile
                >()
            );
        } catch (AuraHandledException expectedException) {
            exceptionThrown = true;
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'An empty submission must be rejected.'
        );
    }

    @IsTest
    static void parseTimeCoversSupportedFormats() {
        // Hours and minutes only, including Z removal.
        System.assertEquals(
            Time.newInstance(10, 30, 0, 0),
            AutoFillController.parseTime('10:30Z')
        );
        
        // Hours, minutes and seconds.
        System.assertEquals(
            Time.newInstance(10, 30, 45, 0),
            AutoFillController.parseTime('10:30:45')
        );
        
        // One millisecond digit must be padded to 100.
        System.assertEquals(
            Time.newInstance(10, 30, 45, 100),
            AutoFillController.parseTime(
                '10:30:45.1'
            )
        );
        
        // Two millisecond digits must be padded to 120.
        System.assertEquals(
            Time.newInstance(10, 30, 45, 120),
            AutoFillController.parseTime(
                '10:30:45.12'
            )
        );
        
        // More than three digits must be truncated.
        System.assertEquals(
            Time.newInstance(10, 30, 45, 123),
            AutoFillController.parseTime(
                '10:30:45.1234567'
            )
        );
        
        // Exactly three digits.
        System.assertEquals(
            Time.newInstance(23, 59, 59, 999),
            AutoFillController.parseTime(
                '23:59:59.999'
            )
        );
    }
    
    @IsTest
    static void parseTimeRejectsInvalidValue() {
        Boolean exceptionThrown = false;
        
        try {
            AutoFillController.parseTime(
                'invalid'
            );
        } catch (Exception e) {
            exceptionThrown = true;
            
            System.assert(
                e.getMessage().contains(
                    'Invalid time value'
                )
            );
        }
        
        System.assertEquals(
            true,
            exceptionThrown,
            'An invalid time should throw an exception.'
        );
    }
    
    @IsTest
    static void cleanNumericValueCoversAllFormats() {
        System.assertEquals(
            null,
            AutoFillController.cleanNumericValue(
                null
            )
        );
        
        System.assertEquals(
            null,
            AutoFillController.cleanNumericValue(
                ''
            )
        );
        
        System.assertEquals(
            null,
            AutoFillController.cleanNumericValue(
                '   '
            )
        );
        
        System.assertEquals(
            null,
            AutoFillController.cleanNumericValue(
                'true'
            )
        );
        
        System.assertEquals(
            null,
            AutoFillController.cleanNumericValue(
                'FALSE'
            )
        );
        
        System.assertEquals(
            null,
            AutoFillController.cleanNumericValue(
                'Yes'
            )
        );
        
        System.assertEquals(
            null,
            AutoFillController.cleanNumericValue(
                'NO'
            )
        );
        
        System.assertEquals(
            '1234.50',
            AutoFillController.cleanNumericValue(
                '$1,234.50'
            )
        );
        
        System.assertEquals(
            '2500',
            AutoFillController.cleanNumericValue(
                '€2,500'
            )
        );
        
        System.assertEquals(
            '99.99',
            AutoFillController.cleanNumericValue(
                '£99.99'
            )
        );
        
        System.assertEquals(
            '15',
            AutoFillController.cleanNumericValue(
                '15%'
            )
        );
        
        System.assertEquals(
            '-125.75',
            AutoFillController.cleanNumericValue(
                ' -125.75 '
            )
        );
        
        // After removing the currency symbol, nothing remains.
        System.assertEquals(
            null,
            AutoFillController.cleanNumericValue(
                '$'
            )
        );
    }

    @IsTest
    static void getExtractedDocumentRejectsBlankItemId() {
        Boolean thrown = false;

        try {
            AutoFillController.getExtractedDocument('   ');
        } catch (AuraHandledException expectedException) {
            thrown = true;
        }

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void getExtractedDocumentHandlesNotFoundAndServerErrors() {
        configureMock(404, '{"message":"Not found"}');

        Boolean notFoundThrown = false;
        try {
            AutoFillController.getExtractedDocument('missing-item');
        } catch (AuraHandledException expectedException) {
            notFoundThrown = true;
        }
        System.assertEquals(true, notFoundThrown);

        configureMock(503, '{"message":"Unavailable"}');

        Boolean serverErrorThrown = false;
        try {
            AutoFillController.getExtractedDocument('failed-item');
        } catch (AuraHandledException expectedException) {
            serverErrorThrown = true;
        }
        System.assertEquals(true, serverErrorThrown);
    }

    @IsTest
    static void getExtractedDocumentRejectsInvalidJson() {
        configureMock(200, 'not-json');

        Boolean thrown = false;

        try {
            AutoFillController.getExtractedDocument('invalid-json-item');
        } catch (AuraHandledException expectedException) {
            thrown = true;
        }

        System.assertEquals(true, thrown);
    }


    @IsTest
    static void resolvesStoredSourceTextForPreview() {
        System.assertEquals(
            'Pickup in Phoenix and deliver in Dallas.',
            AutoFillController.resolveDraftSourceText(
                '{"AutoFillSourceText":"Pickup in Phoenix and deliver in Dallas."}'
            )
        );
        System.assertEquals(
            'Webhook email body',
            AutoFillController.resolveDraftSourceText(
                '{"payload":{"EmailBody":"Webhook email body"}}'
            )
        );
        System.assertEquals(
            '',
            AutoFillController.resolveDraftSourceText(
                '{"EmailContent":"text"}'
            )
        );
    }
}