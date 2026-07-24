public with sharing class DriverPortalLinkAdminController {
    public class LinkResponse {
        @AuraEnabled public Id loadId;
        @AuraEnabled public String portalLink;
        @AuraEnabled public Boolean portalActive;
        @AuraEnabled public Datetime expiresAt;
    }

    @AuraEnabled
    public static LinkResponse generateOrRefresh(Id loadId) {
        return generateOrRefreshInternal(loadId);
    }

    public static LinkResponse generateOrRefreshInternal(Id loadId) {
        if (loadId == null) {
            throw handledException('A Load record is required.');
        }

        FreightTM__Load__c loadRecord = [
            SELECT Id,
                   FreightTM__Driver__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];

        if (loadRecord.FreightTM__Driver__c == null) {
            throw handledException(
                'Assign a Driver to the Load before generating the Driver Portal link.'
            );
        }

        String siteBaseUrl =
            System.Label.Driver_Portal_Base_URL;

        if (
            String.isBlank(siteBaseUrl) ||
            siteBaseUrl.contains('YOUR-SITE-DOMAIN')
        ) {
            throw handledException(
                'Configure the Driver Portal Base URL Custom Label before generating the link.'
            );
        }

        DriverLoadPortalTokenService.LinkResult generated =
            DriverLoadPortalTokenService.generateLink(
                loadId,
                siteBaseUrl
            );

        FreightTM__Load__c finalLoad = [
            SELECT Id,
                   Driver_Portal_Link__c,
                   Driver_Portal_Active__c,
                   Driver_Portal_Expires_At__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];

        LinkResponse response = new LinkResponse();
        response.loadId = finalLoad.Id;
        response.portalLink = finalLoad.Driver_Portal_Link__c;
        response.portalActive =
            finalLoad.Driver_Portal_Active__c;
        response.expiresAt =
            finalLoad.Driver_Portal_Expires_At__c;
        return response;
    }

    @AuraEnabled(cacheable=true)
    public static LinkResponse getStatus(Id loadId) {
        if (loadId == null) {
            return null;
        }

        FreightTM__Load__c loadRecord = [
            SELECT Id,
                   Driver_Portal_Link__c,
                   Driver_Portal_Active__c,
                   Driver_Portal_Expires_At__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];

        LinkResponse response = new LinkResponse();
        response.loadId = loadRecord.Id;
        response.portalLink =
            loadRecord.Driver_Portal_Link__c;
        response.portalActive =
            loadRecord.Driver_Portal_Active__c;
        response.expiresAt =
            loadRecord.Driver_Portal_Expires_At__c;
        return response;
    }

    private static AuraHandledException handledException(
        String message
    ) {
        AuraHandledException errorValue =
            new AuraHandledException(message);
        errorValue.setMessage(message);
        return errorValue;
    }
}
