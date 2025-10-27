public with sharing class GlobalTranzBookShipment {
    // ==== CONFIG (same creds as rate) ====
    private static final String HOST = 'https://dev.gtzintegrate.com';
    //private static final String HOST = 'https://api.gtzintegrate.com'; ===> production
    private static final String SUBSCRIPTION_KEY = 'Your-Key';
    private static final String USERNAME = 'Your-Username';
    private static final String PASSWORD = 'Your-Password';

    // ==== Logging helpers ====
    private static final Integer CHUNK = 12000;
    private static void logLarge(String label, String s){
        if (s == null) { System.debug(label+': <null>'); return; }
        for(Integer i=0;i<s.length();i+=CHUNK){
            System.debug(label+' ['+i+'-'+Math.min(i+CHUNK,s.length())+']: ' + s.substring(i, Math.min(i+CHUNK, s.length())));
        }
    }

    // ==== DTOs ====
    public class Party {
        public String CompanyName;
        public String Street;
        public String Street2;
        public String ContactName;
        public String PhoneNumber;
        public String ReadyTime; // "HH:mm"
        public String CloseTime; // "HH:mm"
    }
    public class ShipmentRequest {
        public String CustomerId;
        public String QuoteId;
        public String CustomerBOLNo;
        public String ShipperRefNo;
        public String PickupNumber;
        public String PONo;
        public String LabelNotes;
        public String PickupRemarks;
        public String DeliveryRemarks;
        public Party Origin;
        public Party Destination;
    }
    public class ShipmentResponse {
        // Unknown exact schema; keep raw too
        public String Raw;
    }

    // ==== Core call ====
    //@AuraEnabled(cacheable=false)
    public static String createShipmentRaw(ShipmentRequest req){

        HTTPResponse res = GlobalTranzHttpRequest.send(JSON.serialize(req), 'shipment/ltl', 'POST');

        System.debug('GTZ Create Shipment status: ' + res.getStatusCode() + ' ' + res.getStatus());
        logLarge('GTZ Create Shipment RAW', res.getBody());
        try {
            logLarge('GTZ Create Shipment PRETTY',
                     JSON.serializePretty(JSON.deserializeUntyped(res.getBody())));
        } catch (Exception ignore){}

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) return res.getBody();
        throw new CalloutException('Create Shipment failed: '+res.getStatus()+ ' — ' + res.getBody());
    }

    // ==== Convenience: build request from Load + QuoteId ====
    //@AuraEnabled(cacheable=false)
    public static String createShipmentForLoad(Id LaneQuoteId, String quoteId){
        FreightTM__Lane_Quote__c laneQuote = [
                   SELECT Id,Name,Customer_Id__c,FreightTM__Customer__c,FreightTM__Customer__r.AccountNumber,FreightTM__Rate_to_Carrier__c,
                   FreightTM__Description__c,FreightTM__Customer_Rate__c, Contact_Name__c,
                   //---- Origin 
                   FreightTM__Pickup_Facility__c, FreightTM__Pickup_Street__c, FreightTM__Pickup_City__c, FreightTM__Pickup_State__c,
                   FreightTM__Pickup_Zip_Code__c, FreightTM__Pickup_Country__c,FreightTM__Pickup_Facility__r.Name, Pickup_Remarks__c,                 
                   FreightTM__Pickup_Facility__r.FreightTM__Working_End_Time__c,FreightTM__Pickup_Facility__r.FreightTM__Working_Start_Time__c,
                   Pickup_Contact__c, Pickup_Phone__c,Pickup_Ref__c,
                   //---- Destination 
                   FreightTM__Delivery_Facility__c, FreightTM__Delivery_Street__c, FreightTM__Delivery_City__c, FreightTM__Delivery_State__c,
                   FreightTM__Delivery_Zip_Code__c, FreightTM__Delivery_Country__c,FreightTM__Delivery_Facility__r.Name, Delivery_Remarks__c,
                   FreightTM__Delivery_Facility__r.FreightTM__Working_End_Time__c,FreightTM__Delivery_Facility__r.FreightTM__Working_Start_Time__c,
                   Delivery_Contact__c, Delivery_Phone__c,Delivery_Ref__c,
                   //---- Freight details
                   Length__c,Height__c,Width__c,FreightTM__Weight__c,Class__c,NMFC__c,Handling__c,Shipment_Info__c,
                   Number_of_Pallets__c,Hazmat__c,Stackable__c,Number_of_Pieces__c,Hazmat_Class__c,Linear_Feet__c,Accessorials__c,PO__c

            FROM FreightTM__Lane_Quote__c WHERE Id = :LaneQuoteId LIMIT 1
        ];

        ShipmentRequest s = new ShipmentRequest();
        s.CustomerId     = laneQuote.Customer_Id__c; 
  
        s.QuoteId         = quoteId;
        s.CustomerBOLNo   = laneQuote.Name;
        s.ShipperRefNo    = laneQuote.Name;
        s.PONo            = laneQuote.PO__c;  
        s.PickupNumber    = laneQuote.Pickup_Ref__c;
        s.LabelNotes      = 'Created from Eighy1 Ventures Quote ' + laneQuote.Name;
        s.PickupRemarks   = String.isBlank(laneQuote.Pickup_Remarks__c) ? '' : laneQuote.Pickup_Remarks__c;
        s.DeliveryRemarks = String.isBlank(laneQuote.Delivery_Remarks__c) ? '' : laneQuote.Delivery_Remarks__c;

        s.Origin = new Party();
        s.Origin.CompanyName = (laneQuote.FreightTM__Pickup_Facility__r==null? null : laneQuote.FreightTM__Pickup_Facility__r.Name);
        s.Origin.Street      = laneQuote.FreightTM__Pickup_Street__c;
        s.Origin.Street2      = '';
        s.Origin.ContactName = laneQuote.Pickup_Contact__c;
        s.Origin.PhoneNumber = laneQuote.Pickup_Phone__c;

        s.Origin.ReadyTime = toHHmm(laneQuote.FreightTM__Pickup_Facility__r.FreightTM__Working_Start_Time__c, '13:00');
        s.Origin.CloseTime = toHHmm(laneQuote.FreightTM__Pickup_Facility__r.FreightTM__Working_End_Time__c,   '16:00');

        
        s.Destination = new Party();
        s.Destination.CompanyName = (laneQuote.FreightTM__Delivery_Facility__r==null? null : laneQuote.FreightTM__Delivery_Facility__r.Name);
        s.Destination.Street      = laneQuote.FreightTM__Delivery_Street__c;
        s.Destination.Street2     = '';
        s.Destination.ContactName = laneQuote.Delivery_Contact__c;
        s.Destination.PhoneNumber = laneQuote.Delivery_Phone__c;

        s.Destination.ReadyTime = toHHmm(laneQuote.FreightTM__Delivery_Facility__r.FreightTM__Working_Start_Time__c, '13:00');
        s.Destination.CloseTime = toHHmm(laneQuote.FreightTM__Delivery_Facility__r.FreightTM__Working_End_Time__c,   '16:00');

        return createShipmentRaw(s);
    }

    private static String blankToDefault(String v, String d){ return String.isBlank(v) ? d : v; }
    
    // Convert Time or "h:mm[:ss] [AM|PM]" string -> "HH:mm". Fallback to dflt.
    private static String toHHmm(Object v, String dflt){
        if (v == null) return dflt;
        try {
            // If it's a real Time field
            if (v instanceof Time) {
                Datetime dt = Datetime.newInstance(Date.newInstance(2000,1,1), (Time)v);
                return dt.format('HH:mm'); // 24-hour minutes
            }
            
            // If it's a string, try to parse "h:mm[:ss] [AM|PM]"
            String s = String.valueOf(v).trim();
            if (String.isBlank(s)) return dflt;
            
            // (?i) = case-insensitive
            Pattern p = Pattern.compile('(?i)^(\\d{1,2}):(\\d{2})(?::(\\d{2}))?\\s*(AM|PM)?$');
            Matcher m = p.matcher(s);
            if (m.matches()){
                Integer hh = Integer.valueOf(m.group(1));
                Integer mm = Integer.valueOf(m.group(2));
                String ap = m.group(4); // AM/PM or null
                
                if (ap != null){
                    Boolean isPM = ap.equalsIgnoreCase('PM');
                    if (hh == 12) hh = 0;     // 12 AM -> 00
                    if (isPM) hh += 12;       // PM -> +12
                }
                if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return dflt;
                
                return (hh < 10 ? '0' : '') + hh + ':' + (mm < 10 ? '0' : '') + mm;
            }
            
            return dflt; // couldn't parse
        } catch (Exception e){
            return dflt;
        }
    }


}
