@IsTest
private class AutoFillFileLifecycleTest {

    private static List<AutoFillController.UploadFile> createFiles() {
        AutoFillController.UploadFile file =
            new AutoFillController.UploadFile();

        file.fileName = 'rate-confirmation-test.pdf';
        file.contentType = 'application/pdf';
        file.base64Data = EncodingUtil.base64Encode(
            Blob.valueOf('AutoFill PDF test content')
        );

        return new List<AutoFillController.UploadFile>{ file };
    }

    private static Id createDraftLoad() {
        FreightLoadSyncHandler.bypassForTests = true;

        Test.setMock(
            HttpCalloutMock.class,
            new AutoFillTestCalloutMock()
        );

        Account customer = new Account(
            Name = 'AutoFill File Test Customer ' + System.now().getTime()
        );
        insert customer;

        Schema.SObjectType loadType =
            Schema.getGlobalDescribe().get('FreightTM__Load__c');
        System.assertNotEquals(null, loadType, 'Load object must be installed.');

        Map<String, Schema.SObjectField> fields =
            loadType.getDescribe().fields.getMap();
        SObject loadRecord = loadType.newSObject();

        putIfCreateable(loadRecord, fields, 'FreightTM__Customer__c', customer.Id);
        putIfCreateable(loadRecord, fields, 'FreightTM__Pickup_City__c', 'Houston');
        putIfCreateable(loadRecord, fields, 'FreightTM__Delivery_City__c', 'Dallas');
        putIfCreateable(loadRecord, fields, 'FreightTM__Pickup_Date__c', Date.today());
        putIfCreateable(loadRecord, fields, 'FreightTM__Delivery_Date__c', Date.today().addDays(1));
        putIfCreateable(loadRecord, fields, 'AutoFill_Status__c', 'Draft');
        putIfCreateable(loadRecord, fields, 'AutoFill_Field_Count__c', 1);
        putIfCreateable(
            loadRecord,
            fields,
            'AutoFill_Detected_Fields__c',
            JSON.serialize(new Map<String, Object>{
                'savedToLoad' => new List<Object>{
                    new Map<String, Object>{
                        'fieldName' => 'Pickup City',
                        'loadFieldApiName' => 'FreightTM__Pickup_City__c',
                        'loadFieldLabel' => 'Pickup City',
                        'value' => 'Houston',
                        'confidence' => 90,
                        'savedToLoad' => true,
                        'reason' => 'Saved to Load'
                    }
                },
                'detectedNotSavedToLoad' => new List<Object>(),
                'rawDetectedFields' => new List<Object>(),
                'summary' => new Map<String, Object>{
                    'savedToLoadCount' => 1,
                    'detectedNotSavedToLoadCount' => 0,
                    'rawDetectedFieldCount' => 0
                }
            })
        );

        AutoFillSafeDml.insertRecord(loadRecord);
        return (Id) loadRecord.get('Id');
    }

    private static void putIfCreateable(
        SObject record,
        Map<String, Schema.SObjectField> fields,
        String fieldApiName,
        Object value
    ) {
        if (!fields.containsKey(fieldApiName)) {
            return;
        }

        Schema.DescribeFieldResult describe =
            fields.get(fieldApiName).getDescribe();

        if (describe.isCreateable() &&
            !describe.isCalculated() &&
            !describe.isAutoNumber()) {
            record.put(fieldApiName, value);
        }
    }

    @IsTest
    static void savesUploadedFileToLoadAndDetectedFields() {
        Id loadId = createDraftLoad();

        Test.startTest();
        Integer savedCount =
            AutoFillController.saveUploadedFilesToLoad(
                loadId,
                createFiles(),
                'item-file-test'
            );
        Test.stopTest();

        System.assertEquals(1, savedCount);

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :loadId
        ];
        System.assertEquals(1, links.size());

        ContentVersion version = [
            SELECT Id, ContentDocumentId, Title, PathOnClient, Description
            FROM ContentVersion
            WHERE ContentDocumentId = :links[0].ContentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];

        System.assertEquals('rate-confirmation-test', version.Title);
        System.assertEquals('rate-confirmation-test.pdf', version.PathOnClient);
        System.assert(version.Description.startsWith('AutoFill Upload'));

        SObject storedLoad = Database.query(
            'SELECT AutoFill_Detected_Fields__c, AutoFill_Field_Count__c ' +
            'FROM FreightTM__Load__c WHERE Id = :loadId LIMIT 1'
        );

        String detectedFieldsJson =
            String.valueOf(storedLoad.get('AutoFill_Detected_Fields__c'));
        System.assert(detectedFieldsJson.contains('Uploaded File'));
        System.assert(detectedFieldsJson.contains('rate-confirmation-test.pdf'));
        System.assert(detectedFieldsJson.contains(String.valueOf(version.ContentDocumentId)));
        System.assertEquals(
            2,
            Decimal.valueOf(String.valueOf(
                storedLoad.get('AutoFill_Field_Count__c')
            )).intValue()
        );
    }

    @IsTest
    static void savesWebhookEmailDocumentForDetectedFieldsPreview() {
        Id loadId = createDraftLoad();
        String base64Body = EncodingUtil.base64Encode(
            Blob.valueOf('Email webhook source document')
        );
        Map<String, Object> webhookPayload = new Map<String, Object>{
            'ItemId' => 'email-webhook-item-001',
            'Documents' => new List<Object>{
                new Map<String, Object>{
                    'FileName' => 'email-source-document.pdf',
                    'ContentType' => 'application/pdf',
                    'Base64Data' => base64Body
                }
            }
        };

        Test.startTest();
        Integer savedCount =
            AutoFillController.saveWebhookFilesToRecord(
                loadId,
                webhookPayload,
                'email-webhook-item-001',
                'FreightTM__Load__c'
            );
        List<AutoFillController.AutoFillFilePreviewRow> previews =
            AutoFillController.getLoadFilePreviews(loadId);
        Test.stopTest();

        System.assertEquals(1, savedCount);
        System.assertEquals(1, previews.size());
        System.assertEquals(
            'email-source-document.pdf',
            previews[0].title
        );
        System.assertEquals(true, previews[0].isPdf);

        SObject storedLoad = Database.query(
            'SELECT AutoFill_Detected_Fields__c ' +
            'FROM FreightTM__Load__c WHERE Id = :loadId LIMIT 1'
        );
        String detectedFieldsJson = String.valueOf(
            storedLoad.get('AutoFill_Detected_Fields__c')
        );

        System.assert(
            detectedFieldsJson.contains('email-source-document.pdf')
        );
    }

    @IsTest
    static void rejectDeletesDraftLoadAndAutoFillFile() {
        Id loadId = createDraftLoad();
        AutoFillController.saveUploadedFilesToLoad(
            loadId,
            createFiles(),
            'item-delete-test'
        );

        ContentDocumentLink link = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :loadId
            LIMIT 1
        ];
        Id contentDocumentId = link.ContentDocumentId;

        Test.startTest();
        AutoFillController.AutoFillRejectResult result =
            AutoFillController.rejectAutoFillLoad(
                loadId,
                'Incorrect document'
            );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(true, result.deleted);
        System.assert(result.message.contains('1 attached file'));

        List<SObject> deletedLoads = Database.query(
            'SELECT Id, IsDeleted FROM FreightTM__Load__c ' +
            'WHERE Id = :loadId ALL ROWS'
        );
        System.assertEquals(1, deletedLoads.size());
        System.assertEquals(true, Boolean.valueOf(String.valueOf(
            deletedLoads[0].get('IsDeleted')
        )));

        System.assertEquals(
            0,
            [SELECT COUNT() FROM ContentDocument WHERE Id = :contentDocumentId]
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :loadId]
        );
    }

    @IsTest
    static void returnsAutoFillPdfForDetectedFieldsPreview() {
        Id loadId = createDraftLoad();
        AutoFillController.saveUploadedFilesToLoad(
            loadId,
            createFiles(),
            'item-preview-test'
        );

        Test.startTest();
        List<AutoFillController.AutoFillFilePreviewRow> previews =
            AutoFillController.getLoadFilePreviews(loadId);
        Test.stopTest();

        System.assertEquals(1, previews.size());
        System.assertNotEquals(null, previews[0].contentDocumentId);
        System.assertNotEquals(null, previews[0].contentVersionId);
        System.assertEquals('rate-confirmation-test.pdf', previews[0].title);
        System.assertEquals(true, previews[0].isPdf);
    }


    @IsTest
    static void approveMarksDraftLoadApprovedAndIsIdempotent() {
        Id loadId = createDraftLoad();

        Test.startTest();
        AutoFillController.approveAutoFillLoad(loadId);
        AutoFillController.approveAutoFillLoad(loadId);
        Test.stopTest();

        Map<String, Schema.SObjectField> loadFields =
            FreightTM__Load__c.SObjectType.getDescribe().fields.getMap();
        String statusFieldName =
            loadFields.get('AutoFill_Status__c').getDescribe().getName();

        SObject approvedLoad = Database.query(
            'SELECT Id, ' + statusFieldName +
            ' FROM FreightTM__Load__c WHERE Id = :loadId LIMIT 1'
        );

        System.assertEquals(
            'Approved',
            String.valueOf(approvedLoad.get('AutoFill_Status__c'))
        );
    }

    @IsTest
    static void approvedLoadCannotBeRejected() {
        Id loadId = createDraftLoad();
        AutoFillController.approveAutoFillLoad(loadId);

        Boolean rejected = false;

        try {
            AutoFillController.rejectAutoFillLoad(
                loadId,
                'Should not be allowed'
            );
        } catch (AuraHandledException expectedException) {
            rejected = true;
        }

        System.assertEquals(
            true,
            rejected,
            'Approved loads must not be rejected.'
        );
    }

    @IsTest
    static void emptyPreviewRequestsReturnNoRows() {
        System.assertEquals(
            0,
            AutoFillController.getLoadFilePreviews(null).size()
        );

        Id loadId = createDraftLoad();

        System.assertEquals(
            0,
            AutoFillController.getLoadFilePreviews(loadId).size()
        );
    }

}