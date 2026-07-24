public without sharing class CarrierOnboardingUploadJob implements Queueable {
    
    private Id carrierId;
    private String documentType;
    private String fileName;
    private String base64Data;
    private Date expirationDate;
    
    public CarrierOnboardingUploadJob(
        Id carrierId,
        String documentType,
        String fileName,
        String base64Data,
        Date expirationDate
    ) {
        this.carrierId = carrierId;
        this.documentType = documentType;
        this.fileName = fileName;
        this.base64Data = base64Data;
        this.expirationDate = expirationDate;
    }
    
    public void execute(QueueableContext context) {
        try {
            validateInput();
            
            String renamedFileName =
                buildDocumentFileName(fileName, documentType);
            
            ContentVersion cv = new ContentVersion();
            cv.Title = removeFileExtension(renamedFileName);
            cv.PathOnClient = renamedFileName;
            cv.VersionData = EncodingUtil.base64Decode(base64Data);
            
            /*
* Attach directly to the Carrier Files related list.
* Do not set OwnerId manually.
*/
            cv.FirstPublishLocationId = carrierId;
            
            insert cv;
            
            ContentVersion insertedVersion = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :cv.Id
                LIMIT 1
            ];
            
            /*
* Only publish the platform event for updating Carrier fields.
* Do not send base64 data in the platform event.
*/
            publishCarrierOnboardingAction(
                carrierId,
                documentType,
                insertedVersion.ContentDocumentId
            );
            
        } catch (Exception e) {
            logUploadFailure(
                carrierId,
                documentType,
                e
            );
        }
    }
    
    private void validateInput() {
        if (carrierId == null) {
            throw new CarrierOnboardingUploadException('Carrier Id is required.');
        }
        
        if (String.isBlank(documentType)) {
            throw new CarrierOnboardingUploadException('Document Type is required.');
        }
        
        if (String.isBlank(fileName)) {
            throw new CarrierOnboardingUploadException('File Name is required.');
        }
        
        if (String.isBlank(base64Data)) {
            throw new CarrierOnboardingUploadException('File Data is required.');
        }
    }
    
    private static void publishCarrierOnboardingAction(
        Id carrierId,
        String documentType,
        Id contentDocumentId
    ) {
        Carrier_Onboarding_Action__e evt =
            new Carrier_Onboarding_Action__e();
        
        evt.Carrier_Id__c = String.valueOf(carrierId);
        evt.Document_Type__c = documentType;
        evt.Content_Document_Id__c = String.valueOf(contentDocumentId);
        evt.Event_Time__c = System.now();
        
        if (documentType == 'Signature') {
            evt.Action_Name__c = 'SIGNATURE_SAVED';
        } else {
            evt.Action_Name__c = 'DOCUMENT_UPLOADED';
        }
        
        Database.SaveResult publishResult =
            EventBus.publish(evt);
        
        if (!publishResult.isSuccess()) {
            for (Database.Error err : publishResult.getErrors()) {
                System.debug(
                    'Carrier onboarding platform event publish failed. ' +
                    'CarrierId=' + carrierId +
                    ', DocumentType=' + documentType +
                    ', ContentDocumentId=' + contentDocumentId +
                    ', Error=' + err.getStatusCode() +
                    ' - ' + err.getMessage()
                );
            }
        } else {
            System.debug(
                'Carrier onboarding platform event published. ' +
                'CarrierId=' + carrierId +
                ', DocumentType=' + documentType +
                ', ContentDocumentId=' + contentDocumentId
            );
        }
    }
    
    private static void logUploadFailure(
        Id carrierId,
        String documentType,
        Exception e
    ) {
        /*
* Do not update Carrier here.
* The Carrier field update is handled by CarrierOnboardingActionHandler
* after the platform event is published.
*/
        System.debug(
            'Carrier onboarding upload failed. ' +
            'CarrierId=' + carrierId +
            ', DocumentType=' + documentType +
            ', Error=' + e.getTypeName() +
            ' - ' + e.getMessage()
        );
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
    
    public class CarrierOnboardingUploadException extends Exception {}
}