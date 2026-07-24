public without sharing class CustomerPortalTokenService {
    public class LinkResult {
        @AuraEnabled public String url;
        @AuraEnabled public String rawToken;
        @AuraEnabled public Id sessionId;
    }

    private static final Integer DEFAULT_VALID_DAYS = 30;

    @AuraEnabled
    public static LinkResult generateLink(Id accountId, Id contactId, String siteBaseUrl, Integer validDays) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        if (String.isBlank(siteBaseUrl)) {
            throw new AuraHandledException('Site base URL is required.');
        }

        Integer daysToUse = validDays == null || validDays <= 0 ? DEFAULT_VALID_DAYS : validDays;
        String normalizedBaseUrl = normalizeBaseUrl(siteBaseUrl);
        String rawToken = generateShortToken();
        String tokenHash = hashToken(rawToken);
        String portalUrl = normalizedBaseUrl + '?t=' + EncodingUtil.urlEncode(rawToken, 'UTF-8');

        Customer_Portal_Session__c session = new Customer_Portal_Session__c();
        session.Account__c = accountId;
        session.Contact__c = contactId;
        session.Token_Hash__c = tokenHash;
        session.Active__c = true;
        session.Expires_At__c = System.now().addDays(daysToUse);
        session.Portal_Link__c = portalUrl;
        insert session;

        LinkResult result = new LinkResult();
        result.url = portalUrl;
        result.rawToken = rawToken;
        result.sessionId = session.Id;
        return result;
    }

    public static Customer_Portal_Session__c validateToken(String rawToken) {
        if (String.isBlank(rawToken)) {
            throw new AuraHandledException('Invalid portal link.');
        }

        String tokenHash = hashToken(rawToken);

        List<Customer_Portal_Session__c> sessions = [
            SELECT Id,
                   Name,
                   Account__c,
                   Contact__c,
                   Active__c,
                   Expires_At__c,
                   Token_Hash__c,
                   Portal_Link__c
            FROM Customer_Portal_Session__c
            WHERE Token_Hash__c = :tokenHash
            LIMIT 1
        ];

        if (sessions.isEmpty()) {
            throw new AuraHandledException('Invalid portal link.');
        }

        Customer_Portal_Session__c session = sessions[0];

        if (session.Active__c != true) {
            throw new AuraHandledException('This portal link is inactive.');
        }

        if (session.Expires_At__c != null && session.Expires_At__c < System.now()) {
            throw new AuraHandledException('This portal link has expired.');
        }

        if (session.Account__c == null) {
            throw new AuraHandledException('Portal session is not connected to an account.');
        }

        return session;
    }

    public static String hashToken(String rawToken) {
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(rawToken));
        return EncodingUtil.convertToHex(digest);
    }

    private static String generateShortToken() {
        String token = EncodingUtil.base64Encode(Crypto.generateAesKey(128));
        token = token.replace('+', '-');
        token = token.replace('/', '_');
        token = token.replace('=', '');
        return token;
    }

    private static String normalizeBaseUrl(String siteBaseUrl) {
        String normalized = siteBaseUrl == null ? '' : siteBaseUrl.trim();

        while (normalized.endsWith('/')) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }

        return normalized;
    }
}