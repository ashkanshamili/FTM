global virtual with sharing class LaneQuoteIntegrations {
    public Id LaneQuoteId { get; set; }
    
    // ---- Values to show on the first card (GlobalTranz) ----
    public String gtzAmount  { get; private set; }
    public String gtzTransit { get; private set; }
    public String gtzQuoteId { get; private set; }
    public String gtzMessage { get; private set; }
    public String gtzEstDelivery { get; private set; }
    public String LtlDeliveryDate { get; private set; }
    
    public String getProviderName(){
        return GlobalTranzLTLRateCheapestRequest.PROVIDER;
    }

    
    private String fmtDate(Datetime dt){
        if (dt == null) return '';
        return dt.format('MMM dd, yyyy');
    }
    
    public LaneQuoteIntegrations(ApexPages.StandardController controller) {
        LaneQuoteId = ApexPages.currentPage().getParameters().get('id');
    }
    
    // Normalize any numeric string to 2 decimals
    private String to2dp(String v){
        if (String.isBlank(v)) return '';
        try { return String.valueOf(Decimal.valueOf(v).setScale(2, RoundingMode.HALF_UP)); }
        catch (Exception e){ return v; }
    }
    
    // Click handler for the "Get Rate" button
    public PageReference getData() {
        try {
            // Call your cheapest/quickest endpoint
            String raw = GlobalTranzLTLRateCheapestRequest.getCheapestForLoad(LaneQuoteId);
            
            
            // Deserialize into your DTOs
            GlobalTranzLTLRateCheapestRequest.PartnerResponse pr =
                (GlobalTranzLTLRateCheapestRequest.PartnerResponse)
                JSON.deserialize(raw, GlobalTranzLTLRateCheapestRequest.PartnerResponse.class);
            
            // We’ll display LowestCostRate on the first card
            GlobalTranzLTLRateCheapestRequest.RateResult r =
                (pr == null) ? null : pr.LowestCostRate;
            
            if (r != null) {
                gtzAmount  = to2dp(r.LtlAmount);
                gtzTransit = r.LtlServiceDays;
                gtzQuoteId = r.QuoteId;
                gtzMessage = r.CustomMessage;
                gtzEstDelivery = fmtDate(r.LtlDeliveryDate);   
            } else {
                gtzAmount = gtzTransit = gtzQuoteId = gtzMessage = gtzEstDelivery = '';
                ApexPages.addMessage(new ApexPages.Message(
                    ApexPages.Severity.WARNING, 'No GlobalTranz rates were returned.'));
            }
        } catch (Exception e) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR, 'GlobalTranz error: ' + e.getMessage()));
        }
        return null; // stay on page and rerender
    }
    
    // Stub used by your button; unchanged
    public PageReference bookForGlobalTranz(){
        try {
            // you can change this if you want to use a different quote id/provider
            if (String.isBlank(gtzQuoteId)) {
                ApexPages.addMessage(
                    new ApexPages.Message(ApexPages.Severity.ERROR,
                                          'No Quote Id available. Click "Get Rate" first.'));
                return null;
            }
            
            // Call the GTZ booking endpoint
            String raw = GlobalTranzBookShipment.createShipmentForLoad(LaneQuoteId, gtzQuoteId);
            
            // Parse the JSON response
            Map<String,Object> resp =
                (Map<String,Object>) JSON.deserializeUntyped(raw);
            
            // Pull fields (use ymd(...) if you want only the date part)
            String estDelivery = ymd(asString(resp.get('EstimatedDeliveryDate')));
            String shipDate    = ymd(asString(resp.get('ShipmentDate')));
            String svcDays     = asString(resp.get('ServiceDays'));
            String cost        = asString(resp.get('Cost'));
            String carrierName = asString(resp.get('CarrierName'));
            String carrierId   = asString(resp.get('CarrierId'));
            String bolNumber   = asString(resp.get('BOLNumber'));
            
            // ---- Extract Terminal Address + Phone (array OR single object) ----
            String carrierAddr  = '';
            String carrierPhone = '';
            if (resp.containsKey('TerminalAddresses')) {
                Object addrObj = resp.get('TerminalAddresses');
                Map<String, Object> pickAddr;
                
                if (addrObj instanceof List<Object>) {
                    List<Object> addrs = (List<Object>) addrObj;
                    
                    // Prefer AddressType "2", else "1", else first
                    for (Object o : addrs) {
                        Map<String, Object> a = (Map<String, Object>) o;
                        if ('2' == asString(a.get('AddressType'))) { pickAddr = a; break; }
                    }
                    if (pickAddr == null) {
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
                    String company = asString(pickAddr.get('CompanyName'));
                    String street1 = asString(pickAddr.get('Street1'));
                    String street2 = asString(pickAddr.get('Street2'));
                    String city    = asString(pickAddr.get('City'));
                    String state   = asString(pickAddr.get('State'));
                    String zip     = asString(pickAddr.get('Zip'));
                    carrierPhone   = asString(pickAddr.get('Phone'));
                    
                    carrierAddr =
                        (String.isBlank(company) ? '' : (company + ', ')) +
                        street1 +
                        (String.isBlank(street2) ? '' : (', ' + street2)) + ', ' +
                        city + ', ' + state + ' ' + zip;
                }
            }
            
            System.debug('📦 Terminal Address -> ' + carrierAddr);
            System.debug('☎  Terminal Phone   -> ' + carrierPhone);
            
            // Success message
            String msg = 'Shipment booked with GlobalTranz (Quote ' + gtzQuoteId + ').';
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM, msg));
            
            // Save to the Load
            FreightTM__Lane_Quote__c upd = new FreightTM__Lane_Quote__c(
                Id                           = LaneQuoteId,
                Shipment_Info__c             = msg,
                Estimated_Delivery_Date__c   = estDelivery,
                Shipment_Date__c             = shipDate,
                Service_Days__c              = svcDays,
                Carrier_Cost__c              = cost,
                Carrier_Name_Hauler__c       = carrierName,
                Carrier_Id_Hauler__c         = carrierId,
                BOL_Number__c                = bolNumber,
                Carrier_Address__c           = carrierAddr,
                Carrier_Phone__c             = carrierPhone,
                Provider__c                  = GlobalTranzLTLRateCheapestRequest.PROVIDER
            );
            update upd;
            
        } catch (Exception e) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR, 'Booking failed: ' + e.getMessage()));
        }
        return null;
    }
    
    // null-safe to-string
    private static String asString(Object o){
        return o == null ? null : String.valueOf(o);
    }
    // (optional) keep only yyyy-MM-dd from an ISO datetime string
    private static String ymd(String iso){
        return (iso != null && iso.length() >= 10) ? iso.substring(0,10) : iso;
    }
    
    
    public PageReference bookFor(){
        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.INFO, 'Shipment booked successfully.'));
        
        return null;
    }
    
    
}