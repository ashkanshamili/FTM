@IsTest
public class Test_FreightAuthApi_RefreshTokenCache { 
    
    // --- Test HTTP mock for both login and refresh endpoints ---
    private class FreightAuthApiMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            
            String ep = req.getEndpoint();
            if (ep != null && ep.endsWith('/api/auth/login')) {
                // Successful login response
                res.setStatusCode(200);
                res.setBody('{"token":"abc123","expiresIn":3600,"refreshToken":"ref123"}');
                return res;
            } else if (ep != null && ep.endsWith('/api/auth/refresh')) {
                // Successful refresh response
                res.setStatusCode(200);
                res.setBody('{"token":"newtok","expiresIn":3600,"refreshToken":"ref456"}');
                return res;
            } else {
                res.setStatusCode(404);
                res.setBody('{"error":"not_found"}');
                return res;
            }
        }
    }
    
    // --- Setup Data ---
    @TestSetup
    static void setupData() {

        FreightAuthToken__c cs = new FreightAuthToken__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Token__c     = 'legacyToken'
        );
        insert cs;
    }
    
    //--- Test methods to cover FreightAuthApi ---
    @IsTest
    static void testAuthenticate_Success() {
        Test.setMock(HttpCalloutMock.class, new FreightAuthApiMock());
        
        Test.startTest();
        String token = FreightAuthApi.authenticate();
        Test.stopTest();
        
        System.assertEquals('abc123', token, 'authenticate() should return the login token');
        
        // Also verify getStoredToken() retrieves the same token from cache
        String stored = FreightAuthApi.getStoredToken();
        System.assertEquals('abc123', stored, 'getStoredToken() should return cached token after authenticate()');
    }
    
    @IsTest
    static void testGetStoredToken_UsesRefreshFlow() {
        Test.setMock(HttpCalloutMock.class, new FreightAuthApiMock());

        try {
            TokenCache.put('', 1);
        } catch (Exception e) {
        }
        
        // Preload refresh token so the code can call /refresh
        try {
            RefreshTokenCache.put('ref123');
        } catch (Exception e) {
            // Ignore if wrapper handles differently in this org
        }
        
        Test.startTest();
        String token = FreightAuthApi.getStoredToken(); // should call refresh and return "newtok"
        Test.stopTest();
        
    }
    
    @IsTest
    static void testGetStoredToken_FallbackToCustomSetting() {
        // Make sure cache won't satisfy the request
        try { TokenCache.put('', 1); } catch (Exception e) {}
        try { RefreshTokenCache.put(''); } catch (Exception e) {}
        
        // No credentials available for refresh, but fall back to Custom Setting
        Test.startTest();
        String token = FreightAuthApi.getStoredToken();
        Test.stopTest();
        
        System.assertEquals('legacyToken', token,
                            'Without cached/refresh tokens and no CMDT creds, code should fall back to Hierarchy Custom Setting');
    }
    
    @IsTest
    static void testAuthenticate_NoCredentials_Throws() {
        // Mock the HttpCalloutMock to simulate no credentials
        Test.setMock(HttpCalloutMock.class, new FreightAuthApiMock());
        
        // Ensure there are no credentials in the Custom Metadata
        List<FreightAuthCredentials__mdt> existingCreds = [SELECT Id FROM FreightAuthCredentials__mdt WHERE DeveloperName = 'Default' LIMIT 1];
        
        
        Boolean threw = false;
        try {
            FreightAuthApi.authenticate(); // This should throw an exception
        } catch (Exception e) {
            threw = true;
            
        }
        System.assert(threw, 'authenticate() must throw when credentials are missing');
    }
    

    
    //--- Test methods to cover RefreshTokenCache ---
    @IsTest
    static void testRefreshTokenCache() {

        String refreshToken = 'testRefreshToken123';
        RefreshTokenCache.put(refreshToken);
        
        // Retrieve the token from cache and assert
        String cachedToken = RefreshTokenCache.get();
        System.assertEquals(refreshToken, cachedToken, 'The refresh token should be stored and retrieved correctly from the cache');
        
        // Test: clearing the cache
        RefreshTokenCache.clear();
        
        // Retrieve the token after clearing and assert it is null
        String clearedToken = RefreshTokenCache.get();
        System.assertEquals(null, clearedToken, 'The cache should be empty after clearing');
    }
    
    //--- Test methods to cover TokenCache ---
    @IsTest
    static void testTokenCache() {
        // Test 1: Put a token with a TTL
        String token = 'testToken123';
        Integer ttl = 3600; // 1 hour TTL
        
        // Store the token in the cache with TTL
        TokenCache.put(token, ttl);
        
        // Retrieve the token from cache and assert
        String cachedToken = TokenCache.get();
        System.assertEquals(token, cachedToken, 'The token should be stored and retrieved correctly with TTL');
        
        // Test 2: Put a token without a TTL (null or 0 TTL)
        String tokenWithoutTTL = 'testTokenNoTTL';
        TokenCache.put(tokenWithoutTTL, 0);  // No TTL
        
        // Retrieve the token from cache and assert
        String cachedTokenWithoutTTL = TokenCache.get();
        System.assertEquals(tokenWithoutTTL, cachedTokenWithoutTTL, 'The token should be stored and retrieved correctly without TTL');
        
        // Test 3: Clear the token from the cache
        TokenCache.clear();
        
        // Retrieve the token after clearing and assert it is null
        String clearedToken = TokenCache.get();
        System.assertEquals(null, clearedToken, 'The cache should be empty after clearing');
    } 
}