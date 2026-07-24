public without sharing class FreightLoadSyncQueueable implements Queueable, Database.AllowsCallouts {
    // private static final String BASE_URL = 'https://api.freightgraph.ai';
    private static final String BASE_URL = 'https://api-dev.freightgraph.ai';
    private static final String LOADS_PATH = '/api/loads';
    
    private List<FreightLoadSyncRequest> requests;
    
    public FreightLoadSyncQueueable(List<FreightLoadSyncRequest> requests) {
        this.requests = requests;
    }
    
    public void execute(QueueableContext context) {
        System.debug('🚚 FreightLoadSyncQueueable started.');
        System.debug('🚚 Request count=' + (requests == null ? 0 : requests.size()));
        
        if (requests == null || requests.isEmpty()) {
            System.debug('⚠ No requests to send.');
            return;
        }
        
        String token = FreightAuthApi.getStoredToken();
        
        if (String.isBlank(token)) {
            System.debug('⚠ No cached token found. Authenticating...');
            token = FreightAuthApi.authenticate();
        }
        
        if (String.isBlank(token)) {
            System.debug('❌ Unable to get FreightGraph auth token.');
            return;
        }
        
        Http http = new Http();
        List<FreightTM__Load__c> loadsToUpdate = new List<FreightTM__Load__c>();
        
        for (FreightLoadSyncRequest syncReq : requests) {
            try {
                String newFreightGraphId = sendRequest(http, token, syncReq);
                
                if (
                    syncReq.method == 'POST' &&
                    !String.isBlank(newFreightGraphId) &&
                    syncReq.salesforceLoadId != null
                ) {
                    loadsToUpdate.add(new FreightTM__Load__c(
                        Id = syncReq.salesforceLoadId,
                        Freight_Id__c = newFreightGraphId
                    ));
                    
                    System.debug(
                        '💾 Queued Freight_Id__c update. Salesforce Load Id=' +
                        syncReq.salesforceLoadId +
                        ', FreightGraph Id=' +
                        newFreightGraphId
                    );
                }
                
            } catch (Exception ex) {
                System.debug('❌ FreightGraph exception.');
                System.debug('❌ Method=' + syncReq.method);
                System.debug('❌ Salesforce Load Id=' + syncReq.salesforceLoadId);
                System.debug('❌ FreightGraph Id=' + syncReq.freightGraphId);
                System.debug('❌ Exception Message=' + ex.getMessage());
                System.debug('❌ Exception Stack Trace=' + ex.getStackTraceString());
            }
        }
        
        if (!loadsToUpdate.isEmpty()) {
            System.debug('💾 Updating Freight_Id__c on loads. Count=' + loadsToUpdate.size());
            
            Database.SaveResult[] results = Database.update(loadsToUpdate, false);
            
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    System.debug('✅ Freight_Id__c updated for Load Id=' + loadsToUpdate[i].Id);
                } else {
                    for (Database.Error err : results[i].getErrors()) {
                        System.debug(
                            '❌ Failed to update Freight_Id__c for Load Id=' +
                            loadsToUpdate[i].Id +
                            '. Error=' +
                            err.getMessage()
                        );
                    }
                }
            }
        }
    }
    
    private static String sendRequest(
        Http http,
        String token,
        FreightLoadSyncRequest syncReq
    ) {
        if (syncReq == null || String.isBlank(syncReq.method)) {
            System.debug('⚠ Invalid sync request.');
            return null;
        }
        
        String endpoint;
        
        if (syncReq.method == 'POST') {
            endpoint = BASE_URL + LOADS_PATH;
        } else {
            if (String.isBlank(syncReq.freightGraphId)) {
                System.debug(
                    '❌ Missing Freight_Id__c. Cannot call ' +
                    syncReq.method +
                    ' /api/loads/{id}. Salesforce Load Id=' +
                    syncReq.salesforceLoadId
                );
                return null;
            }
            
            endpoint =
                BASE_URL +
                LOADS_PATH +
                '/' +
                EncodingUtil.urlEncode(syncReq.freightGraphId, 'UTF-8');
        }
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(syncReq.method);
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(20000);
        
        if (syncReq.method == 'POST' || syncReq.method == 'PATCH') {
            req.setBody(syncReq.bodyJson);
        }
        
        System.debug('📤 FreightGraph Request Method: ' + req.getMethod());
        System.debug('📤 FreightGraph Request Endpoint: ' + req.getEndpoint());
        System.debug('📤 FreightGraph Request Body: ' + req.getBody());
        
        HttpResponse res = http.send(req);
        
        System.debug('📥 FreightGraph Request Status: SENT');
        System.debug('📥 FreightGraph Response Status Code: ' + res.getStatusCode());
        System.debug('📥 FreightGraph Response Status: ' + res.getStatus());
        System.debug('📥 FreightGraph Response Body: ' + res.getBody());
        
        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            System.debug(
                '✅ FreightGraph ' +
                syncReq.method +
                ' succeeded. Salesforce Load Id=' +
                syncReq.salesforceLoadId
            );
            
            if (syncReq.method == 'POST') {
                return extractFreightGraphId(res.getBody());
            }
        } else {
            System.debug(
                '❌ FreightGraph ' +
                syncReq.method +
                ' failed. Salesforce Load Id=' +
                syncReq.salesforceLoadId +
                ', FreightGraph Id=' +
                syncReq.freightGraphId
            );
        }
        
        return null;
    }
    
    private static String extractFreightGraphId(String responseBody) {
        if (String.isBlank(responseBody)) {
            System.debug('⚠ POST response body is blank. Cannot extract FreightGraph Id.');
            return null;
        }
        
        try {
            Map<String, Object> responseMap =
                (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            
            if (responseMap == null || !responseMap.containsKey('Id')) {
                System.debug('⚠ POST response does not contain Id. Body=' + responseBody);
                return null;
            }
            
            String freightGraphId = String.valueOf(responseMap.get('Id'));
            
            System.debug('🆔 Extracted FreightGraph Id from POST response: ' + freightGraphId);
            
            return freightGraphId;
            
        } catch (Exception ex) {
            System.debug('❌ Failed to parse POST response body.');
            System.debug('❌ Body=' + responseBody);
            System.debug('❌ Exception=' + ex.getMessage());
            return null;
        }
    }
}