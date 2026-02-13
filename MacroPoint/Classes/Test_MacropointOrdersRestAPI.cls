@isTest
public class Test_MacropointOrdersRestAPI {
	@isTest
    private static void tesMethod() {
        FreightTM__Load__c load = new FreightTM__Load__c();
        load.FreightTM__Pickup_By_Appointment__c = 'No';
        load.FreightTM__Delivery_By_Appointment__c = 'No';
        load.Driver_Phone_Number__c='1234';
        insert load;
        FreightTM__Stop__c stop = new FreightTM__Stop__c(FreightTM__Load__c = load.Id);
        insert stop;
        insert new Macropoint__c(Username__c = 'username',Password__c='pass',MPID__c='123456',
                                 API_Url__c='https://macropoint-lite.com/api/1.0/orders/createorder');
        Test.setMock(HttpCalloutMock.class, new MockMacropointOrderRestAPI());
        PageReference testPage = Page.UploadLoadData; 
       Test.setCurrentPage(testPage);
       testPage.getParameters().put('Id', String.valueOf(load.Id));
        
       ApexPages.StandardController sc = new  ApexPages.StandardController(load);     
       MacropointOrdersRestAPI ext = new MacropointOrdersRestAPI(sc);         
         
       	System.debug(MacropointOrdersRestAPI.sendOrder()); 
        //PageReference ref = ext.sendOrder();
        
        // Verify response received contains fake values
        //String contentType = res.getHeader('Content-Type');
       // System.assert(contentType == 'application/xml');
       // String actualValue = res.getBody();
        String expectedValue = '{"example":"test"}';
     //   System.assertEquals(actualValue, expectedValue);
      //  System.assertEquals(200, res.getStatusCode());
    }
}