public with sharing class HighwayConfig {

    public static String ENVIRONMENT = 'sandbox';
    public static String API_KEY;
    public static String BASE_URL;

    public static void load() {

        if (API_KEY != null) return;

        try {
            List<Highway_Config__mdt> generalConfig = [
                SELECT Environment__c
                FROM Highway_Config__mdt
                LIMIT 1
            ];
            if (!generalConfig.isEmpty() && String.isNotBlank(generalConfig[0].Environment__c)) {
                ENVIRONMENT = generalConfig[0].Environment__c.trim().toLowerCase();
            }
        } catch (Exception ignored) {
            ENVIRONMENT = 'sandbox';
        }

        String metadataType =
            ENVIRONMENT == 'prod'
            ? 'ProdHighway__mdt'
            : 'StagingHighway__mdt'; 

        List<SObject> results =
            Database.query(
                //'SELECT api_key__c, base_url__c FROM ' +
                'SELECT api_key__c, endpoint_SyncCarrier__c FROM ' +
                metadataType +
                ' LIMIT 1'
            );

        if (!results.isEmpty()) {
            API_KEY = (String) results[0].get('api_key__c');
            //BASE_URL = (String) results[0].get('base_url__c');
            BASE_URL = (String) results[0].get('endpoint_SyncCarrier__c');
        } else {
            throw new CalloutException('Highway config not found');
        }
    }
    @TestVisible
    static void reset() {
        API_KEY = null;
        BASE_URL = null;
        ENVIRONMENT = 'sandbox';
    }
}
