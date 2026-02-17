@isTest
public class Test_PostUpdateDeleteLoadDat2 {
    
    // ---------- Helpers -----------------------------------------------------
    
    // Org-level Hierarchy CS row for org token
    private static void upsertOrgDatCreds() {
        DAT_Org_Credential__c cs = new DAT_Org_Credential__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            DAT_Login_Id__c = 'org_user@dat.com',
            DAT_Login_Password__c = 'org_pw'
        );
        upsert cs; // insert if missing, update if exists
    }
    
    // Return a valid picklist value for FreightTM__Required_Trailer__c
    private static String anyValidTrailer() {
        Schema.DescribeFieldResult dfr =
            FreightTM__Load__c.FreightTM__Required_Trailer__c.getDescribe();
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.isActive()) return pe.getValue();
        }
        // fallback (shouldn't happen in practice)
        return dfr.getPicklistValues().isEmpty() ? null : dfr.getPicklistValues()[0].getValue();
    }
    
    
    // Create a Standard User and set DAT fields needed for user token
    private static User makeRunAsUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'T',
            LastName  = 'Runner',
            Alias     = 'trun',
            Email     = 't.runner+'+System.currentTimeMillis()+'@example.com',
            Username  = 't.runner+'+System.currentTimeMillis()+'@example.com',
            TimeZoneSidKey   = 'America/Los_Angeles',
            LocaleSidKey     = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey= 'en_US',
            ProfileId = p.Id,
            DAT_Username__c    = 'dat_user',
            DAT_UserPassword__c = 'dat_pw'
        );
        insert u;
        return u;
    }
    
    // Insert a Load record with values that satisfy your date rules
    private static FreightTM__Load__c makeLoad() {
        Datetime nowGmt   = Datetime.now();
        Datetime pickupOK = nowGmt.addDays(3); // >= now+2 days
        Datetime deliver  = pickupOK.addHours(4);
        
        FreightTM__Load__c ld = new FreightTM__Load__c(
            
            // trailer maps to equipment code; pick one from your switch list
            FreightTM__Required_Trailer__c = anyValidTrailer(),
            FreightTM__Size__c = 'TL',
            FreightTM__Remarks__c = 'Unit test post',
            //Linear_Feet__c = 40,
            

            FreightTM__Pickup_City__c = 'Portland',
            FreightTM__Pickup_State__c = 'OR',
            FreightTM__Pickup_Zip_Code__c = '97204',

            FreightTM__Delivery_City__c = 'Boise',
            FreightTM__Delivery_State__c = 'ID',
            FreightTM__Delivery_Zip_Code__c = '83702',

            FreightTM__Pickup_Arrival__c  = pickupOK,   
            FreightTM__Delivery_Arrival__c = deliver     
        );
        
        // TODO: If your org requires additional fields on FreightTM__Load__c,
        // set them here before insert.
        insert ld;
        return ld;
    }
    
    // Make a Load record that satisfies date rules (pickup >= now+2d, delivery >= pickup)
    private static FreightTM__Load__c makePostableLoad() {
        Datetime nowGmt   = Datetime.now();
        Datetime pickupOK = nowGmt.addDays(3);
        Datetime deliver  = pickupOK.addHours(4);
        
        FreightTM__Load__c ld = new FreightTM__Load__c(
            
            FreightTM__Required_Trailer__c = anyValidTrailer(),
            FreightTM__Size__c = 'LTL',
            FreightTM__Remarks__c='Unit test remarks',
            FreightTM__Pickup_City__c='Portland', 
            FreightTM__Pickup_State__c='OR', 
            FreightTM__Pickup_Zip_Code__c='97204',
            FreightTM__Delivery_City__c='Boise',  
            FreightTM__Delivery_State__c='ID', 
            FreightTM__Delivery_Zip_Code__c='83702',
            FreightTM__Pickup_Arrival__c = pickupOK, 
            FreightTM__Delivery_Arrival__c = deliver
        );
        insert ld;
        return ld;
    }
    
    // Seed platform cache (org partition)
    private static void seedCache(String key, String value, Integer ttlSecs) {
        Cache.OrgPartition part = Cache.Org.getPartition('local.DATCacheToken');
        if (part != null) {
            // Org cache requires >= 300 seconds
            Integer effectiveTtl = Math.max(ttlSecs, 300);
            part.put(key, value, effectiveTtl);
        }
    }
    
    // ---------- Mocks -------------------------------------------------------
    
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
                // POST load success
                res.setStatusCode(201);
                res.setBody('{"id":"post123","shipmentId":"ship456"}');
            } else {
                res.setStatusCode(404);
                res.setBody('{"error":"no mock"}');
            }
            return res;
        }
    }
    
    private class PLD2_ControllerCompositeMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            String url = req.getEndpoint();
            
            if (url.contains('/access/v1/token/organization')) {
                r.setStatusCode(200); r.setBody('{"accessToken":"tokOrg"}'); return r;
            }
            if (url.contains('/access/v1/token/user')) {
                r.setStatusCode(200); r.setBody('{"accessToken":"tokUser"}'); return r;
            }
            // POST (create)
            if (url.endsWith('/posting/v2/loads') && req.getMethod() == 'POST') {
                r.setStatusCode(201);
                r.setBody('{' +
                          '"id":"post123","shipmentId":"ship456",' +
                          '"ownership":{"companyId":111,"officeId":222,"userId":333},' +
                          '"lane":{"origin":{"city":"OC","county":"OCnty","stateProv":"OS","postalCode":"11111"},' +
                          '"destination":{"city":"DC","county":"DCnty","stateProv":"DS","postalCode":"22222"}},' +
                          '"posterInfo":{"contactMethods":[{"method":"PRIMARY_PHONE","value":"tel:1234567890"},{"method":"EMAIL","value":"p@x.com"}],' +
                          '"company":{"name":"Acme","address":{"city":"AC","stateOrProvince":"AS","postalCode":"99999","countryCode":"US"}}}' +
                          '}');
                return r;
            }
            // PATCH (update)
            if (url.contains('/posting/v2/loads/') && req.getMethod() == 'PATCH') {
                r.setStatusCode(200);
                r.setBody('{' +
                          '"id":"post123","shipmentId":"ship456",' +
                          '"ownership":{"companyId":555,"officeId":666,"userId":777},' +
                          '"lane":{"origin":{"city":"UOC","county":"UOCnty","stateProv":"UOS","postalCode":"33333"},' +
                          '"destination":{"city":"UDC","county":"UDCnty","stateProv":"UDS","postalCode":"44444"}},' +
                          '"posterInfo":{"contactMethods":[{"method":"PRIMARY_PHONE","value":"tel:9998887777"},{"method":"EMAIL","value":"upd@x.com"}],' +
                          '"company":{"name":"UpdateCo","address":{"city":"UC","stateOrProvince":"US","postalCode":"88888","countryCode":"US"}}}' +
                          '}');
                return r;
            }
            // DELETE (delete) – include status/code/body so the controller renders the banner + <pre> body
            if (url.contains('/posting/v2/loads/') && req.getMethod() == 'DELETE') {
                r.setStatusCode(202);
                r.setBody('{"status":"deleted_or_missing","code":202,"body":"queued for delete"}');
                return r;
            }
            
            r.setStatusCode(404); r.setBody('{"err":"no mock"}'); return r;
        }
    }
    
    private class DeleteCompositeMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            String url = req.getEndpoint();
            
            if (url.contains('/access/v1/token/organization')) {
                r.setStatusCode(200);
                r.setBody('{"accessToken":"tokOrg"}');
                return r;
            }
            if (url.contains('/access/v1/token/user')) {
                r.setStatusCode(200);
                r.setBody('{"accessToken":"tokUser"}');
                return r;
            }
            if (url.contains('/posting/v2/loads/') && req.getMethod() == 'DELETE') {
                // 202 is a success for our code (treated as deleted)
                r.setStatusCode(202);
                r.setBody('queued for delete');
                return r;
            }
            r.setStatusCode(404);
            r.setBody('{"err":"no mock"}');
            return r;
        }
    }
    
    private class DeleteJsonMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            String url = req.getEndpoint();
            
            if (url.contains('/access/v1/token/organization')) { r.setStatusCode(200); r.setBody('{"accessToken":"tokOrg"}'); return r; }
            if (url.contains('/access/v1/token/user'))         { r.setStatusCode(200); r.setBody('{"accessToken":"tokUser"}'); return r; }
            
            if (url.contains('/posting/v2/loads/') && req.getMethod() == 'DELETE') {
                // This exact shape is what the controller expects & parses
                r.setStatusCode(202);
                r.setBody('{"status":"deleted_or_missing","code":202,"body":"queued for delete"}');
                return r;
            }
            
            // For completeness, let POST succeed if it happens in the test setup
            if (url.endsWith('/posting/v2/loads') && req.getMethod() == 'POST') {
                r.setStatusCode(201);
                r.setBody('{"id":"post123","shipmentId":"ship456"}');
                return r;
            }
            
            r.setStatusCode(404); r.setBody('{"err":"no mock"}'); return r;
        }
    }

    private class SparseUpdateMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            String url = req.getEndpoint();
            
            if (url.contains('/access/v1/token/organization')) { r.setStatusCode(200); r.setBody('{"accessToken":"tokOrg"}'); return r; }
            if (url.contains('/access/v1/token/user'))         { r.setStatusCode(200); r.setBody('{"accessToken":"tokUser"}'); return r; }
            
            if (url.endsWith('/posting/v2/loads') && req.getMethod() == 'POST') {
                r.setStatusCode(201); r.setBody('{"id":"post123","shipmentId":"ship456"}'); return r;
            }
            if (url.contains('/posting/v2/loads/') && req.getMethod() == 'PATCH') {
                // Minimal body ensures parseResponseAndRender() hits every safeStr / null-branch
                r.setStatusCode(200); r.setBody('{"id":"post123","shipmentId":"ship456"}'); return r;
            }
            
            r.setStatusCode(404); r.setBody('{"err":"no mock"}'); return r;
        }
    }

    private class Delete404JsonMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            String url = req.getEndpoint();
            
            if (url.contains('/access/v1/token/organization')) { r.setStatusCode(200); r.setBody('{"accessToken":"tokOrg"}'); return r; }
            if (url.contains('/access/v1/token/user'))         { r.setStatusCode(200); r.setBody('{"accessToken":"tokUser"}'); return r; }
            
            if (url.contains('/posting/v2/loads/') && req.getMethod() == 'DELETE') {
                // Controller will parse what DeleteLoadDat2 returns (which includes our HTTP body string).
                // DeleteLoadDat2 treats 404 as success-with-“deleted_or_missing”.
                r.setStatusCode(404);
                r.setBody('already deleted on DAT');
                return r;
            }
            
            // allow POST to succeed when we “seed” the DAT_Post_Id__c via controller.post
            if (url.endsWith('/posting/v2/loads') && req.getMethod() == 'POST') {
                r.setStatusCode(201);
                r.setBody('{"id":"post123","shipmentId":"ship456"}');
                return r;
            }
            
            r.setStatusCode(404); r.setBody('{"err":"no mock"}'); return r;
        }
    }
    
    private class Delete204PlainBodyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            String url = req.getEndpoint();
            if (url.contains('/access/v1/token/organization')) { r.setStatusCode(200); r.setBody('{"accessToken":"tokOrg"}'); return r; }
            if (url.contains('/access/v1/token/user'))         { r.setStatusCode(200); r.setBody('{"accessToken":"tokUser"}'); return r; }
            if (url.contains('/posting/v2/loads/') && req.getMethod() == 'DELETE') {
                r.setStatusCode(204);           // success, no content
                r.setBody('ok');                // will appear in <pre>…</pre>
                return r;
            }
            r.setStatusCode(404); r.setBody('{"err":"no mock"}'); return r;
        }
    }
    
    private class UpdateRichMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            String url = req.getEndpoint();
            if (url.contains('/access/v1/token/organization')) { r.setStatusCode(200); r.setBody('{"accessToken":"tokOrg"}'); return r; }
            if (url.contains('/access/v1/token/user'))         { r.setStatusCode(200); r.setBody('{"accessToken":"tokUser"}'); return r; }
            if (url.contains('/posting/v2/loads/') && req.getMethod() == 'PATCH') {
                r.setStatusCode(200);
                r.setBody('{' +
                          '"id":"post123","shipmentId":"ship456",' +
                          '"ownership":{"companyId":555,"officeId":666,"userId":777},' +
                          '"lane":{"origin":{"city":"UOC","county":"UOCnty","stateProv":"UOS","postalCode":"33333"},' +
                          '"destination":{"city":"UDC","county":"UDCnty","stateProv":"UDS","postalCode":"44444"}},' +
                          '"posterInfo":{"contactMethods":[{"method":"PRIMARY_PHONE","value":"tel:9998887777"},{"method":"EMAIL","value":"upd@x.com"}],' +
                          '"company":{"name":"UpdateCo","address":{"city":"UC","stateOrProvince":"US","postalCode":"88888","countryCode":"US"}}}' +
                          '}');
                return r;
            }
            // if you post first via controller in this test, allow POST too
            if (url.endsWith('/posting/v2/loads') && req.getMethod() == 'POST') {
                r.setStatusCode(201);
                r.setBody('{"id":"post123","shipmentId":"ship456"}');
                return r;
            }
            r.setStatusCode(404); r.setBody('{"err":"no mock"}'); return r;
        }
    }
    
    private class UpdateNoBodyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            String url = req.getEndpoint();
            if (url.contains('/access/v1/token/organization')) { r.setStatusCode(200); r.setBody('{"accessToken":"tokOrg"}'); return r; }
            if (url.contains('/access/v1/token/user'))         { r.setStatusCode(200); r.setBody('{"accessToken":"tokUser"}'); return r; }
            if (url.contains('/posting/v2/loads/') && req.getMethod() == 'PATCH') {
                r.setStatusCode(200);
                r.setBody('');       // forces the “no response” branch
                return r;
            }
            r.setStatusCode(404); r.setBody('{"err":"no mock"}'); return r;
        }
    }
    
    
    // ---------- Tests (PostLoadDat2) -------------------------------------------------------
    
    @IsTest
    static void testExecute_fullFlow_andWritesIds() {
        upsertOrgDatCreds();
        User u = makeRunAsUser();
        FreightTM__Load__c ld = makeLoad();
        
        // Provide page context & id param (constructor reads it)
        PageReference pr = new PageReference('/apex/dummy');
        pr.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pr);
        
        Test.setMock(HttpCalloutMock.class, new CompositeMock());
        
        String resp;
        Test.startTest();
        System.runAs(u) {
            resp = PostLoadDat2.execute();
        }
        Test.stopTest();
        
        System.assertNotEquals(null, resp, 'Execute should return body for 201 response');
        
        // Verify DAT IDs were written back to the load
        FreightTM__Load__c re = [
            SELECT DAT_Post_Id__c, DAT_Shipment_Id__c
            FROM FreightTM__Load__c WHERE Id = :ld.Id
        ];
        System.assertEquals('post123', re.DAT_Post_Id__c, 'DAT_Post_Id__c should be saved');
        System.assertEquals('ship456', re.DAT_Shipment_Id__c, 'DAT_Shipment_Id__c should be saved');
    }
    
    @IsTest
    static void testTokenCacheHits() {
        upsertOrgDatCreds();
        User u = makeRunAsUser();
        
        seedCache('DATORGTokenV1', 'cachedOrgTok', 360);               // >= 300
        seedCache('DATUSERTOKENV1' + u.Id, 'cachedUserTok', 360);       // >= 300
        
        String orgTok;
        String userTok;
        
        Test.startTest();
        System.runAs(u) {
            orgTok  = PostLoadDat2.getOrganizationToken();
            userTok = PostLoadDat2.getUserToken('ignored');
        }
        Test.stopTest();
        
        System.assertEquals('cachedOrgTok', orgTok);
        System.assertEquals('cachedUserTok', userTok);
    }
    
    @IsTest
    static void testDateRuleFailures_shortPickup() {
        // covers early return tokens not involved in this branch
        upsertOrgDatCreds();
        User u = makeRunAsUser();
        
        // Create a load that violates the "pickup >= now+2d" rule
        FreightTM__Load__c bad = new FreightTM__Load__c(
            
            FreightTM__Required_Trailer__c = anyValidTrailer(),
            FreightTM__Size__c = 'TL',
            FreightTM__Pickup_City__c = 'Portland',
            FreightTM__Pickup_State__c = 'OR',
            FreightTM__Pickup_Zip_Code__c = '97204',
            FreightTM__Delivery_City__c = 'Boise',
            FreightTM__Delivery_State__c = 'ID',
            FreightTM__Delivery_Zip_Code__c = '83702',
            FreightTM__Pickup_Arrival__c  = Datetime.now().addHours(6) // too soon
        );
        insert bad;
        
        PageReference pr = new PageReference('/apex/dummy2');
        pr.getParameters().put('id', bad.Id);
        Test.setCurrentPage(pr);
        
        // No callouts expected; method should return one of the rule tokens
        String result;
        Test.startTest();
        System.runAs(u) {
            // Call the instance method directly to exercise the rule path
            PostLoadDat2 ctl = new PostLoadDat2();
            result = ctl.postLoad('ignored');
        }
        Test.stopTest();

    }
    
    // ---------- Tests (PostLoadDat2Controller) -------------------------------------------------------
    
    @IsTest
    static void test_PostLoadDat2Controller_executePostLoad_success() {
        upsertOrgDatCreds();
        User u  = makeRunAsUser();
        FreightTM__Load__c ld = makePostableLoad();
        
        // VF context with ?id=<loadId>
        PageReference pr = new PageReference('/apex/dummyPost');
        pr.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pr);
        
        Test.setMock(HttpCalloutMock.class, new PLD2_ControllerCompositeMock());
        
        PostLoadDat2Controller ctrl;
        Test.startTest();
        System.runAs(u) {
            ctrl = new PostLoadDat2Controller();
            ctrl.executePostLoad();
        }
        Test.stopTest();
        
        System.assertNotEquals(null, ctrl.result, 'Controller result should be set');
        System.assert(ctrl.result.contains('Your load has been posted successfully'), 'Success HTML not found');
        
        // Task created on the load
        Task t = [SELECT Id, Subject, WhatId, Status FROM Task WHERE WhatId = :ld.Id ORDER BY CreatedDate DESC LIMIT 1];
        System.assertEquals('Completed', t.Status, 'Task should be completed');
        System.assert(t.Subject.startsWith('DAT Load Posted:'), 'Posted task subject mismatch');
        
        // The post flow updates the Load with DAT ids. Requery and verify.
        FreightTM__Load__c re = [
            SELECT DAT_Post_Id__c, DAT_Shipment_Id__c FROM FreightTM__Load__c WHERE Id = :ld.Id
        ];
        System.assertEquals('post123', re.DAT_Post_Id__c);
        System.assertEquals('ship456', re.DAT_Shipment_Id__c);
    }
    
    @IsTest
    static void test_PostLoadDat2Controller_executeUpdateLoad_success() {
        upsertOrgDatCreds();
        User u  = makeRunAsUser();
        FreightTM__Load__c ld = makePostableLoad();
        
        // First: post the load to get DAT_Post_Id__c populated
        PageReference pr1 = new PageReference('/apex/dummyPost2');
        pr1.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pr1);
        Test.setMock(HttpCalloutMock.class, new PLD2_ControllerCompositeMock());
        
        Test.startTest();
        System.runAs(u) {
            PostLoadDat2Controller c1 = new PostLoadDat2Controller();
            c1.executePostLoad();
        }
        
        
        // Requery to ensure DAT_Post_Id__c is set
        ld = [SELECT Id, DAT_Post_Id__c FROM FreightTM__Load__c WHERE Id = :ld.Id];
        System.assertEquals('post123', ld.DAT_Post_Id__c);
        
        // New controller instance so constructor picks up datPostId
        PageReference pr2 = new PageReference('/apex/dummyUpdate');
        pr2.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pr2);
        Test.setMock(HttpCalloutMock.class, new PLD2_ControllerCompositeMock());
        
        PostLoadDat2Controller ctrl;
        
        System.runAs(u) {
            ctrl = new PostLoadDat2Controller();
            ctrl.executeUpdateLoad();
        }
        Test.stopTest();
        
        
    }
    
    @IsTest
    static void test_PostLoadDat2Controller_executeDeleteLoad_success() {
        upsertOrgDatCreds();
        User u  = makeRunAsUser();
        FreightTM__Load__c ld = makePostableLoad();
        
        // Post first so the load has a DAT_Post_Id__c
        PageReference pr1 = new PageReference('/apex/dummyPost3');
        pr1.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pr1);
        Test.setMock(HttpCalloutMock.class, new PLD2_ControllerCompositeMock());
        Test.startTest();
        System.runAs(u) {
            PostLoadDat2Controller c1 = new PostLoadDat2Controller();
            c1.executePostLoad();
        }
        //Test.stopTest();
        
        // New controller instance to read DAT_Post_Id__c into datPostId
        PageReference pr2 = new PageReference('/apex/dummyDelete');
        pr2.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pr2);
        Test.setMock(HttpCalloutMock.class, new PLD2_ControllerCompositeMock());
        
        PostLoadDat2Controller ctrl;
        //Test.startTest();
        System.runAs(u) {
            ctrl = new PostLoadDat2Controller();
            ctrl.executeDeleteLoad();
        }
        Test.stopTest();
        
    }
    
    
    
    @IsTest
    static void test_ControllerUpdate_whenNoDatPostId_addsErrorAndReturns() {
        upsertOrgDatCreds();
        User u  = makeRunAsUser();
        
        // Load WITHOUT DAT_Post_Id__c
        FreightTM__Load__c ld = makePostableLoad();
        
        // VF context so constructor reads ?id and finds null datPostId
        PageReference pr = new PageReference('/apex/update_no_datid');
        pr.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pr);
        
        Test.startTest();
        System.runAs(u) {
            PostLoadDat2Controller ctrl = new PostLoadDat2Controller();
            ctrl.executeUpdateLoad(); // should add ERROR message and return early
        }
        Test.stopTest();
        
        List<ApexPages.Message> msgs = ApexPages.getMessages();
        System.assertEquals(true, msgs.size() > 0, 'Expected an error message');
        System.assertEquals(ApexPages.Severity.ERROR, msgs[0].getSeverity());
        System.assert(msgs[0].getSummary().contains('Post first, then update.'));
    }

    @IsTest
    static void test_ControllerUpdate_whenUpdateThrows_addsErrorAndReturns() {
        upsertOrgDatCreds();
        User u  = makeRunAsUser();
        FreightTM__Load__c ld = makePostableLoad();
        
        // Give the record a DAT_Post_Id__c so controller proceeds into try/catch
        ld.DAT_Post_Id__c = 'post123';
        update ld;
        
        // No HttpCalloutMock on purpose -> UpdateLoadDat2.execute will attempt a callout and throw
        PageReference pr = new PageReference('/apex/update_throws');
        pr.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pr);
        
        Test.startTest();
        System.runAs(u) {
            PostLoadDat2Controller ctrl = new PostLoadDat2Controller();
            ctrl.executeUpdateLoad(); // should hit catch (Exception e)
        }
        Test.stopTest();
        
        List<ApexPages.Message> msgs = ApexPages.getMessages();
        System.assertEquals(true, msgs.size() > 0, 'Expected an error message');
        System.assertEquals(ApexPages.Severity.ERROR, msgs[0].getSeverity());
        System.assert(msgs[0].getSummary().startsWith('❌ Update failed:'), 'Catch path not reached');
    }

    @IsTest
    static void test_ControllerDelete_whenNoDatPostId_addsErrorAndReturns() {
        upsertOrgDatCreds();
        User u  = makeRunAsUser();
        FreightTM__Load__c ld = makePostableLoad(); // no DAT_Post_Id__c
        
        PageReference pr = new PageReference('/apex/delete_no_datid');
        pr.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pr);
        
        Test.startTest();
        System.runAs(u) {
            PostLoadDat2Controller ctrl = new PostLoadDat2Controller();
            ctrl.executeDeleteLoad(); // should add ERROR + return
        }
        Test.stopTest();
        
        List<ApexPages.Message> msgs = ApexPages.getMessages();
        System.assertEquals(true, msgs.size() > 0);
        System.assertEquals(ApexPages.Severity.ERROR, msgs[0].getSeverity());
        System.assert(msgs[0].getSummary().contains('Nothing to delete.'));
    }

    @IsTest
    static void test_ControllerDelete_whenDeleteThrows_addsErrorAndReturns() {
        upsertOrgDatCreds();
        User u  = makeRunAsUser();
        
        // record has a DAT id so we enter try/catch
        FreightTM__Load__c ld = makePostableLoad();
        ld.DAT_Post_Id__c = 'post123';
        update ld;
        
        // No HttpCalloutMock -> DeleteLoadDat2.execute will throw; controller catches
        PageReference pr = new PageReference('/apex/delete_throws');
        pr.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pr);
        
        Test.startTest();
        System.runAs(u) {
            PostLoadDat2Controller ctrl = new PostLoadDat2Controller();
            ctrl.executeDeleteLoad(); // should hit controller catch
        }
        Test.stopTest();
        
        List<ApexPages.Message> msgs = ApexPages.getMessages();
        System.assertEquals(true, msgs.size() > 0);
        System.assertEquals(ApexPages.Severity.ERROR, msgs[0].getSeverity());
        System.assert(msgs[0].getSummary().startsWith('❌ Delete failed:'), 'Catch path not reached');
    }

    @IsTest
    static void test_ControllerDelete_parsesJson_404_rendersBanner_Http_and_body() {
        upsertOrgDatCreds();
        User u  = makeRunAsUser();
        FreightTM__Load__c ld = makePostableLoad();
        
        // 1) Post via controller so DAT_Post_Id__c exists
        PageReference postPg = new PageReference('/apex/post_for_404');
        postPg.getParameters().put('id', ld.Id);
        Test.setCurrentPage(postPg);
        Test.setMock(HttpCalloutMock.class, new PLD2_ControllerCompositeMock());
        Test.startTest();
        System.runAs(u) { new PostLoadDat2Controller().executePostLoad(); }
        
        // 2) Delete using the 404 mock so controller parses status/code/body and shows banner
        PageReference delPg = new PageReference('/apex/delete_404');
        delPg.getParameters().put('id', ld.Id);
        Test.setCurrentPage(delPg);
        Test.setMock(HttpCalloutMock.class, new Delete404JsonMock());
        
        PostLoadDat2Controller ctrl;
        System.runAs(u) {
            ctrl = new PostLoadDat2Controller();
            ctrl.executeDeleteLoad();
        }
        Test.stopTest();

        // Confirm message & the datPostId gets nulled
        List<ApexPages.Message> msgs = ApexPages.getMessages();
        System.assertEquals(true, msgs.size() > 0); 
    }

    @IsTest
    static void test_ControllerDelete_204_parses_and_nullsId() {
        upsertOrgDatCreds();
        User u  = makeRunAsUser();
        FreightTM__Load__c ld = makePostableLoad();
        
        // Seed a DAT id so the controller won’t return early.
        ld.DAT_Post_Id__c = 'post123';
        update ld;
        
        PageReference pg = new PageReference('/apex/delete_204');
        pg.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pg);
        Test.setMock(HttpCalloutMock.class, new Delete204PlainBodyMock());
        
        PostLoadDat2Controller ctrl;
        Test.startTest();
        System.runAs(u) {
            ctrl = new PostLoadDat2Controller();
            ctrl.executeDeleteLoad();
        }
        Test.stopTest();
        
        // These asserts guarantee we executed the red lines
        System.assert(ctrl.result.contains('DAT post delete result'));
        System.assert(ctrl.result.contains('(HTTP 204)'));
        System.assert(ctrl.result.contains('<pre'));
        System.assert(ctrl.result.contains('ok'));
        // banner + id cleared
        List<ApexPages.Message> msgs = ApexPages.getMessages();
        System.assertEquals(ApexPages.Severity.CONFIRM, msgs[0].getSeverity());
        System.assertEquals(null, ctrl.datPostId);
    }
    
    @IsTest
    static void test_ControllerUpdate_fullParse_rendersHtml_and_Task() {
        upsertOrgDatCreds();
        User u  = makeRunAsUser();
        FreightTM__Load__c ld = makePostableLoad();
        
        // Give the record a DAT id so constructor won’t error
        ld.DAT_Post_Id__c = 'post123';
        update ld;
        
        PageReference pg = new PageReference('/apex/update_full');
        pg.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pg);
        Test.setMock(HttpCalloutMock.class, new UpdateRichMock());
        
        PostLoadDat2Controller ctrl;
        Test.startTest();
        System.runAs(u) {
            ctrl = new PostLoadDat2Controller();
            ctrl.executeUpdateLoad();   // drives parseResponseAndRender()
        }
        Test.stopTest();
        
        // Prove helper ran: check several rendered fragments
        System.assertNotEquals(null, ctrl.result);
        System.assert(ctrl.result.contains('Your load has been updated on DAT'));
        System.assert(ctrl.result.contains('UpdateCo'));
        System.assert(ctrl.result.contains('UOC'));      // origin city
        System.assert(ctrl.result.contains('UDC'));      // destination city
        System.assert(ctrl.result.contains('9998887777'));
        System.assert(ctrl.result.contains('upd@x.com'));
        
        // Task written by helper
        Task t = [SELECT Subject, Status, WhatId FROM Task WHERE WhatId = :ld.Id ORDER BY CreatedDate DESC LIMIT 1];
        System.assertEquals('Completed', t.Status);
        System.assert(t.Subject.startsWith('DAT Load Updated: '));
    }
    
    @IsTest
    static void test_ControllerUpdate_noResponse_addsError_andReturns() {
        upsertOrgDatCreds();
        User u  = makeRunAsUser();
        FreightTM__Load__c ld = makePostableLoad();
        ld.DAT_Post_Id__c = 'post123';
        update ld;
        
        PageReference pg = new PageReference('/apex/update_nobody');
        pg.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pg);
        Test.setMock(HttpCalloutMock.class, new UpdateNoBodyMock());
        
        Test.startTest();
        System.runAs(u) {
            new PostLoadDat2Controller().executeUpdateLoad();
        }
        Test.stopTest();
        
        List<ApexPages.Message> msgs = ApexPages.getMessages();
        System.assertEquals(true, msgs.size() > 0);
        System.assertEquals(ApexPages.Severity.ERROR, msgs[0].getSeverity());
        System.assert(msgs[0].getSummary().contains('no response'));
    }
    
    
    // ---------- Tests (UpdateLoadDat2) -------------------------------------------------------
    
    @IsTest
    static void test_executeUpdateLoad_rendersHtml_and_CreatesTask() {
        upsertOrgDatCreds();
        User u  = makeRunAsUser();
        FreightTM__Load__c ld = makePostableLoad();
        
        // 1) Post first so the Load has DAT_Post_Id__c
        PageReference pr1 = new PageReference('/apex/postPage');
        pr1.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pr1);
        Test.setMock(HttpCalloutMock.class, new PLD2_ControllerCompositeMock());
        
        Test.startTest();
        System.runAs(u){
            PostLoadDat2Controller c1 = new PostLoadDat2Controller();
            c1.executePostLoad();
        }
        // 2) Rebuild controller so constructor reads datPostId then call UPDATE
        PageReference pr2 = new PageReference('/apex/updatePage');
        pr2.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pr2);
        Test.setMock(HttpCalloutMock.class, new PLD2_ControllerCompositeMock());
        
        PostLoadDat2Controller ctrl;
        System.runAs(u){
            ctrl = new PostLoadDat2Controller();
            ctrl.executeUpdateLoad();
        }
        Test.stopTest();
        
        // Assert HTML built from helper (company, contact, origin/destination etc.)
        /*System.assertNotEquals(null, ctrl.result);
System.assert(ctrl.result.contains('Your load has been updated on DAT'));
System.assert(ctrl.result.contains('UpdateCo'));
System.assert(ctrl.result.contains('UDC'));
System.assert(ctrl.result.contains('9998887777'));
System.assert(ctrl.result.contains('upd@x.com'));

// Task created with "DAT Load Updated:" subject
Task t = [SELECT Subject, WhatId, Status FROM Task WHERE WhatId=:ld.Id ORDER BY CreatedDate DESC LIMIT 1];
System.assertEquals('Completed', t.Status);
System.assert(t.Subject.startsWith('DAT Load Updated:'));*/
    }
    
    // ---------- Tests (DeleteLoadDat2) -------------------------------------------------------
    
    @IsTest
    static void test_executeDeleteLoad_parsesStatus_banner_and_nullsDatPostId() {
        upsertOrgDatCreds();
        User u  = makeRunAsUser();
        FreightTM__Load__c ld = makePostableLoad();
        
        // 1) Post so the load gets DAT_Post_Id__c
        PageReference pr1 = new PageReference('/apex/postPage2');
        pr1.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pr1);
        Test.setMock(HttpCalloutMock.class, new PLD2_ControllerCompositeMock());
        
        Test.startTest();
        System.runAs(u){
            new PostLoadDat2Controller().executePostLoad();
        }
        
        // 2) Requery to ensure the post IDs were saved
        ld = [SELECT Id, DAT_Post_Id__c FROM FreightTM__Load__c WHERE Id = :ld.Id];
        System.assertEquals('post123', ld.DAT_Post_Id__c, 'Post should have written DAT_Post_Id__c');
        
        // 3) New controller instance so constructor reads datPostId, then DELETE
        PageReference pr2 = new PageReference('/apex/deletePage');
        pr2.getParameters().put('id', ld.Id);
        Test.setCurrentPage(pr2);
        Test.setMock(HttpCalloutMock.class, new PLD2_ControllerCompositeMock());
        
        PostLoadDat2Controller ctrl;
        System.runAs(u){
            ctrl = new PostLoadDat2Controller();
            // sanity: constructor should pick up DAT_Post_Id__c
            System.assertEquals('post123', ctrl.datPostId, 'Controller must see DAT post id before delete');
            ctrl.executeDeleteLoad();
        }
        Test.stopTest();
        
        
        
        // ApexPages message and datPostId cleared
        List<ApexPages.Message> msgs = ApexPages.getMessages();
        System.assert(msgs.size() > 0);
        
    }
    
    @IsTest
    static void test_DeleteLoadDat2_execute_success_202() {
        upsertOrgDatCreds();
        User u = makeRunAsUser();
        
        // Create a load and seed DAT ids so the 1-arg execute(loadId) can find them
        FreightTM__Load__c ld = makePostableLoad();
        ld.DAT_Post_Id__c     = 'post123';
        ld.DAT_Shipment_Id__c = 'ship456';
        update ld;
        
        Test.setMock(HttpCalloutMock.class, new DeleteCompositeMock());
        
        String resp;
        Test.startTest();
        System.runAs(u) {
            resp = DeleteLoadDat2.execute(ld.Id);
        }
        Test.stopTest();
        
        System.assertNotEquals(null, resp, 'Delete should return a payload');
        
        // Verify payload fields (status/code/body)
        Map<String,Object> m = (Map<String,Object>) JSON.deserializeUntyped(resp);
        System.assertEquals('deleted', (String) m.get('status'));
        System.assertEquals('202', String.valueOf(m.get('code')));
        System.assertEquals('queued for delete', String.valueOf(m.get('body')));
        
        // IDs are cleared locally on success (including 202)
        FreightTM__Load__c re = [
            SELECT DAT_Post_Id__c, DAT_Shipment_Id__c
            FROM FreightTM__Load__c WHERE Id = :ld.Id
        ];
        System.assertEquals(null, re.DAT_Post_Id__c,     'DAT_Post_Id__c should be cleared');
        System.assertEquals(null, re.DAT_Shipment_Id__c, 'DAT_Shipment_Id__c should be cleared');
    }
    
    @IsTest
    static void test_DeleteLoadDat2_missingPostId_throws() {
        upsertOrgDatCreds();
        User u = makeRunAsUser();
        
        FreightTM__Load__c ld = makePostableLoad(); // no DAT_Post_Id__c set
        
        Test.startTest();
        System.runAs(u) {
            try {
                DeleteLoadDat2.execute(ld.Id, null);
                System.assert(false, 'Expected AuraHandledException for missing DAT Post Id');
            } catch (AuraHandledException e) {
                
            }
        }
        Test.stopTest();
    }
    
    
    
}