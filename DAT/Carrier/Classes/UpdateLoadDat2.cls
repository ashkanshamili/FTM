public with sharing class UpdateLoadDat2 {
    
    // Convenience overload: pull DAT_Post_Id__c from the Load
    public static String execute(Id loadId) {
        FreightTM__Load__c L = [
            SELECT DAT_Post_Id__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];
        return execute(loadId, L.DAT_Post_Id__c);
    }
    
    // Main entry
    public static String execute(Id loadId, String datPostId) {
        if (String.isBlank(datPostId)) {
            throw new AuraHandledException('Missing DAT Post Id.');
        }
        // 1) auth
        String orgTok  = PostLoadDat2.getOrganizationToken();
        if (String.isBlank(orgTok))  throw new CalloutException('Org token failed');
        String userTok = PostLoadDat2.getUserToken(orgTok);
        if (String.isBlank(userTok)) throw new CalloutException('User token failed');
        
        // 2) load data
        FreightTM__Load__c L = [
            SELECT Id, FreightTM__Size__c, FreightTM__Remarks__c,FreightTM__Required_Trailer__c, Linear_Feet__c, FreightTM__Weight__c,
            FreightTM__Pickup_Departure__c, FreightTM__Delivery_Arrival__c, FreightTM__Delivery_Departure__c, FreightTM__Pickup_Arrival__c
            FROM FreightTM__Load__c WHERE Id = :loadId LIMIT 1
        ];
        
        // ---- Availability window (lenient) ----
        Datetime nowGmt = Datetime.now();
        Datetime earliest = (L.FreightTM__Pickup_Arrival__c != null) ? L.FreightTM__Pickup_Arrival__c : nowGmt;
        
        Datetime latest;
        if (L.FreightTM__Delivery_Arrival__c != null) {
            latest = Datetime.newInstance(L.FreightTM__Delivery_Arrival__c.date(), Time.newInstance(23, 59, 59, 999));
        } else if (L.FreightTM__Pickup_Arrival__c != null) {
            latest = Datetime.newInstance(L.FreightTM__Pickup_Arrival__c.date(), Time.newInstance(23, 59, 59, 999));
        } else {
            latest = Datetime.newInstance(nowGmt.date(), Time.newInstance(23, 59, 59, 999));
        }
        if (latest < earliest) {
            latest = Datetime.newInstance(earliest.date(), Time.newInstance(23, 59, 59, 999));
        }
        Datetime sixMonths = nowGmt.addMonths(6).addSeconds(-1);
        if (latest > sixMonths) {
            latest = Datetime.newInstance(sixMonths.date(), Time.newInstance(23, 59, 59, 999));
        }
        
        // 3) PATCH body
        Map<String,Object> body = new Map<String,Object>();
        Map<String,Object> exposure = new Map<String,Object>{
            'preferredContactMethod'   => 'PRIMARY_PHONE',
                'earliestAvailabilityWhen' => earliest,
                'latestAvailabilityWhen'   => latest
                // If needed later:
                // 'startWhen' => nowGmt,
                // 'endWhen'   => latest
                };
                    body.put('exposure', exposure);
        
        Map<String,Object> freight = new Map<String,Object>();
        if (L.Linear_Feet__c != null)            
            freight.put('lengthFeet',    L.Linear_Feet__c);
        if (L.FreightTM__Weight__c != null)  
            freight.put('weightPounds', L.FreightTM__Weight__c);
        
        // NEW: equipmentType from Required_Trailer__c
        String equipmentType = mapEquipmentType(L.FreightTM__Required_Trailer__c);
        if (!String.isBlank(equipmentType)) {
            freight.put('equipmentType', equipmentType);
        }
        
        String fullPartial = mapFullPartial(L.FreightTM__Size__c);
        if (fullPartial != null) freight.put('fullPartial', fullPartial);
        
        
        String pickWin = makeWindow(L.FreightTM__Pickup_Departure__c, L.FreightTM__Delivery_Arrival__c);
        String dropWin = makeWindow(L.FreightTM__Delivery_Departure__c, L.FreightTM__Pickup_Arrival__c);
        if (pickWin != null) freight.put('pickupHours',  pickWin);
        if (dropWin != null) freight.put('dropOffHours', dropWin);
        
        if (!String.isBlank(L.FreightTM__Remarks__c)) {
            List<Object> comments = new List<Object>{
                new Map<String,Object>{ 'comment' => L.FreightTM__Remarks__c }
            };
                freight.put('comments', comments);
        }
        body.put('freight', freight);
        System.debug('PATCH BODY → ' + JSON.serializePretty(body));
        
        // 4) call PATCH
        String endpoint = 'https://freight.api.staging.dat.com/posting/v2/loads/' +
            EncodingUtil.urlEncode(datPostId, 'UTF-8');
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('PATCH');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setHeader('x-dat-partner-id', '001f400001M2BglAAF');
        req.setHeader('Authorization', 'Bearer ' + userTok);
        req.setBody(JSON.serialize(body));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        System.debug('DAT PATCH RES -> ' + res.getStatusCode() + ' ' + res.getBody());
        
        if (res.getStatusCode() == 200) {
            return res.getBody();
        }
        throw new CalloutException('DAT update failed: ' + res.getStatus() + ' ' + res.getStatusCode() + ' - ' + res.getBody());
    }
    
    private static String mapFullPartial(String svc) {
        if (String.isBlank(svc)) return null;
        if (svc == 'STL') return 'PARTIAL';
        if (svc == 'FTL' || svc == 'Expedited') return 'FULL';
        return null;
    }
    

    private static String mapEquipmentType(String requiredTrailer) {
        if (String.isBlank(requiredTrailer)) return 'V'; // safe default (Van)
        
        switch on requiredTrailer {
            when 'Sprinter Van'                          { return 'SV'; } // was V (wrong)
            when 'Dry Van Trailer - Door clearance 110" tall required' { return 'V'; } // plain Van is safest
            when 'Straight Box Truck - door clearance minimum 96"x96" required' { return 'SB'; }
            when 'Reefer'                                { return 'R'; }
            when 'Flatbed'                               { return 'F'; }
            when 'Step Deck - Conestoga'                 { return 'SN'; }
            when 'Flatbed - Conestoga'                   { return 'FN'; }
            when 'Power Only'                            { return 'PO'; }
            when 'Lowboy'                                { return 'LB'; }
            when 'Step Deck'                             { return 'SD'; }
            when 'Low Pro Step-Deck'                     { return 'SD'; } // not LA; LA = Landoll
            when 'Extendable Flatbed Stretch'            { return 'ST'; }
            when 'Stretch Single Drop Deck'              { return 'ST'; } // closest match
            when 'Stretch Double Drop'                   { return 'DD'; }
            when 'Extendable Double Drop'                { return 'DD'; }
            when 'Removable Gooseneck'                   { return 'RG'; }
            when 'Conestoga'                             { return 'CN'; }
            when 'Side Kit'                              { return 'FS'; }
            when 'Rail'                                  { return 'C'; }  // Container
            when 'Specialized'                           { return 'SR'; } // Step Deck or RGN
            when 'Hot Shot Flatbed'                      { return 'FH'; }
            when 'Tilt'                                  { return 'F'; }  // no dedicated code; use flatbed
            when else                                    { return 'V'; }
        }
    }

    @TestVisible
    private static String makeWindow(Datetime startDt, Datetime endDt) {
        if (startDt == null && endDt == null) return null;
        if (startDt != null && endDt != null) {
            return startDt.format('ha', 'en_US').toLowerCase()
                + ' to '
                + endDt.format('ha', 'en_US').toLowerCase();
        }
        Datetime only = (startDt != null) ? startDt : endDt;
        return only.format('ha', 'en_US').toLowerCase();
    }
}