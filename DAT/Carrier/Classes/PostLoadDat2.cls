public class PostLoadDat2 {
    public String pageId { get; set; }
    public FreightTM__Load__c loadRecord { get; set; }
    public static final String DATE_RULE_FAIL_TOKEN = '__DATE_RULE_FAIL_BOTH_NULL__';
    public static final String DATE_RULE_FAIL_TOKEN_Pickup = '__DATE_RULE_FAIL_PICKUP__';
    public static final String DATE_RULE_FAIL_TOKEN_Delivery = '__DATE_RULE_FAIL_DELIVERY__';

    // ---- Platform Cache (named partition)
    private static final String ORG_PARTITION = 'local.DATCacheToken'; // your partition
    private static final String ORG_TOKEN_CACHE_KEY = 'DATORGTokenV1';
    private static final Integer ORG_TOKEN_TTL_SECS = 28 * 60; // 28 minutes

    private static final String USER_TOKEN_CACHE_KEY_PREFIX = 'DATUSERTOKENV1';
    private static final Integer USER_TOKEN_TTL_SECS = 28 * 60; // 28 minutes

    public PostLoadDat2() {
        
        pageId = ApexPages.currentPage().getParameters().get('id');
        loadRecord = [SELECT Id, Name, FreightTM__Remarks__c,FreightTM__Size__c,
                      FreightTM__Required_Trailer__c, FreightTM__Length__c, FreightTM__Weight__c, Linear_Feet__c,
                      FreightTM__Delivery_State__c, FreightTM__Delivery_City__c, FreightTM__Delivery_Address__c,FreightTM__Delivery_Zip_Code__c, 
                      FreightTM__Pickup_State__c, FreightTM__Pickup_Zip_Code__c, FreightTM__Pickup_Address__c, FreightTM__Pickup_City__c, 
                      FreightTM__Pickup_Arrival__c, FreightTM__Delivery_Arrival__c,
                      
                      FreightTM__Carrier_Obj__r.FreightTM__Phone__c, FreightTM__Carrier_Obj__r.FreightTM__Email__c,
                      FreightTM__Driver__c,FreightTM__Driver__r.FreightTM__Phone__c
                      
                      FROM FreightTM__Load__c WHERE id = :pageId LIMIT 1];
    }
    
    // --- AUTH: organization token
    public static String getOrganizationToken() {   
        
        // 1) Try cache (Org partition)
        Cache.OrgPartition part = Cache.Org.getPartition(ORG_PARTITION);
        String cached = (String) part.get(ORG_TOKEN_CACHE_KEY);
        if (!String.isBlank(cached)) {
            System.debug('**[DEBUG]** Org token from cache: ' + cached);
            return cached;
        }
        
        // Read credentials from Hierarchy Custom Setting: DAT_Org_Credential__c
        DAT_Org_Credential__c cs = DAT_Org_Credential__c.getInstance();
        String csUsername = (cs != null) ? cs.DAT_Login_Id__c : null;
        String csPassword = (cs != null) ? cs.DAT_Login_Password__c : null;
        
        if (String.isBlank(csUsername) || String.isBlank(csPassword)) {
            System.debug('**[ERROR]** DAT_Org_Credential__c is missing DAT_Login_Id__c or DAT_Login_Password__c');
            return null;
        }
        
        
        String endpoint = 'https://identity.api.staging.dat.com/access/v1/token/organization';
        //String requestBody = '{"username": "developersupport+asuccini@dat.com", "password": "dZ0YgVMSWPMfFmn"}';
        // Build JSON body from custom setting values
        String requestBody = JSON.serialize(new Map<String, String>{
            'username' => csUsername,
                'password' => csPassword
                });

        //String endpoint = 'callout:DAT_Org_Credential/access/v1/token/organization';
        //String requestBody = '{"username": "callout:DAT_Org_Credential/Username", "password": "callout:DAT_Org_Credential/Password"}';
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-dat-partner-id', '001f400001M2BglAAF');
        req.setBody(requestBody);

        System.debug('**[DEBUG]** Organization Token Request -> Endpoint: ' + endpoint + ', Body: ' + requestBody);

        Http http = new Http();
        try {
            HttpResponse res = new Http().send(req);
            System.debug('**[DEBUG]** Org Token Response -> ' + res.getStatusCode() + ', Body: ' + res.getBody());
            
            if (res.getStatusCode() == 200) {
                Map<String,Object> m = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
                if (m.containsKey('accessToken')) {
                    String token = (String) m.get('accessToken');
                    
                    // 3) Cache with TTL (seconds)
                    part.put(ORG_TOKEN_CACHE_KEY, token, ORG_TOKEN_TTL_SECS);
                    return token;
                }
                throw new CalloutException('Access token not found in the response');
            }
            throw new CalloutException('Failed to get organization token: ' + res.getStatus() + ' ' + res.getStatusCode());
        } catch (Exception e) {
            System.debug('**[ERROR]** getOrganizationToken Exception -> ' + e.getMessage());
            return null;
        }
    
        
    }

    // --- AUTH: user token
    public static String getUserToken(String accessToken) {
        // Token
        String userId = UserInfo.getUserId();
        String userKey = USER_TOKEN_CACHE_KEY_PREFIX + userId;
        
        // 1) Try cache (Org partition)
        Cache.OrgPartition part = Cache.Org.getPartition(ORG_PARTITION);
        String cached = (String) part.get(userKey);
        if (!String.isBlank(cached)) {
            System.debug('**[DEBUG]** User token from cache.' + cached);
            return cached;
        }
        
        // 2) Call identity API to get a fresh user token
        User currentUser = [SELECT Name, DAT_Username__c, DAT_UserPassword__c FROM User WHERE Id = :UserInfo.getUserId()];
        String requestBody = '{"username": "' + currentUser.DAT_Username__c + '", "password": "' + currentUser.DAT_UserPassword__c + '"}';
        //String requestBody = '{"username": "asuccini_test", "password": "asuccini_test"}';
        
        String endpoint = 'https://identity.api.staging.dat.com/access/v1/token/user';
        // String endpoint = 'callout:DAT_User_Credential/access/v1/token/user';
        //String requestBody = '{"username": "callout:DAT_User_Credential/username", "password": "callout:DAT_User_Credential/password"}';
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-dat-partner-id', '001f400001M2BglAAF');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setBody(requestBody);
        System.debug('**[DEBUG]** User Token Request -> Endpoint: ' + endpoint + ', Body: ' + requestBody + ', OrgToken: ' + accessToken);
        
        Http http = new Http();
        try {
            HttpResponse res = new Http().send(req);
            System.debug('**[DEBUG]** User Token Response -> ' + res.getStatusCode() + ', Body: ' + res.getBody());
            
            if (res.getStatusCode() == 200) {
                Map<String,Object> m = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
                if (m.containsKey('accessToken')) {
                    String token = (String) m.get('accessToken');
                    
                    // 3) Cache per-user token with TTL
                    part.put(userKey, token, USER_TOKEN_TTL_SECS);
                    return token;
                }
                throw new CalloutException('User token not found in the response');
            }
            throw new CalloutException('Failed to get user token: ' + res.getStatus() + ' ' + res.getStatusCode());
        } catch (Exception e) {
            System.debug('**[ERROR]** getUserToken Exception -> ' + e.getMessage());
            return null;
        }
        
        
    }
    
    // --- POST the load
    public String postLoad(String userToken) {
        String endpoint = 'https://freight.api.staging.dat.com/posting/v2/loads';
        //String endpoint = 'callout:DAT_Post_Load/posting/v2/loads';
        
        // Constructing the request body using Maps
        Map<String, Object> freight = new Map<String, Object>();
        
        // Map Required_Trailer__c -> DAT equipment code
        String requiredTrailer = loadRecord.FreightTM__Required_Trailer__c;
        String equipmentType;
        switch on requiredTrailer {
            when 'Sprinter Van' {
                equipmentType = 'V';
            }
            when 'Dry Van Trailer - Door clearance 110" tall required' {
                equipmentType = 'VA';
            }
            when 'Straight Box Truck - door clearance minimum 96"x96" required' { 
                equipmentType = 'SB';
            }
            when 'Reefer' {
                equipmentType = 'R';
            }
            when 'Flatbed' {
                equipmentType = 'F';
            }
            when 'Step Deck - Conestoga' {
                equipmentType = 'SN';
            }
            when 'Flatbed - Conestoga' {
                equipmentType = 'FN';
            }
            when 'Power Only' {
                equipmentType = 'PO';
            }
            when 'Lowboy' { 
                equipmentType = 'LB';
            }
            when 'Step Deck' {
                equipmentType = 'SD';
            }
            when 'Low Pro Step-Deck' {
                equipmentType = 'LA';  // Drop Deck, Landoll  //'LSD'
            }
            when 'Extendable Flatbed Stretch' {
                equipmentType = 'ST';   // Stretch Trailer  //'FS'
            }
            when 'Stretch Single Drop Deck' {  // Stretch Trailer 
                equipmentType = 'LA'; //or may 'ST'
            }
            when 'Stretch Double Drop' {
                equipmentType = 'DD'; 
            }
            when 'Extendable Double Drop' {
                equipmentType = 'DD'; 
            }
            when 'Removable Gooseneck' { 
                equipmentType = 'RG';
            }
            when 'Conestoga' {
                equipmentType = 'CN';
            }
            when 'Side Kit' {  // Flatbed w/Sides
                equipmentType = 'FS';
            }
            when 'Rail' { // Container
                equipmentType = 'C';
            }
            when 'Specialized' { // Step Deck or RGN (closest analogue)
                equipmentType = 'SR';
            }
            when 'Hot Shot Flatbed' { // Flatbed, Hotshot
                equipmentType = 'FH';
            }
            when 'Tilt' { //not in DAT doc
                equipmentType = 'F';
            }
            when else {
                // Default case if none of the above matches
                equipmentType = 'V';
            }
        }

        freight.put('equipmentType', equipmentType);
        
        
        // pull out the raw picklist
        String svc = loadRecord.FreightTM__Size__c;
        
        // map it
        String fullPartial;
        if (svc == 'LTL') {
            fullPartial = 'PARTIAL';
        } else if (svc == 'TL') {
            fullPartial = 'FULL';
        } else {
            fullPartial = null;  
        }
        
        // Comments
        List<Map<String, String>> comments = new List<Map<String, String>>();
        Map<String, String> comment = new Map<String, String>();
        comment.put('comment', loadRecord.FreightTM__Remarks__c); //dry van only
        comments.add(comment);
        freight.put('comments', comments);

        // Dimensions
        freight.put('lengthFeet', loadRecord.Linear_Feet__c); 
        freight.put('weightPounds', loadRecord.FreightTM__Weight__c); 

        // Lane
        Map<String, Object> origin = new Map<String, Object>();
        origin.put('city', loadRecord.FreightTM__Pickup_City__c);
        origin.put('stateProv', loadRecord.FreightTM__Pickup_State__c);
        origin.put('postalCode', loadRecord.FreightTM__Pickup_Zip_Code__c);

        Map<String, Object> destination = new Map<String, Object>();
        destination.put('city', loadRecord.FreightTM__Delivery_City__c);
        destination.put('stateProv', loadRecord.FreightTM__Delivery_State__c);
        destination.put('postalCode', loadRecord.FreightTM__Delivery_Zip_Code__c);

        Map<String, Object> lane = new Map<String, Object>();
        lane.put('origin', origin);
        lane.put('destination', destination);

        // Exposure / Audience
        Map<String, Boolean> audience = new Map<String, Boolean>();
        audience.put('loadBoard', true);

        Map<String, Object> exposure = new Map<String, Object>();
        exposure.put('audience', audience);
        
        // ---------------------------------------------
        // -----START NEW ADDED(PICKUP/DELIVERY DATE/TIME)
        // Availability window (use fields as-is, apply EOD rule + 6-month clamp)
        // ---------------------------------------------
        Datetime nowGmt = Datetime.now();
        
        // Earliest = pickup if present; else now (allows missing/past dates)
        Datetime earliest = (loadRecord.FreightTM__Pickup_Arrival__c != null)
            ? loadRecord.FreightTM__Pickup_Arrival__c
            : nowGmt;
        
        // Latest = delivery EOD if present; else pickup EOD if present; else today EOD
        Datetime latest;
        if (loadRecord.FreightTM__Delivery_Arrival__c != null) {
            latest = Datetime.newInstance(
                loadRecord.FreightTM__Delivery_Arrival__c.date(),
                Time.newInstance(23, 59, 59, 999)
            );
        } else if (loadRecord.FreightTM__Pickup_Arrival__c != null) {
            latest = Datetime.newInstance(
                loadRecord.FreightTM__Pickup_Arrival__c.date(),
                Time.newInstance(23, 59, 59, 999)
            );
        } else {
            latest = Datetime.newInstance(
                nowGmt.date(),
                Time.newInstance(23, 59, 59, 999)
            );
        }
        
        // If delivery < pickup, normalize to pickup EOD (no failure)
        if (latest < earliest) {
            latest = Datetime.newInstance(
                earliest.date(),
                Time.newInstance(23, 59, 59, 999)
            );
        }
        
        // Keep ~6-month clamp
        Datetime sixMonths = nowGmt.addMonths(6).addSeconds(-1);
        if (latest > sixMonths) {
            latest = Datetime.newInstance(
                sixMonths.date(),
                Time.newInstance(23, 59, 59, 999)
            );
        }

        // Push to API
        exposure.put('startWhen', nowGmt);
        exposure.put('earliestAvailabilityWhen', earliest);
        exposure.put('latestAvailabilityWhen', latest);
        exposure.put('endWhen', latest);
        
        /// --------- End Of NEW ADDED(PICKUP/DELIVERY DATE/TIME)
        
        
        
        // Poster info
        Map<String, String> primaryPhone = new Map<String, String>();
        primaryPhone.put('method', 'PRIMARY_PHONE'); 
        
        Map<String, String> email = new Map<String, String>();
        email.put('method', 'EMAIL');  
        
        List<Map<String, String>> contactMethods = new List<Map<String, String>>();
        contactMethods.add(primaryPhone);
        contactMethods.add(email);

        Map<String, Object> posterInfo = new Map<String, Object>();
        posterInfo.put('contactMethods', contactMethods);

        Map<String, Object> requestBodyMap = new Map<String, Object>();
        requestBodyMap.put('freight', freight);
        requestBodyMap.put('lane', lane);
        requestBodyMap.put('exposure', exposure);
        requestBodyMap.put('isTrackingRequired', true);
        requestBodyMap.put('posterInfo', posterInfo);

        // Serialize the map to JSON
        String requestBody = JSON.serialize(requestBodyMap);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-dat-partner-id', '001f400001M2BglAAF');
        req.setHeader('Authorization', 'Bearer ' + userToken);
        req.setBody(requestBody);
        System.debug('**[DEBUG]** Post Load Request -> Endpoint: ' + endpoint + ', Body: ' + requestBody);

        Http http = new Http();

        try {
            HttpResponse res = http.send(req);
            System.debug('**[DEBUG]** Post Load Response -> Status: ' + res.getStatus() + ' (' + res.getStatusCode() + '), Body: ' + res.getBody());
            
            if (res.getStatusCode() == 201) {
                //return res.getBody();
                String body = res.getBody();

                // --- Save DAT ids on the Load record ---
                try {
                    Map<String,Object> resp = (Map<String,Object>) JSON.deserializeUntyped(body);
                    String datPostId  = (String) resp.get('id');
                    String shipmentId = (String) resp.get('shipmentId');
                    
                    if (!String.isBlank(datPostId) || !String.isBlank(shipmentId)) {
                        update new FreightTM__Load__c(
                            Id = this.loadRecord.Id,
                            DAT_Post_Id__c     = datPostId,
                            DAT_Shipment_Id__c = shipmentId
                        );
                        System.debug('Saved DAT IDs -> DAT_Post_Id__c=' + datPostId + ', DAT_Shipment_Id__c=' + shipmentId);
                    }
                } catch (Exception e) {
                    System.debug('Failed to save DAT IDs: ' + e.getMessage());
                }

                return body;
            // --- Save DAT ids on the Load record ---
            
            
            } else {
                throw new CalloutException('Failed to post load: ' + res.getStatus() + ' ' + res.getStatusCode());
            }
        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
            System.debug('**[ERROR]** postLoad Exception -> ' + e.getMessage());
            return null;
        }
    }

    // --- Orchestrator
    public static String execute() {
        System.debug('**[DEBUG]** Starting PostLoadDat2.execute()');
        PostLoadDat2 postLoadDat2 = new PostLoadDat2();

        // Step 1: Get the organization token
        String organizationToken = getOrganizationToken();
        System.debug('**[DEBUG]** Retrieved Org Token: ' + organizationToken);
        if (organizationToken == null) {
            System.debug('Failed to get organization token');
            return null;
        }

        // Step 2: Use the organization token to get the user token
        String userToken = getUserToken(organizationToken);
        if (userToken == null) {
            System.debug('Failed to get user token');
            return null;
        }

        // Step 3: Use the user token to post the load
        String response = postLoadDat2.postLoad(userToken);
        System.debug('**[DEBUG]** Final postLoad response: ' + response);
        if (response == null) {
            System.debug('Failed to post load');
            
        }
        return response;
    }
}