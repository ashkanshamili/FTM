@RestResource(urlMapping='/api/*')

//API class used by macropoint to update locations in Salesforce
// Created Date: 03/01/2022
// 

global class MacropointRestAPI {
	@HttpGet	
    global static String doGet() {
        System.debug('doGet called');
        String loadName = RestContext.request.params.get('ID');
    	String mpOrderId = RestContext.request.params.get('MPOrderID'); 
    	String latitude = RestContext.request.params.get('Latitude'); 
    	String longitude = RestContext.request.params.get('Longitude');
    	String country = RestContext.request.params.get('Country'); 
    	String city = RestContext.request.params.get('City'); 
    	String state = RestContext.request.params.get('State');
        try {
            List<FreightTM__Load__c> load = [SELECT Id FROM FreightTM__Load__c WHERE Name = :loadName LIMIT 1];
            //List<FreightTM__Site_Location__c> location = [SELECT Id,FreightTM__Coordinates__Latitude__s,FreightTM__Coordinates__Longitude__s
           //                FROM FreightTM__Site_Location__c WHERE FreightTM__Load__r.Name = :loadName LIMIT 1];
            if(load != null && load.size() > 0) {
            FreightTM__Site_Location__c location = new FreightTM__Site_Location__c(FreightTM__Load__c= load[0].Id);
                if(latitude != null && longitude != null) {
                    location.FreightTM__Coordinates__Latitude__s = Decimal.valueOf(latitude);  
                    location.FreightTM__Coordinates__Longitude__s = Decimal.valueOf(longitude);
                    if(country != null) {
                        if(country == 'MEX') {
                            location.FreightTM__Country__c = 'Mexico';
                        } else if(country == 'CAN') {
                            location.FreightTM__Country__c = 'Canada';
                        } else {
                            location.FreightTM__Country__c = 'United States';
                        }
                        location.FreightTM__State_Province__c = state;
                    }
                    location.FreightTM__City__c = city;
                    insert location;
                }
                
            } else {
               throw new CustomException('No load found.');
         	  }
        } catch(CustomException e) {
            throw new CustomException(e.getMessage());
        } 
        catch(Exception e) {
            throw new CustomException(e.getMessage());
        }
        
        return 'success';
    }
}