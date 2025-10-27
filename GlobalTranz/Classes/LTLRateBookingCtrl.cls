public with sharing class LTLRateBookingCtrl {
    // bound to the standard controller record
    public Id LaneQuoteId { get; private set; }
    
    // data exposed to the page
    public GlobalTranzLtlRateRequest.Response resp { get; private set; }
    public String rawJson { get; private set; }
    public String errorMsg { get; private set; }
    
    public String selectedQuoteId { get; set; }
    public String selectedCarrier  { get; set; }
    public String bookingRaw       { get; private set; } // optional: raw JSON/text from booking call
    
    
    public LTLRateBookingCtrl(ApexPages.StandardController std){
        this.LaneQuoteId = std.getId();
    }
    
    // convenience getter for a table
    public List<GlobalTranzLtlRateRequest.RateResult> getRatesList(){
        if (resp == null || resp.RateResults == null) return new List<GlobalTranzLtlRateRequest.RateResult>();
        return resp.RateResults;
    }
    
    public String getProviderName(){
        return GlobalTranzLtlRateRequest.PROVIDER;
    }
    
    // called by the "Get Rate" button
    public PageReference getRates(){
        try {
            errorMsg = null;
            resp    = GlobalTranzLtlRateRequest.getRatesForLoad(LaneQuoteId);
            rawJson = JSON.serializePretty(resp);
        } catch (Exception e){
            resp = null;
            rawJson = null;
            errorMsg = e.getMessage();
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, errorMsg));
        }
        return null; // stay on page and rerender
    }
    
    // called by the "book shipment" button
    public PageReference bookShipment(){
        // read from the request
        selectedQuoteId = ApexPages.currentPage().getParameters().get('qid');
        selectedCarrier  = ApexPages.currentPage().getParameters().get('car');
        
        try {
            if (String.isBlank(selectedQuoteId)) {
                throw new AuraHandledException('No Quote Id on the selected row.');
            }
            
            // (optional) prove we have it
            System.debug('Booking with QuoteId=' + selectedQuoteId + ', Carrier=' + selectedCarrier);
            
            // Call booking API
            String raw = GlobalTranzBookShipment.createShipmentForLoad(LaneQuoteId, selectedQuoteId);
            bookingRaw  = raw;
            
            // ---- parse the JSON we care about ----
            Map<String,Object> m = (Map<String,Object>) JSON.deserializeUntyped(raw);
            
            String estDelivery = ymd(asString(m.get('EstimatedDeliveryDate')));
            String shipDate    = ymd(asString(m.get('ShipmentDate')));
            String svcDays     = asString(m.get('ServiceDays'));
            String cost        = asString(m.get('Cost'));
            String carrierName = asString(m.get('CarrierName'));
            String carrierId   = asString(m.get('CarrierId'));
            String bolNumber   = asString(m.get('BOLNumber'));
            // ---- Extract Terminal Address + Phone ----
            String carrierAddr  = '';
            String carrierPhone = '';
            if (m.containsKey('TerminalAddresses')) {
                Object addrObj = m.get('TerminalAddresses');
                
                // helper to pick a single address map (prefer AddressType "2", else "1", else first)
                Map<String, Object> pickAddr;
                if (addrObj instanceof List<Object>) {
                    List<Object> addrs = (List<Object>) addrObj;
                    for (Object o : addrs) {
                        Map<String, Object> a = (Map<String, Object>) o;
                        if ('2' == asString(a.get('AddressType'))) { pickAddr = a; break; }
                    }
                    if (pickAddr == null && !addrs.isEmpty()) {
                        // try AddressType "1"
                        for (Object o : addrs) {
                            Map<String, Object> a = (Map<String, Object>) o;
                            if ('1' == asString(a.get('AddressType'))) { pickAddr = a; break; }
                        }
                    }
                    if (pickAddr == null && !addrs.isEmpty()) {
                        pickAddr = (Map<String, Object>) addrs[0];
                    }
                } else if (addrObj instanceof Map<String, Object>) {
                    pickAddr = (Map<String, Object>) addrObj;
                }
                
                if (pickAddr != null) {
                    // Build a readable address
                    carrierAddr =
                        (asString(pickAddr.get('CompanyName'))==null?'':asString(pickAddr.get('CompanyName')) + ', ') +
                        asString(pickAddr.get('Street1')) + 
                        (String.isBlank(asString(pickAddr.get('Street2'))) ? '' : (', ' + asString(pickAddr.get('Street2')))) + ', ' +
                        asString(pickAddr.get('City')) + ', ' +
                        asString(pickAddr.get('State')) + ' ' +
                        asString(pickAddr.get('Zip'));
                    
                    // Phone (as-is)
                    carrierPhone = asString(pickAddr.get('Phone'));
                }
            }
            
            System.debug('📦 Parsed Terminal Address: ' + carrierAddr);
            System.debug('☎  Parsed Terminal Phone:   ' + carrierPhone);
            
            // Success message
            String msg = 'Shipment booked with ' + selectedCarrier + ' (Quote Id ' + selectedQuoteId + ').';
            
            // 1) show green toast
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM, msg));
            
            // 2) save to Load (your fields are Text, so assign strings directly)
            update new FreightTM__Lane_Quote__c(
                Id                         = LaneQuoteId,
                Shipment_Info__c           = msg,
                Estimated_Delivery_Date__c = estDelivery,
                Shipment_Date__c           = shipDate,
                Service_Days__c            = svcDays,
                Carrier_Cost__c            = cost,
                Carrier_Name_Hauler__c     = carrierName,
                Carrier_Id_Hauler__c       = carrierId,
                BOL_Number__c              = bolNumber,
                Carrier_Address__c         = carrierAddr,
                Carrier_Phone__c           = carrierPhone,
                Provider__c                = GlobalTranzLtlRateRequest.PROVIDER
            );
            
        } catch (Exception e){
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR, 'Booking failed: ' + e.getMessage()
            ));
        }
        return null;
    }
    
    // null-safe string
    private static String asString(Object o){
        return o == null ? null : String.valueOf(o);
    }
    // keep only yyyy-MM-dd from an ISO datetime string (optional)
    private static String ymd(String iso){
        return (iso != null && iso.length() >= 10) ? iso.substring(0,10) : iso;
    }
    
    
    
}
