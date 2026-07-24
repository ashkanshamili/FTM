public without sharing class DriverLoadPortalTokenService {
    public class LinkResult {
        @AuraEnabled public String url;
        @AuraEnabled public String rawToken;
    }
    
    public static LinkResult generateLink(Id loadId, String siteBaseUrl) {
        if (loadId == null) {
            throw new AuraHandledException('Load Id is required.');
        }
        
        FreightTM__Load__c loadToUpdate = new FreightTM__Load__c(Id = loadId);
        
        populatePortalFields(loadToUpdate, siteBaseUrl);
        
        update loadToUpdate;
        
        LinkResult result = new LinkResult();
        result.url = loadToUpdate.Driver_Portal_Link__c;
        
        // Optional: rawToken is no longer easily returned from the helper.
        // Usually you do not need to return rawToken separately because it is already in the URL.
        result.rawToken = null;
        
        return result;
    }
    
    public static FreightTM__Load__c validateToken(String rawToken) {
        if (String.isBlank(rawToken)) {
            throw new AuraHandledException('Invalid portal link.');
        }
        
        String tokenHash = hashToken(rawToken);
        
        List<FreightTM__Load__c> loads = [
            SELECT Id,
            Name,
            Driver_Portal_Token_Hash__c,
            Driver_Portal_Active__c,
            Driver_Portal_Expires_At__c,
            Driver_Portal_Last_Opened__c
            FROM FreightTM__Load__c
            WHERE Driver_Portal_Token_Hash__c = :tokenHash
            LIMIT 1
        ];
        
        if (loads.isEmpty()) {
            throw new AuraHandledException('Invalid portal link.');
        }
        
        FreightTM__Load__c loadRec = loads[0];
        
        if (loadRec.Driver_Portal_Active__c != true) {
            throw new AuraHandledException('This portal link is inactive.');
        }
        
        if (
            loadRec.Driver_Portal_Expires_At__c != null &&
            loadRec.Driver_Portal_Expires_At__c < System.now()
        ) {
            throw new AuraHandledException('This portal link has expired.');
        }
        
        return loadRec;
    }
    
    public static String hashToken(String rawToken) {
        Blob digest = Crypto.generateDigest(
            'SHA-256',
            Blob.valueOf(rawToken)
        );
        
        return EncodingUtil.convertToHex(digest);
    }
    
    public static void populatePortalFields(FreightTM__Load__c loadRec, String siteBaseUrl) {
        if (loadRec == null) {
            return;
        }
        
        if (String.isBlank(siteBaseUrl)) {
            throw new AuraHandledException('Site base URL is required.');
        }
        
        if (siteBaseUrl.endsWith('/')) {
            siteBaseUrl = siteBaseUrl.substring(0, siteBaseUrl.length() - 1);
        }
        
        String rawToken = generateShortToken();
        String tokenHash = hashToken(rawToken);
        
        String portalUrl = siteBaseUrl + '?t=' +
            EncodingUtil.urlEncode(rawToken, 'UTF-8');
        
        loadRec.Driver_Portal_Token_Hash__c = tokenHash;
        loadRec.Driver_Portal_Link__c = portalUrl;
        loadRec.Driver_Portal_Expires_At__c = System.now().addDays(14);
        loadRec.Driver_Portal_Active__c = true;
    }
    
    public static String validateTokenAndReturnHash(String rawToken) {
        validateToken(rawToken);
        return hashToken(rawToken);
    }
    
    private static String generateShortToken() {
        String token = EncodingUtil.base64Encode(Crypto.generateAesKey(128));
        
        token = token.replace('+', '-');
        token = token.replace('/', '_');
        token = token.replace('=', '');
        
        return token;
    }
    
    public static FreightTM__Load__c validateTokenForDisplay(String rawToken) {
        if (String.isBlank(rawToken)) {
            throw new AuraHandledException('Invalid portal link.');
        }
        
        String tokenHash = hashToken(rawToken);
        
        List<FreightTM__Load__c> loads = [
            SELECT Id,
            Name,
            Driver_Portal_Token_Hash__c,
            Driver_Portal_Active__c,
            Driver_Portal_Expires_At__c,
            Driver_Portal_Last_Opened__c,
            FreightTM__Status__c
            FROM FreightTM__Load__c
            WHERE Driver_Portal_Token_Hash__c = :tokenHash
            LIMIT 1
        ];
        
        if (loads.isEmpty()) {
            throw new AuraHandledException('Invalid portal link.');
        }
        
        FreightTM__Load__c loadRec = loads[0];
        
        Boolean isDelivered =
            loadRec.FreightTM__Status__c == 'Delivered';
        
        if (loadRec.Driver_Portal_Active__c != true && !isDelivered) {
            throw new AuraHandledException('This portal link is inactive.');
        }
        
        if (
            loadRec.Driver_Portal_Expires_At__c != null &&
            loadRec.Driver_Portal_Expires_At__c < System.now() &&
            !isDelivered
        ) {
            throw new AuraHandledException('This portal link has expired.');
        }
        
        return loadRec;
    }
}