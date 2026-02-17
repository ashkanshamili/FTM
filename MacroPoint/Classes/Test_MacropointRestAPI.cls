@isTest
public class Test_MacropointRestAPI{

    static testMethod void  testPostMethod() {
        FreightTM__Load__c load = new FreightTM__Load__c();
        load.FreightTM__Pickup_By_Appointment__c = 'No';
        load.FreightTM__Delivery_By_Appointment__c = 'No';
        insert load;
        
        
        FreightTM__Site_Location__c location = new FreightTM__Site_Location__c();
        location.FreightTM__Load__c = load.Id;
        insert location;
        FreightTM__Load__c load1 = [SELECT Id,Name FROM FreightTM__Load__c LIMIT 1];
        Test.startTest();
		
        RestRequest req = new RestRequest(); 
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/api/?';  //Request URL
        // add URL parameters here...
        req.addParameter('ID', load1.Name);
        req.addParameter('Latitude', '39.84');
        req.addParameter('Longitude', '-82.28');
        req.addParameter('Country', 'USA');
        req.addParameter('State', 'OH');
        req.addParameter('City', 'Independence');
        req.httpMethod = 'POST';//HTTP Request Type
        RestContext.request = req;
        RestContext.response= res;
        try {
            System.debug('MacropointRestAPI.doPost()'+MacropointRestAPI.doGet());
        } catch(Exception e) {
            //System.assert(e.getMessage()!='No location found for the Load.');
        }
        
        
        Test.stopTest();
    }
    static testMethod void  testPostMethod1() {
        FreightTM__Load__c load = new FreightTM__Load__c();
        load.FreightTM__Pickup_By_Appointment__c = 'No';
        load.FreightTM__Delivery_By_Appointment__c = 'No';
        insert load;
        
        
        FreightTM__Site_Location__c location = new FreightTM__Site_Location__c();
        location.FreightTM__Load__c = load.Id;
        insert location;
        FreightTM__Load__c load1 = [SELECT Id,Name FROM FreightTM__Load__c LIMIT 1];
        Test.startTest();
		
        RestRequest req = new RestRequest(); 
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/api/?';  //Request URL
        // add URL parameters here...
        req.addParameter('ID', 'load1');
        req.addParameter('Latitude', '39.84');
        req.addParameter('Longitude', '-82.28');
        req.httpMethod = 'POST';//HTTP Request Type
        RestContext.request = req;
        RestContext.response= res;
        try {
            System.debug('MacropointRestAPI.doPost()'+MacropointRestAPI.doGet());
        } catch(Exception e) {
            //System.assert(e.getMessage()!='No location found for the Load.');
        }
        
        
        Test.stopTest();
    }
}