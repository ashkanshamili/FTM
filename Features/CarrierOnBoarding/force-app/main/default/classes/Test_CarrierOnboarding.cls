@IsTest
private class Test_CarrierOnboarding {

    private static Integer sequenceNumber = 0;

    private static String nextToken() {
        sequenceNumber++;
        return String.valueOf(sequenceNumber);
    }

    private static String validBase64(String textValue) {
        return EncodingUtil.base64Encode(Blob.valueOf(textValue));
    }

    // Keep the test independent from controller constants/helper methods that
    // may not exist in older org versions.
    private static String getActiveOnboardingStatus() {
        List<Schema.PicklistEntry> entries =
            FreightTM__Carrier__c.FreightTM__On_boarding_Status__c
                .getDescribe()
                .getPicklistValues();

        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }

    private static CarrierOnboardingController.CarrierInput buildValidInput() {
        String token = nextToken();

        CarrierOnboardingController.CarrierInput input =
            new CarrierOnboardingController.CarrierInput();

        input.carrierName = 'QA Carrier Onboarding ' + token;
        input.mcNumber = 'MC' + token;
        input.usdotNumber = null;
        input.federalId = 'FED' + token;
        input.scacCode = 'Q' + token;
        input.website = 'https://example.com';

        input.primaryContact = 'QA Contact ' + token;
        input.title = 'Operations';
        input.email = 'carrier' + token + '@example.com';
        input.phone = '555100' + token;
        input.afterHoursPhone = '555200' + token;

        input.street = '100 Test Street';
        input.city = 'Los Angeles';
        input.country = 'United States';
        input.stateProvince = 'CA';
        input.zipCode = '90001';

        input.billingStreet = '200 Billing Street';
        input.billingCity = 'Los Angeles';
        input.billingCountry = 'United States';
        input.billingStateProvince = 'CA';
        input.billingZipCode = '90002';

        input.mode = null;
        input.ltl = false;
        input.hazmatPermit = false;
        input.preferredLanes = 'CA-TX';
        input.numberOfDrivers = 5;
        input.numberOfTractors = 4;
        input.numberOfTrailers = 6;
        input.onlineGpsTracking = true;

        input.cargoInsuranceAmount = 100000;
        input.cargoInsuranceExpiration = Date.today().addYears(1);
        input.liabilityInsuranceAmount = 1000000;
        input.liabilityInsuranceExpiration = Date.today().addYears(1);

        input.remarks = 'Created by Carrier Onboarding Apex test.';
        input.agreementAccepted = true;
        input.agreementSignedBy = 'QA Signer ' + token;

        return input;
    }

    private static FreightTM__Carrier__c createCarrier(
        String label,
        Boolean agreementReady,
        Boolean documentsReady
    ) {
        String token = nextToken();

        FreightTM__Carrier__c carrier = new FreightTM__Carrier__c();
        carrier.Name = 'QA ' + label + ' ' + token;
        carrier.FreightTM__MC_MX_FF_Number__c = 'MC' + token;
        carrier.FreightTM__Email__c =
            'directcarrier' + token + '@example.com';
        carrier.FreightTM__Phone__c = '555300' + token;
        carrier.FreightTM__Primary_Contact__c = 'QA Contact';
        carrier.FreightTM__Preferred_Lanes__c = 'CA-AZ';
        carrier.FreightTM__Number_of_Drivers__c = 1;
        carrier.FreightTM__Number_of_Tractors__c = 1;
        carrier.FreightTM__Number_of_Trailers__c = 1;
        carrier.FreightTM__Cargo_Insurance_Amount__c = 100000;
        carrier.FreightTM__Cargo_Insurance_Expiration__c =
            Date.today().addYears(1);
        carrier.FreightTM__Liability_Insurance_Amount__c = 1000000;
        carrier.FreightTM__Liability_Insurance_Expiration__c =
            Date.today().addYears(1);
        String activeOnboardingStatus = getActiveOnboardingStatus();
        if (!String.isBlank(activeOnboardingStatus)) {
            carrier.FreightTM__On_boarding_Status__c =
                activeOnboardingStatus;
        }
        carrier.Overall_Compliance_Status__c = 'Missing Info';
        carrier.Ready_for_Loads__c = false;
        carrier.Public_Onboarding_Access__c = true;

        if (agreementReady == true) {
            carrier.Agreement_Status__c = 'Signed';
            carrier.Signature_File_Uploaded__c = true;
            carrier.Agreement_Signed_Date__c = System.now();
            carrier.Agreement_Signed_By__c = 'QA Signer';
        } else {
            carrier.Agreement_Status__c = 'Pending';
            carrier.Signature_File_Uploaded__c = false;
            carrier.Agreement_File_Uploaded__c = false;
        }

        if (documentsReady == true) {
            carrier.W_9_File_Uploaded__c = true;
            carrier.MC_Authority_File_Uploaded__c = true;
            carrier.Certificate_of_Insurance_File_Uploaded__c = true;
        } else {
            carrier.W_9_File_Uploaded__c = false;
            carrier.MC_Authority_File_Uploaded__c = false;
            carrier.Certificate_of_Insurance_File_Uploaded__c = false;
        }

        insert as system carrier;
        return carrier;
    }

    private static void assertSaveFailure(
        CarrierOnboardingController.CarrierInput input,
        String expectedText
    ) {
        CarrierOnboardingController.OnboardingResult result =
            CarrierOnboardingController.saveCarrier(input);

        System.assertEquals(
            false,
            result.success,
            'The invalid Carrier input should fail.'
        );
        System.assert(
            result.message != null &&
            result.message.contains(expectedText),
            'Expected "' + expectedText + '" but received: ' + result.message
        );
    }

    private static void assertUploadFailure(
        CarrierOnboardingController.DocumentInput input,
        String expectedText
    ) {
        CarrierOnboardingController.OnboardingResult result =
            CarrierOnboardingController.uploadCarrierDocument(input);

        System.assertEquals(false, result.success);
        System.assert(
            result.message != null &&
            result.message.contains(expectedText),
            'Expected "' + expectedText + '" but received: ' + result.message
        );
    }

    private static Carrier_Onboarding_Action__e buildEvent(
        Id carrierId,
        String actionName,
        String documentType,
        String fileName,
        String base64Data
    ) {
        Carrier_Onboarding_Action__e eventRecord =
            new Carrier_Onboarding_Action__e();

        eventRecord.Carrier_Id__c =
            carrierId == null ? null : String.valueOf(carrierId);
        eventRecord.Action_Name__c = actionName;
        eventRecord.Document_Type__c = documentType;
        eventRecord.File_Name__c = fileName;
        eventRecord.Base64_Data__c = base64Data;
        eventRecord.Event_Time__c = System.now();

        return eventRecord;
    }

    @IsTest
    static void testSaveCarrierCreateAndUpdate() {
        CarrierOnboardingController.CarrierInput createInput =
            buildValidInput();

        Test.startTest();
        CarrierOnboardingController.OnboardingResult createResult =
            CarrierOnboardingController.saveCarrier(createInput);
        Test.stopTest();

        System.assertEquals(
            true,
            createResult.success,
            createResult.message
        );
        System.assertNotEquals(null, createResult.carrierId);

        FreightTM__Carrier__c createdCarrier = [
            SELECT Id,
                   Name,
                   FreightTM__Email__c,
                   FreightTM__Phone__c,
                   Agreement_Status__c,
                   Agreement_Signed_By__c,
                   Ready_for_Loads__c,
                   Public_Onboarding_Access__c
            FROM FreightTM__Carrier__c
            WHERE Id = :createResult.carrierId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        System.assertEquals(createInput.carrierName, createdCarrier.Name);
        System.assertEquals(createInput.email, createdCarrier.FreightTM__Email__c);
        System.assertEquals('Signed', createdCarrier.Agreement_Status__c);
        System.assertEquals(false, createdCarrier.Ready_for_Loads__c);
        System.assertEquals(true, createdCarrier.Public_Onboarding_Access__c);

        createInput.carrierId = createdCarrier.Id;
        createInput.carrierName = 'QA Carrier Updated';
        createInput.remarks = 'Updated through saveCarrier.';

        CarrierOnboardingController.OnboardingResult updateResult =
            CarrierOnboardingController.saveCarrier(createInput);

        System.assertEquals(true, updateResult.success, updateResult.message);
        System.assertEquals(createdCarrier.Id, updateResult.carrierId);

        FreightTM__Carrier__c updatedCarrier = [
            SELECT Name, FreightTM__Remarks__c
            FROM FreightTM__Carrier__c
            WHERE Id = :createdCarrier.Id
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        System.assertEquals('QA Carrier Updated', updatedCarrier.Name);
        System.assertEquals(
            'Updated through saveCarrier.',
            updatedCarrier.FreightTM__Remarks__c
        );

        CarrierOnboardingController.CarrierInput wrongIdInput =
            buildValidInput();
        wrongIdInput.carrierId = UserInfo.getUserId();

        CarrierOnboardingController.OnboardingResult wrongIdResult =
            CarrierOnboardingController.saveCarrier(wrongIdInput);

        System.assertEquals(false, wrongIdResult.success);
        System.assert(
            wrongIdResult.message.contains('Save failed:'),
            wrongIdResult.message
        );
    }

    @IsTest
    static void testSaveCarrierValidationBranches() {
        assertSaveFailure(null, 'Carrier data is required.');

        CarrierOnboardingController.CarrierInput input = buildValidInput();
        input.carrierName = ' ';
        assertSaveFailure(input, 'Carrier Name is required.');

        input = buildValidInput();
        input.email = null;
        assertSaveFailure(input, 'Email is required.');

        input = buildValidInput();
        input.phone = '';
        assertSaveFailure(input, 'Phone is required.');

        input = buildValidInput();
        input.mcNumber = null;
        input.usdotNumber = null;
        assertSaveFailure(
            input,
            'MC/MX/FF Number or USDOT Number is required.'
        );

        input = buildValidInput();
        input.scacCode = 'TOOLONG';
        assertSaveFailure(
            input,
            'SCAC Code must be 5 characters or less.'
        );

        input = buildValidInput();
        input.mcNumber = '12345678901';
        assertSaveFailure(
            input,
            'MC/MX/FF Number must be 10 characters or less.'
        );

        input = buildValidInput();
        input.mcNumber = null;
        input.usdotNumber = '12345678901';
        assertSaveFailure(
            input,
            'USDOT Number must be 10 characters or less.'
        );

        input = buildValidInput();
        input.federalId = '12345678901';
        assertSaveFailure(
            input,
            'Federal ID must be 10 characters or less.'
        );

        input = buildValidInput();
        input.zipCode = '12345678901';
        assertSaveFailure(
            input,
            'Zip Code must be 10 characters or less.'
        );

        input = buildValidInput();
        input.billingZipCode = '12345678901';
        assertSaveFailure(
            input,
            'Billing Zip Code must be 10 characters or less.'
        );

        input = buildValidInput();
        input.primaryContact = null;
        assertSaveFailure(input, 'Primary Contact is required.');

        input = buildValidInput();
        input.preferredLanes = '';
        assertSaveFailure(input, 'Preferred Lanes is required.');

        input = buildValidInput();
        input.numberOfDrivers = null;
        assertSaveFailure(input, 'Number of Drivers is required.');

        input = buildValidInput();
        input.numberOfDrivers = -1;
        assertSaveFailure(input, 'Number of Drivers cannot be negative.');

        input = buildValidInput();
        input.numberOfTractors = null;
        assertSaveFailure(input, 'Number of Tractors is required.');

        input = buildValidInput();
        input.numberOfTractors = -1;
        assertSaveFailure(input, 'Number of Tractors cannot be negative.');

        input = buildValidInput();
        input.numberOfTrailers = null;
        assertSaveFailure(input, 'Number of Trailers is required.');

        input = buildValidInput();
        input.numberOfTrailers = -1;
        assertSaveFailure(input, 'Number of Trailers cannot be negative.');

        input = buildValidInput();
        input.cargoInsuranceAmount = null;
        assertSaveFailure(input, 'Cargo Insurance Amount is required.');

        input = buildValidInput();
        input.cargoInsuranceAmount = 0;
        assertSaveFailure(
            input,
            'Cargo Insurance Amount must be greater than zero.'
        );

        input = buildValidInput();
        input.cargoInsuranceExpiration = null;
        assertSaveFailure(
            input,
            'Cargo Insurance Expiration is required.'
        );

        input = buildValidInput();
        input.liabilityInsuranceAmount = null;
        assertSaveFailure(
            input,
            'Liability Insurance Amount is required.'
        );

        input = buildValidInput();
        input.liabilityInsuranceAmount = 0;
        assertSaveFailure(
            input,
            'Liability Insurance Amount must be greater than zero.'
        );

        input = buildValidInput();
        input.liabilityInsuranceExpiration = null;
        assertSaveFailure(
            input,
            'Liability Insurance Expiration is required.'
        );

        input = buildValidInput();
        input.agreementAccepted = false;
        assertSaveFailure(
            input,
            'You must accept the broker-carrier agreement'
        );

        input = buildValidInput();
        input.agreementSignedBy = ' ';
        assertSaveFailure(
            input,
            'Signed By is required before continuing.'
        );

        input = buildValidInput();
        input.mode = 'Invalid Mode';
        assertSaveFailure(input, 'Invalid Mode value: Invalid Mode');
    }

    @IsTest
    static void testUploadCarrierDocumentValidationAndSuccess() {
        assertUploadFailure(null, 'Upload failed:');

        CarrierOnboardingController.DocumentInput input =
            new CarrierOnboardingController.DocumentInput();
        assertUploadFailure(
            input,
            'Carrier record is required before uploading documents.'
        );

        FreightTM__Carrier__c carrier =
            createCarrier('Upload Validation', false, false);

        input = new CarrierOnboardingController.DocumentInput();
        input.carrierId = carrier.Id;
        assertUploadFailure(input, 'Document Type is required.');

        input.documentType = 'W-9';
        assertUploadFailure(input, 'File name is required.');

        input.fileName = 'w9.pdf';
        assertUploadFailure(input, 'File data is required.');

        input.base64Data = validBase64('W9 test file');

        Test.startTest();
        CarrierOnboardingController.OnboardingResult result =
            CarrierOnboardingController.uploadCarrierDocument(input);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(carrier.Id, result.carrierId);

        FreightTM__Carrier__c updatedCarrier = [
            SELECT W_9_File_Uploaded__c,
                   W9_Status__c,
                   Overall_Compliance_Status__c,
                   Ready_for_Loads__c
            FROM FreightTM__Carrier__c
            WHERE Id = :carrier.Id
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        System.assertEquals(true, updatedCarrier.W_9_File_Uploaded__c);
        System.assertEquals('Uploaded', updatedCarrier.W9_Status__c);
        System.assertEquals('Missing Info', updatedCarrier.Overall_Compliance_Status__c);
        System.assertEquals(false, updatedCarrier.Ready_for_Loads__c);

        Integer fileLinkCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :carrier.Id
            WITH SYSTEM_MODE
        ];
        System.assert(fileLinkCount > 0, 'The W-9 file should be attached.');
    }

    @IsTest
    static void testUploadSignatureEvent() {
        FreightTM__Carrier__c carrier =
            createCarrier('Signature Upload', false, false);

        CarrierOnboardingController.DocumentInput input =
            new CarrierOnboardingController.DocumentInput();

        input.carrierId = carrier.Id;
        input.documentType = 'Signature';
        input.fileName = 'signature.png';
        input.base64Data = validBase64('signature image');

        Test.startTest();
        CarrierOnboardingController.OnboardingResult result =
            CarrierOnboardingController.uploadCarrierDocument(input);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);

        FreightTM__Carrier__c updatedCarrier = [
            SELECT Signature_File_Uploaded__c,
                   Agreement_Status__c,
                   Agreement_Signed_Date__c
            FROM FreightTM__Carrier__c
            WHERE Id = :carrier.Id
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        System.assertEquals(true, updatedCarrier.Signature_File_Uploaded__c);
        System.assertEquals('Signed', updatedCarrier.Agreement_Status__c);
        System.assertNotEquals(null, updatedCarrier.Agreement_Signed_Date__c);
    }

    @IsTest
    static void testSubmitForReviewBranches() {
        CarrierOnboardingController.OnboardingResult nullResult =
            CarrierOnboardingController.submitForReview(null);

        System.assertEquals(false, nullResult.success);
        System.assert(
            nullResult.message.contains('Carrier Id is required.'),
            nullResult.message
        );

        FreightTM__Carrier__c missingAgreement =
            createCarrier('Missing Agreement', false, true);

        CarrierOnboardingController.OnboardingResult agreementResult =
            CarrierOnboardingController.submitForReview(
                missingAgreement.Id
            );

        System.assertEquals(false, agreementResult.success);
        System.assert(
            agreementResult.message.contains(
                'Agreement must be signed or uploaded'
            ),
            agreementResult.message
        );

        FreightTM__Carrier__c missingDocuments =
            createCarrier('Missing Documents', true, false);

        CarrierOnboardingController.OnboardingResult documentsResult =
            CarrierOnboardingController.submitForReview(
                missingDocuments.Id
            );

        System.assertEquals(false, documentsResult.success);
        System.assert(
            documentsResult.message.contains(
                'Required documents are missing.'
            ),
            documentsResult.message
        );

        FreightTM__Carrier__c readyCarrier =
            createCarrier('Ready For Review', true, true);

        Test.startTest();
        CarrierOnboardingController.OnboardingResult successResult =
            CarrierOnboardingController.submitForReview(readyCarrier.Id);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(true, successResult.success, successResult.message);
        System.assertEquals(readyCarrier.Id, successResult.carrierId);

        FreightTM__Carrier__c reviewedCarrier = [
            SELECT Overall_Compliance_Status__c,
                   Ready_for_Loads__c,
                   FreightTM__On_boarding_Status__c
            FROM FreightTM__Carrier__c
            WHERE Id = :readyCarrier.Id
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        System.assertEquals(
            'Pending Review',
            reviewedCarrier.Overall_Compliance_Status__c
        );
        System.assertEquals(false, reviewedCarrier.Ready_for_Loads__c);
        System.assertNotEquals(
            null,
            reviewedCarrier.FreightTM__On_boarding_Status__c
        );
    }

    @IsTest
    static void testActionHandlerInvalidAndFailureBranches() {
        CarrierOnboardingActionHandler.handleAfterInsert(null);
        CarrierOnboardingActionHandler.handleAfterInsert(
            new List<Carrier_Onboarding_Action__e>()
        );

        FreightTM__Carrier__c carrier =
            createCarrier('Handler Invalid Events', false, false);

        List<Carrier_Onboarding_Action__e> invalidEvents =
            new List<Carrier_Onboarding_Action__e>{
                new Carrier_Onboarding_Action__e(
                    Action_Name__c = 'DOCUMENT_UPLOADED',
                    Document_Type__c = 'W-9'
                ),
                new Carrier_Onboarding_Action__e(
                    Carrier_Id__c = 'not-an-id',
                    Action_Name__c = 'DOCUMENT_UPLOADED',
                    Document_Type__c = 'W-9'
                ),
                new Carrier_Onboarding_Action__e(
                    Carrier_Id__c = String.valueOf(carrier.Id),
                    Action_Name__c = 'UNSUPPORTED_ACTION',
                    Document_Type__c = 'W-9'
                )
            };

        Test.startTest();
        CarrierOnboardingActionHandler.handleAfterInsert(invalidEvents);
        Test.stopTest();

        Carrier_Onboarding_Action__e invalidBase64Event =
            buildEvent(
                carrier.Id,
                'DOCUMENT_UPLOADED',
                'W-9',
                'invalid.pdf',
                '%%%not-base64%%%'
            );

        CarrierOnboardingActionHandler.handleAfterInsert(
            new List<Carrier_Onboarding_Action__e>{
                invalidBase64Event
            }
        );

        FreightTM__Carrier__c deletedCarrier =
            createCarrier('Deleted Handler Carrier', false, false);
        Id deletedCarrierId = deletedCarrier.Id;
        delete as system deletedCarrier;

        CarrierOnboardingActionHandler.handleAfterInsert(
            new List<Carrier_Onboarding_Action__e>{
                buildEvent(
                    deletedCarrierId,
                    'DOCUMENT_UPLOADED',
                    'W-9',
                    null,
                    null
                )
            }
        );

        System.assert(true, 'Invalid Handler branches completed.');
    }

    @IsTest
    static void testActionHandlerDocumentTypesAndFiles() {
        FreightTM__Carrier__c w9Carrier =
            createCarrier('Handler W9', false, false);
        FreightTM__Carrier__c mcCarrier =
            createCarrier('Handler MC', false, false);
        FreightTM__Carrier__c insuranceCarrier =
            createCarrier('Handler Insurance', false, false);
        FreightTM__Carrier__c agreementCarrier =
            createCarrier('Handler Agreement', false, false);
        FreightTM__Carrier__c unknownCarrier =
            createCarrier('Handler Unknown', false, false);
        FreightTM__Carrier__c signatureCarrier =
            createCarrier('Handler Signature', false, false);
        FreightTM__Carrier__c submitCarrier =
            createCarrier('Handler Submit', true, true);

        Test.startTest();

        CarrierOnboardingActionHandler.handleAfterInsert(
            new List<Carrier_Onboarding_Action__e>{
                buildEvent(
                    w9Carrier.Id,
                    'DOCUMENT_UPLOADED',
                    'W-9',
                    'w9.pdf',
                    validBase64('w9 content')
                )
            }
        );

        CarrierOnboardingActionHandler.handleAfterInsert(
            new List<Carrier_Onboarding_Action__e>{
                buildEvent(
                    mcCarrier.Id,
                    'DOCUMENT_UPLOADED',
                    'MC Authority',
                    null,
                    null
                )
            }
        );

        CarrierOnboardingActionHandler.handleAfterInsert(
            new List<Carrier_Onboarding_Action__e>{
                buildEvent(
                    insuranceCarrier.Id,
                    'DOCUMENT_UPLOADED',
                    'Certificate of Insurance',
                    null,
                    null
                )
            }
        );

        CarrierOnboardingActionHandler.handleAfterInsert(
            new List<Carrier_Onboarding_Action__e>{
                buildEvent(
                    agreementCarrier.Id,
                    'DOCUMENT_UPLOADED',
                    'Broker Carrier Agreement',
                    null,
                    null
                )
            }
        );

        CarrierOnboardingActionHandler.handleAfterInsert(
            new List<Carrier_Onboarding_Action__e>{
                buildEvent(
                    unknownCarrier.Id,
                    'DOCUMENT_UPLOADED',
                    'Unknown Document',
                    null,
                    null
                )
            }
        );

        CarrierOnboardingActionHandler.handleAfterInsert(
            new List<Carrier_Onboarding_Action__e>{
                buildEvent(
                    signatureCarrier.Id,
                    'SIGNATURE_SAVED',
                    'Signature',
                    null,
                    null
                )
            }
        );

        CarrierOnboardingActionHandler.handleAfterInsert(
            new List<Carrier_Onboarding_Action__e>{
                buildEvent(
                    submitCarrier.Id,
                    'SUBMIT_FOR_REVIEW',
                    null,
                    null,
                    null
                )
            }
        );

        Test.stopTest();

        Set<Id> carrierIds = new Set<Id>{
            w9Carrier.Id,
            mcCarrier.Id,
            insuranceCarrier.Id,
            agreementCarrier.Id,
            unknownCarrier.Id,
            signatureCarrier.Id,
            submitCarrier.Id
        };

        Map<Id, FreightTM__Carrier__c> carriersById =
            new Map<Id, FreightTM__Carrier__c>([
                SELECT Id,
                       W_9_File_Uploaded__c,
                       W9_Status__c,
                       MC_Authority_File_Uploaded__c,
                       MC_Authority_Status__c,
                       Certificate_of_Insurance_File_Uploaded__c,
                       Insurance_COI_Status__c,
                       Agreement_File_Uploaded__c,
                       Broker_Carrier_Agreement_Status__c,
                       Signature_File_Uploaded__c,
                       Agreement_Status__c,
                       Agreement_Signed_Date__c,
                       Overall_Compliance_Status__c,
                       Ready_for_Loads__c
                FROM FreightTM__Carrier__c
                WHERE Id IN :carrierIds
                WITH SYSTEM_MODE
            ]);

        System.assertEquals(
            true,
            carriersById.get(w9Carrier.Id).W_9_File_Uploaded__c
        );
        System.assertEquals(
            'Uploaded',
            carriersById.get(w9Carrier.Id).W9_Status__c
        );

        System.assertEquals(
            true,
            carriersById.get(mcCarrier.Id).MC_Authority_File_Uploaded__c
        );
        System.assertEquals(
            'Uploaded',
            carriersById.get(mcCarrier.Id).MC_Authority_Status__c
        );

        System.assertEquals(
            true,
            carriersById.get(insuranceCarrier.Id)
                .Certificate_of_Insurance_File_Uploaded__c
        );
        System.assertEquals(
            'Uploaded',
            carriersById.get(insuranceCarrier.Id).Insurance_COI_Status__c
        );

        System.assertEquals(
            true,
            carriersById.get(agreementCarrier.Id).Agreement_File_Uploaded__c
        );
        System.assertEquals(
            'Uploaded',
            carriersById.get(agreementCarrier.Id)
                .Broker_Carrier_Agreement_Status__c
        );

        System.assertEquals(
            true,
            carriersById.get(signatureCarrier.Id).Signature_File_Uploaded__c
        );
        System.assertEquals(
            'Signed',
            carriersById.get(signatureCarrier.Id).Agreement_Status__c
        );
        System.assertNotEquals(
            null,
            carriersById.get(signatureCarrier.Id).Agreement_Signed_Date__c
        );

        System.assertEquals(
            'Pending Review',
            carriersById.get(submitCarrier.Id).Overall_Compliance_Status__c
        );
        System.assertEquals(
            false,
            carriersById.get(submitCarrier.Id).Ready_for_Loads__c
        );

        Integer w9FileCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :w9Carrier.Id
            WITH SYSTEM_MODE
        ];
        System.assertEquals(1, w9FileCount);
    }

    @IsTest
    static void testUploadJobValidAndInvalidBranches() {
        FreightTM__Carrier__c carrier =
            createCarrier('Upload Job W9', false, false);

        new CarrierOnboardingUploadJob(
            null,
            'W-9',
            'missing-carrier.pdf',
            validBase64('data'),
            null
        ).execute(null);

        new CarrierOnboardingUploadJob(
            carrier.Id,
            null,
            'missing-document-type.pdf',
            validBase64('data'),
            null
        ).execute(null);

        new CarrierOnboardingUploadJob(
            carrier.Id,
            'W-9',
            null,
            validBase64('data'),
            null
        ).execute(null);

        new CarrierOnboardingUploadJob(
            carrier.Id,
            'W-9',
            'missing-data.pdf',
            null,
            null
        ).execute(null);

        Test.startTest();
        new CarrierOnboardingUploadJob(
            carrier.Id,
            'W-9',
            'queue-w9.pdf',
            validBase64('queueable W9 data'),
            Date.today().addYears(1)
        ).execute(null);
        Test.getEventBus().deliver();
        Test.stopTest();

        FreightTM__Carrier__c updatedCarrier = [
            SELECT W_9_File_Uploaded__c,
                   W9_Status__c
            FROM FreightTM__Carrier__c
            WHERE Id = :carrier.Id
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        System.assertEquals(true, updatedCarrier.W_9_File_Uploaded__c);
        System.assertEquals('Uploaded', updatedCarrier.W9_Status__c);

        List<ContentDocumentLink> links = [
            SELECT Id, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :carrier.Id
            WITH SYSTEM_MODE
        ];
        System.assert(links.size() > 0, 'The Queueable should attach a file.');

        FreightTM__Carrier__c signatureCarrier =
            createCarrier('Upload Job Signature', false, false);

        new CarrierOnboardingUploadJob(
            signatureCarrier.Id,
            'Signature',
            'signaturefile',
            validBase64('signature data'),
            null
        ).execute(null);
        Test.getEventBus().deliver();

        FreightTM__Carrier__c updatedSignatureCarrier = [
            SELECT Signature_File_Uploaded__c,
                   Agreement_Status__c
            FROM FreightTM__Carrier__c
            WHERE Id = :signatureCarrier.Id
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        System.assertEquals(
            true,
            updatedSignatureCarrier.Signature_File_Uploaded__c
        );
        System.assertEquals(
            'Signed',
            updatedSignatureCarrier.Agreement_Status__c
        );
    }
}
