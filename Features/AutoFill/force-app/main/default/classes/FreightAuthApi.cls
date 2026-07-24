public with sharing class FreightAuthApi {

    //private static final String BASE_URL   = 'https://api.freightgraph.ai'; // Production
    private static final String BASE_URL   = 'https://api-dev.freightgraph.ai'; // update to your public URL
    private static final String LOGIN_PATH = '/api/auth/login';
    private static final String REFRESH_PATH  = '/api/auth/refresh';           //  update if your API differs
    private static final Integer DEFAULT_TTL_SECONDS = 3300; // ~55 minutes (leave buffer)
    
    // Authenticate using credentials from Custom Metadata,
    // then store token (now in Platform Cache via TokenCache).
    public static String authenticate() {
        
        // 1. Load credentials from Custom Metadata
        FreightAuthCredentials__mdt creds = [
            SELECT Username__c, Password__c
            FROM FreightAuthCredentials__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        if (creds == null) {
            throw new CalloutException('❌ No FreightAuthCredentials__mdt record found.');
        }
        
        String username = creds.Username__c;
        String password = creds.Password__c;
        
        // 2. Build request
        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + LOGIN_PATH);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(20000);
        
        Map<String, String> body = new Map<String, String>{
            'username' => username,
                'password' => password
                };
                    req.setBody(JSON.serialize(body));
        
        Http resp = new Http();
        HttpResponse res = resp.send(req);
        
        // 3. Parse response
        if (res.getStatusCode() == 200) {
            Map<String, Object> jsonResp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            // accept common variants
            String token = getString(jsonResp, new List<String>{'token','access_token','AccessToken'});
            if (!String.isBlank(token)) {
                
                // (Avoid logging raw token in logs)
                System.debug('🔑 Auth token received (length=' + token.length() + ').');
                System.debug('🔑 Auth Token Received: ' + token);
                
                // 4. Cache token with TTL (prefer API-provided expiresIn with a 60s safety buffer)
                Integer ttl = resolveTtl(jsonResp, DEFAULT_TTL_SECONDS);
                TokenCache.put(token, ttl);
                
                // 5. If a refresh token is included, cache it (no TTL)
                String refreshToken = getString(jsonResp, new List<String>{'refreshToken','RefreshToken','refresh_token'});
                if (!String.isBlank(refreshToken)) {
                    RefreshTokenCache.put(refreshToken);
                }
                
                return token;
            } else {
                throw new CalloutException('❌ Token not found in response: ' + res.getBody());
            }
        } else {
            throw new CalloutException(
                '❌ Authentication failed with status ' + res.getStatusCode() +
                ' and response: ' + res.getBody()
            );
        }
    }
    
    // Helper to fetch the stored token.
    // Now reads from Platform Cache; falls back to old custom setting if present.
    public static String getStoredToken() {
        

        
        // 1) Preferred: Platform Cache
        String cached = TokenCache.get();
        if (!String.isBlank(cached)) {
            return cached;
        }
        System.debug('Cached' + cached);
        System.debug('Cached token missing. Trying refresh flow…');
        
        // 2) Try refresh-without-password using Username + RefreshToken
        String refreshed = refreshAccessToken();
        if (!String.isBlank(refreshed)) {
            return refreshed;
        }
        System.debug('Refreshed' + refreshed);
        
        // 3) Backward-compatibility: try old Custom Setting (may be null/too short)
        FreightAuthToken__c tokenSetting = FreightAuthToken__c.getOrgDefaults();
        return (tokenSetting != null) ? tokenSetting.Token__c : null;
    }
    
    // =================== Private helpers (no public API changes) ===================
    private static String refreshAccessToken() {
        
        
        // Get refresh token from cache
        String refreshToken = RefreshTokenCache.get();
        if (String.isBlank(refreshToken)) {
            System.debug('No refresh token found in cache.');
            return null;
        }
        
        // Get username from metadata (same record as login)
        FreightAuthCredentials__mdt creds = [
            SELECT Username__c
            FROM FreightAuthCredentials__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        if (creds == null || String.isBlank(creds.Username__c)) {
            System.debug('No username available to perform refresh.');
            return null;
        }
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + REFRESH_PATH);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(20000);
        req.setBody(JSON.serialize(new Map<String, String>{
            'Username'     => creds.Username__c,
                'RefreshToken' => refreshToken
                }));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 200) {
            Map<String, Object> jsonResp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            
            String token = getString(jsonResp, new List<String>{'token','access_token','AccessToken'});
            if (String.isBlank(token)) {
                System.debug('Refresh response did not contain an access token.');
                return null;
            }
            
            Integer ttl = resolveTtl(jsonResp, DEFAULT_TTL_SECONDS);
            TokenCache.put(token, ttl);
            
            // Some APIs rotate refresh tokens—capture if present
            String newRefresh = getString(jsonResp, new List<String>{'refreshToken','RefreshToken','refresh_token'});
            if (!String.isBlank(newRefresh)) {
                RefreshTokenCache.put(newRefresh);
            }
            
            System.debug('🔁 Access token refreshed (ttl=' + ttl + 's).');
            return token;
        }
        
        System.debug('⚠ Refresh failed: ' + res.getStatusCode() + ' → ' + res.getBody());
        return null;
    }
    
    // Pull a string from possible key variants (handles case/format differences)
    private static String getString(Map<String, Object> m, List<String> keys) {
        if (m == null || keys == null) return null;
        for (String k : keys) {
            if (m.containsKey(k) && m.get(k) != null) {
                Object v = m.get(k);
                if (v instanceof String) return (String)v;
            }
        }
        return null;
    }
    
    // Resolve TTL (seconds) from response; apply a 60s safety buffer
    private static Integer resolveTtl(Map<String, Object> m, Integer fallback) {
        try {
            if (m != null && m.containsKey('expiresIn') && m.get('expiresIn') != null) {
                Object exp = m.get('expiresIn');
                Integer apiTtl;
                if (exp instanceof Decimal)      apiTtl = ((Decimal)exp).intValue();
                else if (exp instanceof Integer) apiTtl = (Integer)exp;
                else if (exp instanceof Long)    apiTtl = ((Long)exp).intValue();
                else if (exp instanceof String)  apiTtl = Integer.valueOf((String)exp);
                else                              apiTtl = fallback;
                return Math.max(60, apiTtl - 60);
            }
        } catch (Exception ignore) {}
        return fallback;
    }
}