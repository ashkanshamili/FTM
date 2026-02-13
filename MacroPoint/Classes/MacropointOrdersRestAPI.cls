/*
    This class was created to send load data to Macropoint
    Created: 03/11/2022
//
*/
public class MacropointOrdersRestAPI {
    public static Id loadId{get;set;}
    public MacropointOrdersRestAPI(ApexPages.StandardController controller) {
        FreightTM__Load__c loadRec =  (FreightTM__Load__c) controller.getRecord();
        loadId = loadRec.Id;
        System.debug('The load record: ' + loadId);
    }
    public static PageReference sendOrder() {
        try {
            FreightTM__Load__c load;
            List<FreightTM__Stop__c> stops;
            Macropoint__c config = Macropoint__c.getOrgDefaults();
            HttpRequest req = new HttpRequest();
            HttpResponse res = new HttpResponse();
            Http http = new Http();
            String username = config.Username__c;
            String password = config.Password__c;
            if(loadId != null) {
                load = [SELECT Id, Name, Driver_Phone_Number__c, Truck_Number__c, FreightTM__Trailer__c, 
                        Tracking_Comments__c  FROM FreightTM__Load__c WHERE Id = :loadId];
                stops = [SELECT Id, Name, FreightTM__Type__c, FreightTM__Address__c, FreightTM__City__c, FreightTM__State__c,
                         FreightTM__Country__c, FreightTM__Zip_Code__c, FreightTM__Arrival__c, FreightTM__Departure__c,
                         FreightTM__Remarks__c FROM FreightTM__Stop__c WHERE FreightTM__Load__c = :loadId];
            }
            if(load.Driver_Phone_Number__c != null) {
                Blob headerValue = Blob.valueOf(username + ':' + password);
                String authorizationHeader = 'Basic ' + EncodingUtil.base64Encode(headerValue);
                
                req.setHeader('Authorization', authorizationHeader);
                req.setHeader('Content-Type','application/xml');
                String stopString= '';
                if(stops.size()> 0) {
                    for(FreightTM__Stop__c stop : stops) {
                        String stopType = stop.FreightTM__Type__c == 'Delivery'?'DropOff':'Pickup';
                        String remarks = stop.FreightTM__Remarks__c == null?'':stop.FreightTM__Remarks__c;
                        String departure = stop.FreightTM__Departure__c == null?'':''+stop.FreightTM__Departure__c;
                        String arrival = stop.FreightTM__Arrival__c == null?'':''+stop.FreightTM__Arrival__c;
                        String country = stop.FreightTM__Country__c == null?'':stop.FreightTM__Country__c;
                        String zip = stop.FreightTM__Zip_Code__c == null?'':stop.FreightTM__Zip_Code__c;
                        String state = stop.FreightTM__State__c == null?'':stop.FreightTM__State__c;
                        String city = stop.FreightTM__City__c == null?'':stop.FreightTM__City__c;
                        String address = stop.FreightTM__Address__c == null?'':stop.FreightTM__Address__c;
                    	stopString += '<Stop>'+
                                        '<Name>'+stop.Name+'</Name>'+
                                        '<StopType>'+stopType+'</StopType>'+
                                        '<Address>'+
                                            '<Line1>'+address+'</Line1>'+
                                            '<Line2></Line2>'+
                                            '<City>'+city+'</City>'+
                                            '<StateOrProvince>'+state+'</StateOrProvince>'+
                                            '<PostalCode>'+zip+'</PostalCode>'+
                                            '<Country>'+country+'</Country>'+
                                        '</Address>'+
                                        '<Latitude></Latitude>'+
                                        '<Longitude></Longitude>'+
                                        '<StartDateTime>'+arrival+'</StartDateTime>'+
                                        '<EndDateTime>'+departure+'</EndDateTime>'+
                                        '<GeofenceInMiles></GeofenceInMiles>'+
                                        '<SequenceNumber></SequenceNumber>'+
                                        '<StopID>'+stop.Name+'</StopID>'+
                                        '<Notes>'+remarks+'</Notes>'+ 
                                        '<LastStopEventCompleted></LastStopEventCompleted>'+
                                    '</Stop>';
                	}
                }
                string xmlString = //' <?xml version="1.0"?>'+
                        '<Order xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns=\"http://macropoint-lite.com/xml/1.0\">'+
                        '<TrackVia>'+
                            '<Number Type="Mobile">'+load.Driver_Phone_Number__c+'</Number>'+
                            '<Number Type="VehicleID">'+load.Truck_Number__c+'</Number>'+
                            '<Number Type="TrailerID"></Number>'+
                        '</TrackVia>'+
                        '<TrackStartDateTime>'+Datetime.now().format('yyyy-MM-dd HH:mm')+' ET'+'</TrackStartDateTime>'+
                        '<Notifications>'+
                            '<Notification>'+
                                '<PartnerMPID>'+config.MPID__c+'</PartnerMPID>'+
                                '<IDNumber>'+load.Name+'</IDNumber>'+
                                '<TrackDurationInHours>24</TrackDurationInHours>'+
                                '<TrackIntervalInMinutes>60</TrackIntervalInMinutes>'+
                            '</Notification>'+
                        '</Notifications>'+
                        '<Carrier>'+
                        '</Carrier>'+
                        '<Vehicle>'+
                            '<Type>DryVan</Type>'+
                        '</Vehicle>'+
                    	'<TripSheet>'+
                            '<StopSequencingRequired>False</StopSequencingRequired>'+
                            	'<Stops>'+
                    				stopString+
                                '</Stops>'+
                            '</TripSheet>'+
                        '<ScheduleAlerts>'+
                            '<MaximumAllowableDrivingHoursPerDay>11</MaximumAllowableDrivingHoursPerDay>'+
                        '</ScheduleAlerts>'+
                        '<EmailCopiesOfUpdatesTo></EmailCopiesOfUpdatesTo>'+
                        '<Notes>'+load.Tracking_Comments__c  +'</Notes>'+
                    '</Order>';
                SYstem.debug(xmlString);
                req.setEndpoint(config.API_Url__c);
                req.setMethod('POST');
                req.setBody(xmlString);
                res = http.send(req);
                if(res.getStatusCode() == 400) {
                    ApexPages.addmessage(new ApexPages.message(ApexPages.severity.ERROR,res.getStatus()));
                	return null;
                }
                SYstem.debug(res);
            } else {
                System.debug('Callout error: ');
                ApexPages.addmessage(new ApexPages.message(ApexPages.severity.ERROR,'Driver Phone Number Cannot be empty'));
                return null;
            }
            
        } catch(System.CalloutException e) {
            System.debug('Callout error: '+ e);
            ApexPages.addmessage(new ApexPages.message(ApexPages.severity.ERROR,e.getMessage()));
            return null;
        }catch(Exception e) {
            System.debug('Callout error: '+ e);
            ApexPages.addmessage(new ApexPages.message(ApexPages.severity.ERROR,e.getMessage()));
            return null;
        }
        return new PageReference('/'+loadId);
    }
}