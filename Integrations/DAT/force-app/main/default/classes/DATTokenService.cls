public with sharing class DATTokenService {
    private static final String CACHE_PARTITION = 'local.DATCacheToken';
    private static final String ORG_CACHE_KEY = 'DATORGTokenV2';
    private static final String USER_CACHE_PREFIX = 'DATUSERTOKENV2';

    @TestVisible
    private static Boolean disableCacheForTests = false;

    public static String getOrganizationToken() {
        DATIntegrationConfig.Settings settings = DATIntegrationConfig.requireEnabled();
        String cached = getCached(ORG_CACHE_KEY);
        if (!String.isBlank(cached)) {
            return cached;
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint('DAT_Identity_Org', '/access/v1/token/organization'));
        request.setMethod('POST');
        request.setTimeout(20000);
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Accept', 'application/json');
        request.setHeader('x-dat-partner-id', settings.partnerId);
        request.setBody(
            '{"username":"{!$Credential.DAT_Org_External.Username}",' +
            '"password":"{!$Credential.DAT_Org_External.Password}"}'
        );

        String token = sendForToken(request, 'organization');
        putCached(ORG_CACHE_KEY, token, settings.orgTokenTtlSeconds);
        return token;
    }

    public static String getUserToken(String organizationToken) {
        if (String.isBlank(organizationToken)) {
            throw new DATIntegrationException('DAT organization token is unavailable.');
        }

        DATIntegrationConfig.Settings settings = DATIntegrationConfig.requireEnabled();
        String cacheKey = USER_CACHE_PREFIX + UserInfo.getUserId();
        String cached = getCached(cacheKey);
        if (!String.isBlank(cached)) {
            return cached;
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint('DAT_Identity_User', '/access/v1/token/user'));
        request.setMethod('POST');
        request.setTimeout(20000);
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Accept', 'application/json');
        request.setHeader('x-dat-partner-id', settings.partnerId);
        request.setHeader('Authorization', 'Bearer ' + organizationToken);
        request.setBody(
            '{"username":"{!$Credential.DAT_User_External.Username}",' +
            '"password":"{!$Credential.DAT_User_External.Password}"}'
        );

        String token = sendForToken(request, 'user');
        putCached(cacheKey, token, settings.userTokenTtlSeconds);
        return token;
    }

    public static void clearTokens() {
        removeCached(ORG_CACHE_KEY);
        removeCached(USER_CACHE_PREFIX + UserInfo.getUserId());
    }

    private static String sendForToken(HttpRequest request, String tokenType) {
        HttpResponse response;
        try {
            response = new Http().send(request);
        } catch (System.CalloutException ex) {
            throw new DATIntegrationException('DAT ' + tokenType + ' authentication callout failed. Check the Named Credential and network access.');
        }

        Integer statusCode = response.getStatusCode();
        if (statusCode < 200 || statusCode >= 300) {
            throw new DATIntegrationException(
                'DAT ' + tokenType + ' authentication failed with HTTP ' + statusCode + '.'
            );
        }

        Map<String, Object> responseBody;
        try {
            responseBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        } catch (Exception ex) {
            throw new DATIntegrationException('DAT ' + tokenType + ' authentication returned invalid JSON.');
        }

        String token = responseBody == null ? null : (String) responseBody.get('accessToken');
        if (String.isBlank(token)) {
            throw new DATIntegrationException('DAT ' + tokenType + ' authentication response did not include an access token.');
        }
        return token;
    }

    private static String endpoint(String namedCredential, String path) {
        if (Test.isRunningTest()) {
            return 'https://dat.test' + path;
        }
        return 'callout:' + namedCredential + path;
    }

    private static String getCached(String key) {
        if (Test.isRunningTest() && disableCacheForTests) {
            return null;
        }
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            if (partition == null) {
                return null;
            }
            Object value = partition.get(key);
            return value == null ? null : String.valueOf(value);
        } catch (Exception ignored) {
            return null;
        }
    }

    private static void putCached(String key, String value, Integer ttlSeconds) {
        if (String.isBlank(value) || (Test.isRunningTest() && disableCacheForTests)) {
            return;
        }
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            if (partition != null) {
                partition.put(key, value, ttlSeconds);
            }
        } catch (Exception ignored) {
            // Cache is optional. Authentication still works without allocated cache capacity.
        }
    }

    private static void removeCached(String key) {
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            if (partition != null) {
                partition.remove(key);
            }
        } catch (Exception ignored) {
            // Cache is optional.
        }
    }
}
