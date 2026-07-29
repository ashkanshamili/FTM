public with sharing class DATLoadService {
    public class Result {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String operation { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String postId { get; set; }
        @AuraEnabled public String shipmentId { get; set; }
    }

    public static Result post(Id loadId) {
        FreightTM__Load__c loadRecord = DATLoadRepository.getLoad(loadId);
        if (!String.isBlank(loadRecord.DAT_Post_Id__c)) {
            throw new DATIntegrationException('This Load is already posted to DAT. Use Update instead.');
        }

        DATHttpClient.Response response = DATHttpClient.postLoad(
            DATLoadMapper.buildPostPayload(loadRecord)
        );
        Map<String, Object> data = parseResponse(response.body, 'post');
        String postId = stringValue(data.get('id'));
        String shipmentId = stringValue(data.get('shipmentId'));

        if (String.isBlank(postId)) {
            throw new DATIntegrationException('DAT created the request but did not return a posting ID.');
        }

        try {
            DATLoadRepository.saveDatIds(loadId, postId, shipmentId);
        } catch (Exception ex) {
            throw new DATIntegrationException(
                'DAT returned Post ID ' + postId +
                ', but Salesforce could not save it. Reconcile this posting before retrying.'
            );
        }
        return result('POST', 'Load posted to DAT.', postId, shipmentId);
    }

    public static Result updatePosting(Id loadId) {
        FreightTM__Load__c loadRecord = DATLoadRepository.getLoad(loadId);
        if (String.isBlank(loadRecord.DAT_Post_Id__c)) {
            throw new DATIntegrationException('Post this Load to DAT before updating it.');
        }

        DATHttpClient.Response response = DATHttpClient.updateLoad(
            loadRecord.DAT_Post_Id__c,
            DATLoadMapper.buildUpdatePayload(loadRecord)
        );
        Map<String, Object> data = parseResponse(response.body, 'update');
        String returnedPostId = stringValue(data.get('id'));
        String returnedShipmentId = stringValue(data.get('shipmentId'));

        String postId = String.isBlank(returnedPostId) ? loadRecord.DAT_Post_Id__c : returnedPostId;
        String shipmentId = String.isBlank(returnedShipmentId) ? loadRecord.DAT_Shipment_Id__c : returnedShipmentId;
        if (postId != loadRecord.DAT_Post_Id__c || shipmentId != loadRecord.DAT_Shipment_Id__c) {
            try {
                DATLoadRepository.saveDatIds(loadId, postId, shipmentId);
            } catch (Exception ex) {
                throw new DATIntegrationException(
                    'DAT updated the posting, but Salesforce could not refresh the DAT IDs.'
                );
            }
        }

        return result('UPDATE', 'DAT posting updated.', postId, shipmentId);
    }

    public static Result deletePosting(Id loadId) {
        FreightTM__Load__c loadRecord = DATLoadRepository.getLoad(loadId);
        if (String.isBlank(loadRecord.DAT_Post_Id__c)) {
            throw new DATIntegrationException('This Load does not have a DAT posting to delete.');
        }

        DATHttpClient.deleteLoad(loadRecord.DAT_Post_Id__c);
        try {
            DATLoadRepository.clearDatIds(loadId);
        } catch (Exception ex) {
            throw new DATIntegrationException(
                'DAT deletion succeeded, but Salesforce could not clear the local DAT IDs.'
            );
        }
        return result('DELETE', 'DAT posting deleted and local DAT IDs cleared.', null, null);
    }

    private static Map<String, Object> parseResponse(String responseBody, String operation) {
        if (String.isBlank(responseBody)) {
            return new Map<String, Object>();
        }
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        } catch (Exception ex) {
            throw new DATIntegrationException('DAT ' + operation + ' response was not valid JSON.');
        }
    }

    private static Result result(String operation, String message, String postId, String shipmentId) {
        Result output = new Result();
        output.success = true;
        output.operation = operation;
        output.message = message;
        output.postId = postId;
        output.shipmentId = shipmentId;
        return output;
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}
