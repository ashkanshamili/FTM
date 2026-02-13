@isTest
public class Test_DatPostLoad {
    
    // -- Helpers -------------------------------------------------------------
    private static void upsertOrgDatCreds() {
        DAT_Org_Credential__c cs = new DAT_Org_Credential__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            DAT_Login_Id__c = 'org_user@dat.com',
            DAT_Login_Password__c = 'org_pw'
        );
        upsert cs; // uses Id; if none, it inserts
    }

    private static User makeRunAsUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName='T', LastName='Runner',
            Alias='trun', Email='t.runner+'+System.currentTimeMillis()+'@example.com',
            Username='t.runner+'+System.currentTimeMillis()+'@example.com',
            TimeZoneSidKey='America/Los_Angeles',
            LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8',
            LanguageLocaleKey='en_US',
            ProfileId=p.Id,
            // custom DAT fields for user-token call
            DAT_Username__c = 'dat_user',
            DAT_UserPassword__c = 'dat_pw'
        );
        insert u;
        return u;
    }

    private static void seedCache(String key, String value, Integer ttlSecs) {
        Cache.OrgPartition part = Cache.Org.getPartition('local.DATCacheToken');
        if (part != null) part.put(key, value, ttlSecs);
    }

    @IsTest
    static void testGetOrganizationToken_calloutPath() {
        upsertOrgDatCreds();
        Test.setMock(HttpCalloutMock.class, new CompositeMock());

        Test.startTest();
        String tok = DatPostLoad.getOrganizationToken();
        Test.stopTest();

        System.assertEquals('mockOrgToken', tok);
    }

    @IsTest
    static void testGetUserToken_calloutPath() {
        upsertOrgDatCreds(); // not strictly required here, but harmless
        User u = makeRunAsUser();
        Test.setMock(HttpCalloutMock.class, new CompositeMock());

        Test.startTest();
        System.runAs(u) {
            String userTok = DatPostLoad.getUserToken('mockOrgToken');
            System.assertEquals('mockUserToken', userTok);
        }
        Test.stopTest();
    }

    @isTest
    static void testGetLoadDetailsList() {
        // Setup the mock response for load details list
        Test.setMock(HttpCalloutMock.class, new CompositeMock());

        Test.startTest();
        List<DatPostLoad.LoadDetails> loadDetailsList = DatPostLoad.getLoadDetailsList('mockUserToken');
        Test.stopTest();

        System.assertNotEquals(null, loadDetailsList, 'Load details list should not be null');
        System.assertEquals(1, loadDetailsList.size(), 'Load details list size should be 1');
        DatPostLoad.LoadDetails load = loadDetailsList[0];
        System.assertEquals('1', load.id, 'Load ID should match');
        System.assertEquals('1001', load.shipmentId, 'Shipment ID should match');
        System.assertEquals('City1', load.originCity, 'Origin city should match');
        System.assertEquals('City2', load.destinationCity, 'Destination city should match');
        System.assertEquals('Flatbed', load.equipmentType, 'Equipment type should match');
        System.assertEquals(20, load.lengthFeet, 'Length feet should match');
        System.assertEquals(2000, load.weightPounds, 'Weight pounds should match');
        System.assertEquals('Handle with care', load.comments, 'Comments should match');
        System.assertEquals('1234567890', load.contactPhone, 'Contact phone should match');
        System.assertEquals('test@test.com', load.contactEmail, 'Contact email should match');
    }

    @isTest
    static void testLoadDetailsController() {
        // Setup the mock responses for tokens and load details
        Test.setMock(HttpCalloutMock.class, new CompositeMock());

        Test.startTest();
        DatPostLoadController controller = new DatPostLoadController();
        Test.stopTest();

       
    }
    @IsTest
    static void testDatPostLoadController_success() {
        // Need a page context because the controller may call ApexPages.addMessage
        Test.setCurrentPage(new PageReference('/apex/dummy'));
        
        upsertOrgDatCreds();                 // org-level Hierarchy CS row
        User u = makeRunAsUser();            // user has DAT_Username__c / DAT_UserPassword__c
        Test.setMock(HttpCalloutMock.class, new CompositeMock()); // returns tokens + loads
        
        DatPostLoadController ctrl;
        Test.startTest();
        System.runAs(u) {
            ctrl = new DatPostLoadController();
        }
        Test.stopTest();
        
        System.assertNotEquals(null, ctrl.loadDetailsList, 'List should be set');
        System.assertEquals(1, ctrl.loadDetailsList.size(), 'One load expected from mock');
        System.assertEquals(0, ApexPages.getMessages().size(), 'No error messages expected');
    }

    
    // Composite Mock for the three endpoints used
    private class CompositeMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String url = req.getEndpoint();

            if (url.contains('/access/v1/token/organization')) {
                res.setStatusCode(200);
                res.setBody('{"accessToken":"mockOrgToken"}');
            } else if (url.contains('/access/v1/token/user')) {
                res.setStatusCode(200);
                res.setBody('{"accessToken":"mockUserToken"}');
            } else if (url.contains('/posting/v2/loads')) {
                res.setStatusCode(200);
                res.setBody(
                    '[{"id":"1","shipmentId":"1001",' +
                    '"exposure":{"startWhen":"2025-09-10T17:00:00.000Z","endWhen":"2025-09-10T20:00:00.000Z","earliestAvailabilityWhen":"2025-09-10T17:00:00.000Z","latestAvailabilityWhen":"2025-09-10T20:00:00.000Z"},' +
                    '"lane":{"origin":{"city":"City1","stateProv":"ST1","postalCode":"12345"},' +
                    '"destination":{"city":"City2","stateProv":"ST2","postalCode":"54321"}},' +
                    '"freight":{"equipmentType":"Flatbed","lengthFeet":20,"weightPounds":2000,"comments":[{"comment":"Handle with care"}]},' +
                    '"posterInfo":{"contactMethods":[{"method":"PRIMARY_PHONE","value":"1234567890"},{"method":"EMAIL","value":"test@test.com"}]}}]'
                );
            } else {
                res.setStatusCode(404);
                res.setBody('{"error":"no mock"}');
            }
            return res;
        }
    }  

   
}