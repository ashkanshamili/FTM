public with sharing class DeleteLoadDat2 {
    
    private static final String TAG = '[DAT:DELETE] ';
    
    public static String execute(Id loadId) {
        System.debug(TAG + 'Entered execute(loadId). loadId=' + loadId);
        
        FreightTM__Load__c L = [
            SELECT DAT_Post_Id__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];
        System.debug(TAG + 'Resolved DAT_Post_Id__c=' + L.DAT_Post_Id__c);
        
        return execute(loadId, L.DAT_Post_Id__c);
    }
    
    public static String execute(Id loadId, String datPostId) {
        System.debug(TAG + 'Entered execute(loadId, datPostId). loadId=' + loadId + ', datPostId=' + datPostId);
        
        if (String.isBlank(datPostId)) {
            System.debug(TAG + 'Abort: Missing DAT Post Id.');
            throw new AuraHandledException('Missing DAT Post Id.');
        }
        
        // --- auth
        String orgTok  = PostLoadDat2.getOrganizationToken();
        System.debug(TAG + 'Org token acquired? ' + String.valueOf(!String.isBlank(orgTok)));
        if (String.isBlank(orgTok))  throw new CalloutException('Org token failed');
        
        String userTok = PostLoadDat2.getUserToken(orgTok);
        System.debug(TAG + 'User token acquired? ' + String.valueOf(!String.isBlank(userTok)));
        if (String.isBlank(userTok)) throw new CalloutException('User token failed');
        
        // --- DELETE call
        String endpoint = 'https://freight.api.staging.dat.com/posting/v2/loads/' +
            EncodingUtil.urlEncode(datPostId, 'UTF-8');
        System.debug(TAG + 'DELETE endpoint=' + endpoint);
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('DELETE');
        req.setHeader('Authorization', 'Bearer ' + userTok);
        req.setHeader('Accept', 'application/json');
        req.setHeader('x-dat-partner-id', '001f400001M2BglAAF');
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        Integer code = res.getStatusCode();
        String  body = res.getBody();
        System.debug(TAG + 'HTTP ' + code + ' BODY=' + body);
        
        // Success: 200/202/204; 404 means "already gone"
        if (code == 200 || code == 202 || code == 204 || code == 404) {
            System.debug(TAG + 'Delete considered SUCCESS (including 404). Clearing IDs on Load...');
            try {
                update new FreightTM__Load__c(
                    Id = loadId,
                    DAT_Post_Id__c     = null,
                    DAT_Shipment_Id__c = null
                );
                System.debug(TAG + 'Load updated locally: DAT_Post_Id__c and DAT_Shipment_Id__c cleared.');
            } catch (Exception e) {
                System.debug(TAG + 'WARNING: Failed to clear DAT ids on Load. ' + e.getMessage());
            }
            
            Map<String,Object> ok = new Map<String,Object>{
                'status' => (code == 404 ? 'deleted_or_missing' : 'deleted'),
                    'code'   => code,
                    'body'   => body
                    };
                        String out = JSON.serialize(ok);
            System.debug(TAG + 'Returning success payload: ' + out);
            return out;
        }
        
        // Any other code = failure
        String err = 'DAT delete failed: ' + res.getStatus() + ' ' + code + ' - ' + body;
        System.debug(TAG + err);
        throw new CalloutException(err);
    }
}