public class DatPostLoad {
    
    // ---- Platform Cache (Org partition)
    private static final String ORG_PARTITION = 'local.DATCacheToken';
    private static final String ORG_TOKEN_CACHE_KEY = 'DATORGTokenV1';       
    private static final Integer ORG_TOKEN_TTL_SECS = 28 * 60;
    
    private static final String USER_TOKEN_CACHE_KEY_PREFIX = 'DATUSERTOKENV1'; // alphanumeric only
    private static final Integer USER_TOKEN_TTL_SECS = 28 * 60;


    public static String getOrganizationToken() {
        
        // 1) Cache first
        Cache.OrgPartition part = Cache.Org.getPartition(ORG_PARTITION);
        if (part != null) {
            String cached = (String) part.get(ORG_TOKEN_CACHE_KEY);
            if (!String.isBlank(cached)) {
                System.debug('**[DEBUG]** Org token (cache hit)'+ cached);
                return cached;
            }
        } else {
            System.debug('**[WARN]** Cache partition not found; proceeding without cache.');
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
        String requestBody = JSON.serialize(new Map<String, String>{
            'username' => csUsername,
                'password' => csPassword
                });
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-dat-partner-id', '001f400001M2BglAAF');
        req.setBody(requestBody);
        
        //Http http = new Http();
        System.debug('**[DEBUG]** Org Token Request -> Endpoint: ' + endpoint + ', Body: {"username":"***","password":"***"}');

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                if (responseMap.containsKey('accessToken')) {
                    String token = (String) responseMap.get('accessToken');
                    
                    // 4) Cache with TTL
                    if (part != null) part.put(ORG_TOKEN_CACHE_KEY, token, ORG_TOKEN_TTL_SECS);
                    return token;
                }
                throw new CalloutException('Access token not found in the response');
            }
            throw new CalloutException('Failed to get organization token: ' + res.getStatus() + ' ' + res.getStatusCode());
        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
            return null;
        }
        
    }
    
    public static String getUserToken(String accessToken) {
        String userId = UserInfo.getUserId();
        String userKey = USER_TOKEN_CACHE_KEY_PREFIX + userId; // keep alphanumeric
        
        // 1) Cache first
        Cache.OrgPartition part = Cache.Org.getPartition(ORG_PARTITION);
        if (part != null) {
            String cached = (String) part.get(userKey);
            if (!String.isBlank(cached)) {
                System.debug('**[DEBUG]** User token (cache hit)' + cached);
                return cached;
            }
        } else {
            System.debug('**[WARN]** Cache partition not found; proceeding without cache.');
        }
        
        String endpoint = 'https://identity.api.staging.dat.com/access/v1/token/user';
        User currentUser = [SELECT Name, DAT_Username__c, DAT_UserPassword__c FROM User WHERE Id = :UserInfo.getUserId()];
        String requestBody = '{"username": "' + currentUser.DAT_Username__c + '", "password": "' + currentUser.DAT_UserPassword__c + '"}';
        //String requestBody = '{"username": "asuccini_test", "password": "asuccini_test"}';
       
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-dat-partner-id', '001f400001M2BglAAF');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setBody(requestBody);
        
        //Http http = new Http();
        System.debug('**[DEBUG]** User Token Request -> Endpoint: ' + endpoint + ', Body: {"username":"***","password":"***"}');
        
        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                if (responseMap.containsKey('accessToken')) {
                    String token = (String) responseMap.get('accessToken');
                    
                    // 3) Cache per-user token with TTL
                    if (part != null) part.put(userKey, token, USER_TOKEN_TTL_SECS);
                    
                    return token;
                }
                throw new CalloutException('User token not found in the response');
            }
            throw new CalloutException('Failed to get user token: ' + res.getStatus() + ' ' + res.getStatusCode());
        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
            return null;
        }
        
    }
    
    // ------------ NEW helper: "2025-09-10T17:00:00.000Z" -> "2025-09-10 17:00"
    private static String isoPretty(String iso) {
        if (String.isBlank(iso)) return '';
        String s = iso.replace('T',' ');
        if (s.endsWith('Z')) s = s.substring(0, s.length()-1);
        Integer dot = s.indexOf('.');
        if (dot > -1) s = s.substring(0, dot);
        return (s.length() >= 16) ? s.substring(0,16) : s;
    }// ------------ END OF NEW helper: "2025-09-10T17:00:00.000Z" -> "2025-09-10 17:00"
    
    public class LoadDetails {
        public String id { get; set; }
        public String shipmentId { get; set; }
        public String originCity { get; set; }
        public String originState { get; set; }
        public String originPostalCode { get; set; }
        public String destinationCity { get; set; }
        public String destinationState { get; set; }
        public String destinationPostalCode { get; set; }
        public String equipmentType { get; set; }
        public Integer lengthFeet { get; set; }
        public Integer weightPounds { get; set; }
        public String comments { get; set; }
        public String contactPhone { get; set; }
        public String contactEmail { get; set; }
        
        // ------------ NEW Additional - pretty strings for UI
        public String startWhen { get; set; }
        public String endWhen { get; set; }
        public String earliestAvailabilityWhen { get; set; }
        public String latestAvailabilityWhen { get; set; }
        
        // ------------ NEW: Additional - pretty strings for UI
        public String startWhenFmt { get; set; }
        public String endWhenFmt { get; set; }
        public String earliestAvailabilityWhenFmt { get; set; }
        public String latestAvailabilityWhenFmt { get; set; }
    }
    
    public static List<LoadDetails> getLoadDetailsList(String userToken) {
        String endpoint = 'https://freight.api.staging.dat.com/posting/v2/loads?includeWorkgroupPostings=false&orderBy=desc(lifeCycleEvents.serviced.when)';
        //String endpoint = 'callout:DAT_Post_Load/posting/v2/loads?includeWorkgroupPostings=false&orderBy=desc(lifeCycleEvents.serviced.when)';
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-dat-partner-id', '001f400001M2BglAAF');
        req.setHeader('Authorization', 'Bearer ' + userToken);
        
        Http http = new Http();
        
        try {
            HttpResponse res = http.send(req);
            System.debug(res.getBody());
            if (res.getStatusCode() == 200) {
                List<JSON2Apex> responseList = (List<JSON2Apex>) JSON.deserialize(res.getBody(), List<JSON2Apex>.class);
                List<LoadDetails> loadDetailsList = new List<LoadDetails>();
                
                for (JSON2Apex loadMap : responseList) {
                    LoadDetails load = new LoadDetails();
                    load.id = loadMap.id;
                    load.shipmentId = loadMap.shipmentId;
                    
                    // ------------ NEW ADITIONALL
                    if (loadMap.exposure != null) {
                        load.startWhen = loadMap.exposure.startWhen;
                        load.endWhen = loadMap.exposure.endWhen;
                        load.earliestAvailabilityWhen = loadMap.exposure.earliestAvailabilityWhen;
                        load.latestAvailabilityWhen = loadMap.exposure.latestAvailabilityWhen;
                        // pretty
                        load.startWhenFmt = isoPretty(load.startWhen);
                        load.endWhenFmt = isoPretty(load.endWhen);
                        load.earliestAvailabilityWhenFmt = isoPretty(load.earliestAvailabilityWhen);
                        load.latestAvailabilityWhenFmt = isoPretty(load.latestAvailabilityWhen);
                    }
                    // ------------ END OF NEW ADDITIONAL
                    
                    if (loadMap.lane != null) {
                        if (loadMap.lane.origin != null) {
                            load.originCity = loadMap.lane.origin.city;
                            load.originState = loadMap.lane.origin.stateProv;
                            load.originPostalCode = loadMap.lane.origin.postalCode;
                        }
                        
                        if (loadMap.lane.destination != null) {
                            load.destinationCity = loadMap.lane.destination.city;
                            load.destinationState = loadMap.lane.destination.stateProv;
                            load.destinationPostalCode = loadMap.lane.destination.postalCode;
                        }
                    }
                    
                    if (loadMap.freight != null) {
                        load.equipmentType = loadMap.freight.equipmentType;
                        load.lengthFeet = loadMap.freight.lengthFeet;
                        load.weightPounds = loadMap.freight.weightPounds;
                        
                        if (loadMap.freight.comments != null && !loadMap.freight.comments.isEmpty()) {
                            load.comments = loadMap.freight.comments[0].comment;
                        }
                    }
                    
                    
                    if (loadMap.posterInfo != null && loadMap.posterInfo.contactMethods != null) {
                        for (ContactMethods contact : loadMap.posterInfo.contactMethods) {
                            String method = contact.method;
                            if (method.equals('PRIMARY_PHONE')) {
                                load.contactPhone = contact.value;
                            } else if (method.equals('EMAIL')) {
                                load.contactEmail = contact.value;
                            }
                        }
                    }
                    
                    loadDetailsList.add(load);
                }
                
                return loadDetailsList;
            } else {
                throw new CalloutException('Failed to get load details list: ' + res.getStatus() + ' ' + res.getStatusCode());
            }
        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
            return null;
        }
    }
    
    public class JSON2Apex {
        public String id;
        public String shipmentId;
        public Ownership ownership;
        public OwnershipV2 ownershipV2;
        public LifeCycleEvents lifeCycleEvents;
        public Exposure exposure;
        public Lane lane;
        public Freight freight;
        public Boolean isTrackingRequired;
        public PosterInfo posterInfo;
    }
    
    public class Ownership {
        public Integer companyId;
        public Integer officeId;
        public Integer groupId;
        public Integer userId;
        public String sourceApplication;
    }
    
    public class OwnershipV2 {
        public String userId;
        public String officeId;
        public String headquartersId;
    }

    public class LifeCycleEvents {
        public Created created;
        public Created updated;
        public Created serviced;
    }
    
    public class Created {
        public Integer who;
        public String when_Z;
    }
    
    public class Exposure {
        public Audience audience;
        public Boolean isExposed;
        public String startWhen;
        public String endWhen;
        public String earliestAvailabilityWhen;
        public String latestAvailabilityWhen;
        public String preferredContactMethod;
    }
    
    public class Audience {
        public LoadBoard loadBoard;
    }
    
    public class LoadBoard {
        public Boolean includesExtendedNetwork;
    }
    
    public class Lane {
        public Origin origin;
        public Origin destination;
    }
    
    public class Origin {
        public String city;
        public String county;
        public String stateProv;
        public String postalCode;
        public Double latitude;
        public Double longitude;
        public Integer placeId;
    }
    
    public class Freight {
        public String fullPartial;
        public String equipmentType;
        public Integer lengthFeet;
        public Integer weightPounds;
        public List<Comments> comments;
    }
    
    public class Comments {
        public String comment;
    }
    
    public class PosterInfo {
        public List<ContactMethods> contactMethods;
        public Company company;
    }
    
    public class ContactMethods {
        public String method;
        public String userId;
        public String value;
    }
    
    public class Company {
        public String name;
        public Address address;
        public String directoryLookupId;
    }
    
    public class Address {
        public String city;
        public String stateOrProvince;
        public String postalCode;
        public String countryCode;
    }
}