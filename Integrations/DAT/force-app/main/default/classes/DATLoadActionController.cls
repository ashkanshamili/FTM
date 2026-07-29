public with sharing class DATLoadActionController {
    public class State {
        @AuraEnabled public Boolean configured { get; set; }
        @AuraEnabled public Boolean authorized { get; set; }
        @AuraEnabled public String environmentLabel { get; set; }
        @AuraEnabled public String postId { get; set; }
        @AuraEnabled public String shipmentId { get; set; }
        @AuraEnabled public Boolean canPost { get; set; }
        @AuraEnabled public Boolean canUpdate { get; set; }
        @AuraEnabled public Boolean canDelete { get; set; }
        @AuraEnabled public String message { get; set; }
    }

    @TestVisible
    private static Boolean bypassPermissionForTests = false;

    @AuraEnabled(cacheable=true)
    public static State getState(Id recordId) {
        State state = new State();
        state.authorized = hasPermission();
        DATIntegrationConfig.Settings settings = DATIntegrationConfig.getSettings();
        state.configured = settings != null && settings.enabled == true && !String.isBlank(settings.partnerId);
        state.environmentLabel = settings == null ? 'Not configured' : settings.environmentLabel;

        if (!state.authorized) {
            state.canPost = false;
            state.canUpdate = false;
            state.canDelete = false;
            state.message = 'You do not have DAT integration permission.';
            return state;
        }

        FreightTM__Load__c loadRecord = DATLoadRepository.getLoad(recordId);
        state.postId = loadRecord.DAT_Post_Id__c;
        state.shipmentId = loadRecord.DAT_Shipment_Id__c;
        Boolean hasPost = !String.isBlank(state.postId);
        state.canPost = state.configured && !hasPost;
        state.canUpdate = state.configured && hasPost;
        state.canDelete = state.configured && hasPost;
        state.message = state.configured
            ? (hasPost ? 'This Load is currently posted to DAT.' : 'This Load has not been posted to DAT.')
            : 'DAT is not enabled or the Partner ID is missing.';
        return state;
    }

    @AuraEnabled
    public static DATLoadService.Result postLoad(Id recordId) {
        requirePermission();
        return handlePost(recordId);
    }

    @AuraEnabled
    public static DATLoadService.Result updateLoad(Id recordId) {
        requirePermission();
        return handleUpdate(recordId);
    }

    @AuraEnabled
    public static DATLoadService.Result deleteLoad(Id recordId) {
        requirePermission();
        return handleDelete(recordId);
    }

    private static DATLoadService.Result handlePost(Id recordId) {
        try {
            return DATLoadService.post(recordId);
        } catch (Exception ex) {
            throw handled(ex);
        }
    }

    private static DATLoadService.Result handleUpdate(Id recordId) {
        try {
            return DATLoadService.updatePosting(recordId);
        } catch (Exception ex) {
            throw handled(ex);
        }
    }

    private static DATLoadService.Result handleDelete(Id recordId) {
        try {
            return DATLoadService.deletePosting(recordId);
        } catch (Exception ex) {
            throw handled(ex);
        }
    }

    private static Boolean hasPermission() {
        return (Test.isRunningTest() && bypassPermissionForTests)
            || FeatureManagement.checkPermission('DAT_Run');
    }

    private static void requirePermission() {
        if (!hasPermission()) {
            throw new AuraHandledException('You do not have permission to run DAT actions.');
        }
    }

    private static AuraHandledException handled(Exception ex) {
        String message = ex instanceof DATIntegrationException
            ? ex.getMessage()
            : 'DAT operation failed. Contact your Salesforce administrator.';
        return new AuraHandledException(message);
    }
}
