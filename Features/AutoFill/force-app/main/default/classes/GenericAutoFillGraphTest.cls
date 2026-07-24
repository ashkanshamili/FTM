@IsTest
private class GenericAutoFillGraphTest {

    private class ExtractionResponseMock implements HttpCalloutMock {
        private final String responseBody;

        ExtractionResponseMock(String responseBody) {
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest request) {
            String endpoint = String.valueOf(request.getEndpoint());
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');

            if (endpoint.contains('/api/auth/login') ||
                endpoint.contains('/api/auth/refresh')) {
                response.setBody(
                    '{"token":"generic-test-token","expiresIn":3600}'
                );
            } else if (endpoint.contains('/api/loads')) {
                response.setBody('{}');
            } else {
                response.setBody(responseBody);
            }

            return response;
        }
    }

    private static Map<String, Object> parsePayload(String payloadJson) {
        return (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
    }

    @IsTest
    static void controllerCreatesOnlyExplicitGenericChildren() {
        String parentName = 'Generic Parent ' + String.valueOf(DateTime.now().getTime());
        String childLastName = 'Explicit Child ' + String.valueOf(DateTime.now().getTime());

        Map<String, Object> payload = new Map<String, Object>{
            'Success' => true,
            'ItemId' => 'generic-controller-explicit-child',
            'SalesforceObjectType' => 'Account',
            'ExtractedFields' => new Map<String, Object>{
                'Name' => parentName
            },
            'Metadata' => new Map<String, Object>{
                'salesforceChildren' => new Map<String, Object>{
                    'contacts' => new Map<String, Object>{
                        'objectApiName' => 'Contact',
                        'parentLookupFieldApiName' => 'AccountId'
                    }
                },
                'collections' => new Map<String, Object>{
                    'contacts' => new List<Object>{
                        new Map<String, Object>{
                            'LastName' => childLastName,
                            'Email' => 'explicit-child@example.com'
                        }
                    }
                }
            }
        };

        Test.setMock(
            HttpCalloutMock.class,
            new ExtractionResponseMock(JSON.serialize(payload))
        );
        AutoFillController.testAccessToken = 'test-token';

        Test.startTest();
        AutoFillController.ApiResult result =
            AutoFillController.sendEmailContent(
                'Create a generic Account with one explicit Contact child.',
                new List<AutoFillController.UploadFile>()
            );
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals('Account', result.objectType);
        System.assertNotEquals(null, result.recordId);

        Id createdParentId = result.recordId;
        Account createdParent = [
            SELECT Id, Name
            FROM Account
            WHERE Id = :createdParentId
            LIMIT 1
        ];
        System.assertEquals(parentName, createdParent.Name);

        Contact createdChild = [
            SELECT Id, AccountId, LastName, Email
            FROM Contact
            WHERE AccountId = :createdParent.Id
            LIMIT 1
        ];
        System.assertEquals(childLastName, createdChild.LastName);
        System.assertEquals('explicit-child@example.com', createdChild.Email);
    }

    @IsTest
    static void controllerDoesNotGuessChildFromCollectionName() {
        String parentName = 'No Guess Parent ' + String.valueOf(DateTime.now().getTime());

        Map<String, Object> payload = new Map<String, Object>{
            'Success' => true,
            'ItemId' => 'generic-controller-no-guess',
            'SalesforceObjectType' => 'Account',
            'ExtractedFields' => new Map<String, Object>{
                'Name' => parentName
            },
            'Metadata' => new Map<String, Object>{
                'collections' => new Map<String, Object>{
                    'contacts' => new List<Object>{
                        new Map<String, Object>{
                            'LastName' => 'Must Not Be Created',
                            'Email' => 'must-not-exist@example.com'
                        }
                    },
                    'freight_tm_legs' => new List<Object>{
                        new Map<String, Object>{
                            'LastName' => 'Legacy Guess Must Not Be Created'
                        }
                    }
                }
            }
        };

        Test.setMock(
            HttpCalloutMock.class,
            new ExtractionResponseMock(JSON.serialize(payload))
        );
        AutoFillController.testAccessToken = 'test-token';

        Test.startTest();
        AutoFillController.ApiResult result =
            AutoFillController.sendEmailContent(
                'Create only the parent. Child definitions are intentionally absent.',
                new List<AutoFillController.UploadFile>()
            );
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        Id createdParentId = result.recordId;
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Contact WHERE AccountId = :createdParentId],
            'A collection without an explicit Salesforce child definition must never create a child.'
        );
    }

    @IsTest
    static void controllerSupportsLegacyV2LoadWithoutGuessingChildren() {
        String customerName =
            'Legacy V2 Customer ' + String.valueOf(DateTime.now().getTime());

        Map<String, Object> payload = new Map<String, Object>{
            'Success' => true,
            'ItemId' => 'generic-controller-legacy-v2-load',
            'ExtractedFields' => new Map<String, Object>{
                'Customer' => customerName,
                'Pickup City' => 'Houston',
                'Delivery City' => 'Dallas',
                'Pickup Date' => String.valueOf(Date.today()),
                'Delivery Date' => String.valueOf(Date.today().addDays(1))
            },
            'Metadata' => new Map<String, Object>{
                'pipeline' => 'v2',
                // A collection without an explicit child definition must be ignored.
                'collections' => new Map<String, Object>{
                    'freight_tm_legs' => new List<Object>{
                        new Map<String, Object>{
                            'Description' => 'Must not be created'
                        }
                    }
                }
            }
        };

        Test.setMock(
            HttpCalloutMock.class,
            new ExtractionResponseMock(JSON.serialize(payload))
        );
        AutoFillController.testAccessToken = 'test-token';

        Test.startTest();
        AutoFillController.ApiResult result =
            AutoFillController.sendEmailContent(
                'Current V2 payload without explicit parent metadata.',
                new List<AutoFillController.UploadFile>()
            );
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals('FreightTM__Load__c', result.objectType);
        System.assertNotEquals(null, result.recordId);

        Id createdLoadId = result.recordId;
        System.assertEquals(
            0,
            Database.countQuery(
                'SELECT COUNT() FROM FreightTM__Leg__c ' +
                'WHERE FreightTM__Load__c = :createdLoadId'
            ),
            'Legacy V2 fallback may create the parent Load, but it must not guess child objects.'
        );
    }

    @IsTest
    static void webhookUsesTheSameGenericRules() {
        String parentName = 'Webhook Generic Parent ' + String.valueOf(DateTime.now().getTime());
        String childLastName = 'Webhook Explicit Child ' + String.valueOf(DateTime.now().getTime());

        Map<String, Object> payload = new Map<String, Object>{
            'SalesforceObjectType' => 'Account',
            'ExtractedFields' => new Map<String, Object>{
                'Name' => parentName
            },
            'Metadata' => new Map<String, Object>{
                'salesforceChildren' => new List<Object>{
                    new Map<String, Object>{
                        'collectionName' => 'contacts',
                        'objectApiName' => 'Contact',
                        'parentLookupFieldApiName' => 'AccountId'
                    }
                },
                'collections' => new Map<String, Object>{
                    'contacts' => new List<Object>{
                        new Map<String, Object>{
                            'ExtractedFields' => new Map<String, Object>{
                                'LastName' => childLastName
                            }
                        }
                    }
                }
            }
        };

        Test.startTest();
        AutoFillService.ProcessingResult result =
            AutoFillService.createFromExtractionPayloadWithStatus(
                payload,
                null
            );
        Test.stopTest();

        System.assertEquals(true, result.created);
        System.assertNotEquals(null, result.recordId);

        Id webhookParentId = result.recordId;
        Contact createdChild = [
            SELECT Id, AccountId, LastName
            FROM Contact
            WHERE AccountId = :webhookParentId
            LIMIT 1
        ];
        System.assertEquals(childLastName, createdChild.LastName);
    }
}