public without sharing class CarrierOnboardingActionHandler {

    private static final String ACTION_DOCUMENT_UPLOADED = 'DOCUMENT_UPLOADED';
    private static final String ACTION_SIGNATURE_SAVED = 'SIGNATURE_SAVED';
    private static final String ACTION_SUBMIT_FOR_REVIEW = 'SUBMIT_FOR_REVIEW';

    public static void handleAfterInsert(List<Carrier_Onboarding_Action__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        List<FreightTM__Carrier__c> carrierUpdates =
            new List<FreightTM__Carrier__c>();

        for (Carrier_Onboarding_Action__e evt : events) {
            try {
                processEvent(evt, carrierUpdates);
            } catch (Exception e) {
                System.debug(
                    'Carrier onboarding event failed. ' +
                    'CarrierId=' + evt.Carrier_Id__c +
                    ', Action=' + evt.Action_Name__c +
                    ', DocumentType=' + evt.Document_Type__c +
                    ', Error=' + e.getTypeName() +
                    ' - ' + e.getMessage()
                );
            }
        }

        if (carrierUpdates.isEmpty()) {
            System.debug('No Carrier onboarding updates to process.');
            return;
        }

        Database.SaveResult[] results =
            Database.update(carrierUpdates, false);

        for (Integer i = 0; i < results.size(); i++) {
            Database.SaveResult sr = results[i];
            FreightTM__Carrier__c carrierUpdate = carrierUpdates[i];

            if (sr.isSuccess()) {
                System.debug(
                    'Carrier onboarding update succeeded: ' +
                    carrierUpdate.Id
                );
                continue;
            }

            for (Database.Error err : sr.getErrors()) {
                System.debug(
                    'Carrier onboarding update failed for ' +
                    carrierUpdate.Id +
                    ': ' +
                    err.getStatusCode() +
                    ' - ' +
                    err.getMessage()
                );
            }
        }
    }

    private static void processEvent(
        Carrier_Onboarding_Action__e evt,
        List<FreightTM__Carrier__c> carrierUpdates
    ) {
        if (String.isBlank(evt.Carrier_Id__c)) {
            System.debug('Skipped Carrier Onboarding event because Carrier_Id__c is blank.');
            return;
        }

        Id carrierId;

        try {
            carrierId = (Id) evt.Carrier_Id__c;
        } catch (Exception e) {
            System.debug('Invalid Carrier Id: ' + evt.Carrier_Id__c);
            return;
        }

        if (
            evt.Action_Name__c != ACTION_DOCUMENT_UPLOADED &&
            evt.Action_Name__c != ACTION_SIGNATURE_SAVED &&
            evt.Action_Name__c != ACTION_SUBMIT_FOR_REVIEW
        ) {
            System.debug('Unsupported Carrier onboarding action: ' + evt.Action_Name__c);
            return;
        }

        if (
            evt.Action_Name__c == ACTION_DOCUMENT_UPLOADED ||
            evt.Action_Name__c == ACTION_SIGNATURE_SAVED
        ) {
            if (
                !String.isBlank(evt.File_Name__c) &&
                !String.isBlank(evt.Base64_Data__c)
            ) {
                createCarrierFile(
                    carrierId,
                    evt.Document_Type__c,
                    evt.File_Name__c,
                    evt.Base64_Data__c
                );
            }
        }

        FreightTM__Carrier__c carrierUpdate =
            new FreightTM__Carrier__c(Id = carrierId);

        if (evt.Action_Name__c == ACTION_DOCUMENT_UPLOADED) {
            applyDocumentUploadStatus(
                carrierUpdate,
                evt.Document_Type__c
            );

            carrierUpdate.FreightTM__On_boarding_Status__c =
                CarrierOnboardingController.resolveOnboardingStatus(
                    CarrierOnboardingController.STATUS_NOT_COMPLETE,
                    CarrierOnboardingController.STATUS_NEW
                );
            carrierUpdate.Overall_Compliance_Status__c =
                'Missing Info';
            carrierUpdate.Ready_for_Loads__c =
                false;

        } else if (evt.Action_Name__c == ACTION_SIGNATURE_SAVED) {
            applySignatureStatus(carrierUpdate);

            carrierUpdate.FreightTM__On_boarding_Status__c =
                CarrierOnboardingController.resolveOnboardingStatus(
                    CarrierOnboardingController.STATUS_NOT_COMPLETE,
                    CarrierOnboardingController.STATUS_NEW
                );
            carrierUpdate.Overall_Compliance_Status__c =
                'Missing Info';
            carrierUpdate.Ready_for_Loads__c =
                false;

        } else if (evt.Action_Name__c == ACTION_SUBMIT_FOR_REVIEW) {
            carrierUpdate.FreightTM__On_boarding_Status__c =
                CarrierOnboardingController.resolveOnboardingStatus(
                    CarrierOnboardingController.STATUS_PAPERWORK_SIGNED,
                    CarrierOnboardingController.STATUS_NOT_COMPLETE
                );
            carrierUpdate.Overall_Compliance_Status__c =
                'Pending Review';
            carrierUpdate.Ready_for_Loads__c =
                false;
        }

        carrierUpdates.add(carrierUpdate);
    }

    private static void createCarrierFile(
        Id carrierId,
        String documentType,
        String originalFileName,
        String base64Data
    ) {
        String renamedFileName =
            buildDocumentFileName(originalFileName, documentType);

        ContentVersion cv = new ContentVersion();
        cv.Title = removeFileExtension(renamedFileName);
        cv.PathOnClient = renamedFileName;
        cv.VersionData = EncodingUtil.base64Decode(base64Data);

        /*
         * This runs from the Platform Event trigger context,
         * not directly from the public Site Guest User request.
         */
        cv.FirstPublishLocationId = carrierId;

        insert cv;

        ContentVersion insertedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        System.debug(
            'Carrier file created. CarrierId=' +
            carrierId +
            ', DocumentType=' +
            documentType +
            ', ContentDocumentId=' +
            insertedVersion.ContentDocumentId
        );
    }

    private static void applyDocumentUploadStatus(
        FreightTM__Carrier__c carrier,
        String documentType
    ) {
        if (documentType == 'W-9') {
            carrier.W_9_File_Uploaded__c = true;
            carrier.W9_Status__c = 'Uploaded';

        } else if (documentType == 'MC Authority') {
            carrier.MC_Authority_File_Uploaded__c = true;
            carrier.MC_Authority_Status__c = 'Uploaded';

        } else if (documentType == 'Certificate of Insurance') {
            carrier.Certificate_of_Insurance_File_Uploaded__c = true;
            carrier.Insurance_COI_Status__c = 'Uploaded';

        } else if (documentType == 'Broker Carrier Agreement') {
            carrier.Agreement_File_Uploaded__c = true;
            carrier.Broker_Carrier_Agreement_Status__c = 'Uploaded';

        } else {
            System.debug('Unsupported Carrier document type: ' + documentType);
        }
    }

    private static void applySignatureStatus(
        FreightTM__Carrier__c carrier
    ) {
        carrier.Signature_File_Uploaded__c = true;
        carrier.Agreement_Status__c = 'Signed';
        carrier.Agreement_Signed_Date__c = System.now();
    }

    private static String buildDocumentFileName(
        String originalFileName,
        String documentType
    ) {
        if (String.isBlank(originalFileName)) {
            originalFileName = 'Carrier Document';
        }

        String extension = '';
        String baseName = originalFileName;

        Integer dotIndex =
            originalFileName.lastIndexOf('.');

        if (dotIndex > 0) {
            baseName =
                originalFileName.substring(0, dotIndex);

            extension =
                originalFileName.substring(dotIndex);
        }

        return baseName + ' - ' + documentType + extension;
    }

    private static String removeFileExtension(String fileName) {
        if (String.isBlank(fileName)) {
            return 'Uploaded File';
        }

        Integer dotIndex =
            fileName.lastIndexOf('.');

        if (dotIndex > 0) {
            return fileName.substring(0, dotIndex);
        }

        return fileName;
    }
}

/*
public without sharing class CarrierOnboardingActionHandler {

    private static final String ACTION_DOCUMENT_UPLOADED = 'DOCUMENT_UPLOADED';
    private static final String ACTION_SIGNATURE_SAVED = 'SIGNATURE_SAVED';

    public static void handleAfterInsert(List<Carrier_Onboarding_Action__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        List<FreightTM__Carrier__c> carrierUpdates = new List<FreightTM__Carrier__c>();

        for (Carrier_Onboarding_Action__e evt : events) {
            try {
                processEvent(evt, carrierUpdates);
            } catch (Exception e) {
                System.debug(
                    'Carrier onboarding event failed. ' +
                    'CarrierId=' + evt.Carrier_Id__c +
                    ', DocumentType=' + evt.Document_Type__c +
                    ', Error=' + e.getTypeName() +
                    ' - ' + e.getMessage()
                );
            }
        }

        if (!carrierUpdates.isEmpty()) {
            Database.SaveResult[] results =
                Database.update(carrierUpdates, false);

            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    System.debug(
                        'Carrier onboarding update succeeded: ' +
                        carrierUpdates[i].Id
                    );
                } else {
                    for (Database.Error err : results[i].getErrors()) {
                        System.debug(
                            'Carrier onboarding update failed for ' +
                            carrierUpdates[i].Id +
                            ': ' +
                            err.getStatusCode() +
                            ' - ' +
                            err.getMessage()
                        );
                    }
                }
            }
        }
    }

    private static void processEvent(
        Carrier_Onboarding_Action__e evt,
        List<FreightTM__Carrier__c> carrierUpdates
    ) {
        if (String.isBlank(evt.Carrier_Id__c)) {
            return;
        }

        Id carrierId;

        try {
            carrierId = (Id) evt.Carrier_Id__c;
        } catch (Exception e) {
            System.debug('Invalid Carrier Id: ' + evt.Carrier_Id__c);
            return;
        }

        if (
            evt.Action_Name__c != ACTION_DOCUMENT_UPLOADED &&
            evt.Action_Name__c != ACTION_SIGNATURE_SAVED
        ) {
            System.debug('Unsupported action: ' + evt.Action_Name__c);
            return;
        }

        Id contentDocumentId;

        if (
            !String.isBlank(evt.File_Name__c) &&
            !String.isBlank(evt.Base64_Data__c)
        ) {
            contentDocumentId = createCarrierFile(
                carrierId,
                evt.Document_Type__c,
                evt.File_Name__c,
                evt.Base64_Data__c
            );
        }

        FreightTM__Carrier__c carrierUpdate =
            new FreightTM__Carrier__c(Id = carrierId);

        if (evt.Action_Name__c == ACTION_DOCUMENT_UPLOADED) {
            applyDocumentUploadStatus(
                carrierUpdate,
                evt.Document_Type__c
            );

        } else if (evt.Action_Name__c == ACTION_SIGNATURE_SAVED) {
            applySignatureStatus(carrierUpdate);
        }

        carrierUpdate.FreightTM__On_boarding_Status__c =
            'Documents Pending';
        carrierUpdate.Overall_Compliance_Status__c =
            'Missing Info';
        carrierUpdate.Ready_for_Loads__c =
            false;

        carrierUpdates.add(carrierUpdate);
    }

    private static Id createCarrierFile(
        Id carrierId,
        String documentType,
        String originalFileName,
        String base64Data
    ) {
        String renamedFileName =
            buildDocumentFileName(originalFileName, documentType);

        ContentVersion cv = new ContentVersion();
        cv.Title = removeFileExtension(renamedFileName);
        cv.PathOnClient = renamedFileName;
        cv.VersionData = EncodingUtil.base64Decode(base64Data);

        cv.FirstPublishLocationId = carrierId;

        insert cv;

        ContentVersion insertedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        System.debug(
            'Carrier file created. CarrierId=' +
            carrierId +
            ', ContentDocumentId=' +
            insertedVersion.ContentDocumentId
        );

        return insertedVersion.ContentDocumentId;
    }

    private static void applyDocumentUploadStatus(
        FreightTM__Carrier__c carrier,
        String documentType
    ) {
        if (documentType == 'W-9') {
            carrier.W_9_File_Uploaded__c = true;
            carrier.W9_Status__c = 'Uploaded';

        } else if (documentType == 'MC Authority') {
            carrier.MC_Authority_File_Uploaded__c = true;
            carrier.MC_Authority_Status__c = 'Uploaded';

        } else if (documentType == 'Certificate of Insurance') {
            carrier.Certificate_of_Insurance_File_Uploaded__c = true;
            carrier.Insurance_COI_Status__c = 'Uploaded';

        } else if (documentType == 'Broker Carrier Agreement') {
            carrier.Agreement_File_Uploaded__c = true;
            carrier.Broker_Carrier_Agreement_Status__c = 'Uploaded';

        } else {
            System.debug('Unsupported Carrier document type: ' + documentType);
        }
    }

    private static void applySignatureStatus(FreightTM__Carrier__c carrier) {
        carrier.Signature_File_Uploaded__c = true;
        carrier.Agreement_Status__c = 'Signed';
        carrier.Agreement_Signed_Date__c = System.now();
    }

    private static String buildDocumentFileName(
        String originalFileName,
        String documentType
    ) {
        if (String.isBlank(originalFileName)) {
            originalFileName = 'Carrier Document';
        }

        String extension = '';
        String baseName = originalFileName;

        Integer dotIndex = originalFileName.lastIndexOf('.');

        if (dotIndex > 0) {
            baseName = originalFileName.substring(0, dotIndex);
            extension = originalFileName.substring(dotIndex);
        }

        return baseName + ' - ' + documentType + extension;
    }

    private static String removeFileExtension(String fileName) {
        if (String.isBlank(fileName)) {
            return 'Uploaded File';
        }

        Integer dotIndex = fileName.lastIndexOf('.');

        if (dotIndex > 0) {
            return fileName.substring(0, dotIndex);
        }

        return fileName;
    }
}
*/