public with sharing class GlobalTranzLTLRateCheapestRequest {

    public static final String PROVIDER = 'GB';
    // ===== Auth / Config =====
    private static final String BASE = 'https://dev.gtzintegrate.com/';
    //private static final String BASE = 'https://api.gtzintegrate.com/';  ==> production
    private static final String PATH = 'rate/ltl/partner';
    private static final String SUBSCRIPTION_KEY = 'Your-Key';
    private static final String USERNAME = 'Your-Username';
    private static final String PASSWORD = 'Your-Password';
    
    // ---- Debug helpers (safe & chunked) ----
    private static final Integer DBG_CHUNK = 12000;
    
    private static void logBig(String label, String s){
        if (s == null) { System.debug(label + ': <null>'); return; }
        for (Integer i = 0; i < s.length(); i += DBG_CHUNK){
            System.debug(label + ' [' + i + '-' + Math.min(i+DBG_CHUNK, s.length()) + ']: '
                         + s.substring(i, Math.min(i+DBG_CHUNK, s.length())));
        }
    }


    // ===== DTOs =====
    public class Address {
        //public String CompanyName;
        public String Street;
        public String City;
        public String State;
        public String Zip;
        public String Country;
    }
    public class Item {
        public Integer PieceCount;
        public Integer PalletCount;
        public Integer Length;
        public Integer Width;
        public Integer Height;
        public Integer Weight;
        public Integer WeightType;     // 1 = pounds, 0 = KG
        public Integer ProductClass;
        public Integer LinearFeet;
        public String  NmfcNumber;
        public String  Description;
        public Integer PackageType;    // from Handling__c mapping
        public Boolean Hazmat;
        public Integer HazmatClass;
        public String  PackingGroupNumber;
        public String  UnPoNumber;
        public Boolean Stackable;
    }
    public class RateRequest {
        public String  CustomerId;
        public Boolean GuaranteedRates;
        public String  PickupDate; // MM/dd/yyyy
        public Integer ExtremeLength;
        public Integer ExtremeLengthBundleCount;
        public Boolean Stackable;
        public Boolean TerminalPickup;
        public String  ContactName;
        public Decimal ValueOfGoods;
        public Boolean ShipmentNew;
        public Address Origin;
        public Address Destination;
        public List<Item> Items;
        public List<Integer> Accessorials;
    }
    
    // ====== DTOs: Response 
    public class PartnerResponse {
        public RateResult LowestCostRate { get; set; }
        public RateResult QuickestTransitRate { get; set; }
    }
    public class RateResult {
        public String  CustomerId { get; set; }
        public String  CustomerName { get; set; }
        public Datetime QuoteCreatedDate { get; set; }
        public String  VolumeQuote { get; set; }
        public String  CustomMessage { get; set; }
        public String  LtlAmount { get; set; }
        public String  LtlServiceDays{ get; set; }
        public String  PalletAmount{ get; set; }
        public String  PalletServiceDays { get; set; }
        public String  LiabilityPallet{ get; set; }
        public String  UsedLoadLiability{ get; set; }
        public String  NewLoadLiability{ get; set; }
        public Datetime LtlDeliveryDate{ get; set; }
        public String  LtlServiceTypeName{ get; set; }
        public String  IsOceanShipment{ get; set; }
        public String  OceanServiceDays{ get; set; }
        public String  OceanCarrierName{ get; set; }
        public String  OceanCarrierId{ get; set; }
        public String  HubZipCode{ get; set; }
        public String  MultilegCarrierHubAddress{ get; set; }
        public String  MultilegCarrierDetails{ get; set; }
        public String  MultilegCarrierShipDays{ get; set; }
        public Datetime OceanDeliveryDate{ get; set; }
        public Datetime OceanPickupDate{ get; set; }
        public String  ReleaseValue{ get; set; }
        public String  MaxReleaseValue{ get; set; }
        public String  OriginTerminalCode{ get; set; }
        public String  DestinationTerminalCode{ get; set; }
        public Datetime EstimatedDeliveryDate{ get; set; }
        public String  LTLCalendarDays{ get; set; }
        public String  OceanCalendarDays{ get; set; }
        public String  CalendarDays{ get; set; }
        public String  SpotQuoteNumber{ get; set; }
        public String  SpotQuoteCreationTime{ get; set; }
        public String  QuoteId{ get; set; }
        public List<Charge> Charges { get; set; }
        public Prohibited ProhibitedCommodityList{ get; set; }
        public Carrier  CarrierDetail{ get; set; }
    }
    public class Charge {
        public String AccessorialID { get; set; }
        public String Name{ get; set; }
        public String Charge{ get; set; }
    }
    public class Prohibited { 
        public String Description{ get; set; }
        public String Summary{ get; set; } 
    }
    public class Carrier { 
        public String CarrierId{ get; set; }
        public String CarrierName{ get; set; }
        public String CarrierCode{ get; set; }
    }
    
    // ===== Public: call for a Load and return raw JSON =====
    public static String getCheapestForLoad(Id LaneQuoteId){
        RateRequest req = buildRequestFromLoad(LaneQuoteId);
        return call(req);
    }

    // ===== Build request from Load (your exact mapping) =====
    private static RateRequest buildRequestFromLoad(Id LaneQuoteId){
        FreightTM__Lane_Quote__c laneQuote = [
                    SELECT  Id, Name, FreightTM__Rate_to_Carrier__c,FreightTM__Description__c,
                    FreightTM__Customer__c, FreightTM__Customer_Rate__c, Customer_Id__c, Contact_Name__c,
                    //---- Origin 
                    FreightTM__Estimated_Pickup_Time__c, FreightTM__Pickup_Facility__c, FreightTM__Pickup_Facility__r.Name, FreightTM__Pickup_Street__c,
                    FreightTM__Pickup_City__c,FreightTM__Pickup_State__c,FreightTM__Pickup_Zip_Code__c,FreightTM__Pickup_Country__c,
                    FreightTM__Pickup_Facility__r.FreightTM__Working_End_Time__c,FreightTM__Pickup_Facility__r.FreightTM__Working_Start_Time__c,
                    //---- Destination 
                    FreightTM__Estimated_Delivery_Time__c, FreightTM__Delivery_Facility__c, FreightTM__Delivery_Facility__r.Name, FreightTM__Delivery_Street__c,
                    FreightTM__Delivery_City__c,FreightTM__Delivery_State__c,FreightTM__Delivery_Zip_Code__c,FreightTM__Delivery_Country__c,
                    FreightTM__Delivery_Facility__r.FreightTM__Working_End_Time__c,FreightTM__Delivery_Facility__r.FreightTM__Working_Start_Time__c,
                    //---- Freight details 
                    Length__c,Height__c,Width__c,FreightTM__Weight__c,Class__c,NMFC__c,Handling__c,Shipment_Info__c,
                    Number_of_Pallets__c,Hazmat__c,Stackable__c,Number_of_Pieces__c,Hazmat_Class__c,Linear_Feet__c,Accessorials__c,PO__c

            FROM FreightTM__Lane_Quote__c
            WHERE Id = :LaneQuoteId
            LIMIT 1
        ];

        RateRequest rr = new RateRequest();
        rr.CustomerId = nz((String)laneQuote.get('Customer_Id__c'));

        Datetime puDt = (Datetime) laneQuote.get('FreightTM__Estimated_Pickup_Time__c');
        rr.PickupDate = fmtMMddyyyy(puDt == null ? null : puDt.date());

        rr.ContactName              = nz((String)laneQuote.get('Contact_Name__c'));
        rr.ValueOfGoods             = (Decimal)laneQuote.get('FreightTM__Rate_to_Carrier__c');
        rr.GuaranteedRates          = false;
        rr.ExtremeLength            = toInt(laneQuote.get('Length__c'), null);
        rr.ExtremeLengthBundleCount = toInt(laneQuote.get('Length__c'), null);
        rr.Stackable                = bz((Boolean)laneQuote.get('Stackable__c'));
        rr.TerminalPickup           = false;
        rr.ShipmentNew              = false;

        rr.Origin = new Address();
        rr.Origin.Street  = nz((String)laneQuote.get('FreightTM__Pickup_Street__c'));
        rr.Origin.City    = nz((String)laneQuote.get('FreightTM__Pickup_City__c'));
        rr.Origin.State   = nz((String)laneQuote.get('FreightTM__Pickup_State__c'));
        rr.Origin.Zip     = nz((String)laneQuote.get('FreightTM__Pickup_Zip_Code__c'));
        rr.Origin.Country = 'USA';

        rr.Destination = new Address();
        rr.Destination.Street  = nz((String)laneQuote.get('FreightTM__Delivery_Street__c'));
        rr.Destination.City    = nz((String)laneQuote.get('FreightTM__Delivery_City__c'));
        rr.Destination.State   = nz((String)laneQuote.get('FreightTM__Delivery_State__c'));
        rr.Destination.Zip     = nz((String)laneQuote.get('FreightTM__Delivery_Zip_Code__c'));
        rr.Destination.Country = 'USA';

        Item it = new Item();
        it.PieceCount        = toInt(laneQuote.get('Number_of_Pieces__c'), null);
        it.PalletCount       = toInt(laneQuote.get('Number_of_Pallets__c'), null);
        it.Length            = toInt(laneQuote.get('Length__c'), null);
        it.Width             = toInt(laneQuote.get('Width__c'), null);
        it.Height            = toInt(laneQuote.get('Height__c'), null);
        it.Weight            = toInt(laneQuote.get('FreightTM__Weight__c'), null);
        it.WeightType        = 1; // 1 = pounds / 0 = KG
        it.ProductClass      = toInt(laneQuote.get('Class__c'), null);
        it.LinearFeet        = toInt(laneQuote.get('Linear_Feet__c'), null);
        it.NmfcNumber        = nz((String)laneQuote.get('NMFC__c'));
        it.Description       = nz((String)laneQuote.get('FreightTM__Description__c'));
        it.PackageType       = mapPackageType((String) laneQuote.get('Handling__c'));
        it.Hazmat            = bz((Boolean)laneQuote.get('Hazmat__c'));
        it.HazmatClass       = toInt(laneQuote.get('Hazmat_Class__c'), null);
        it.PackingGroupNumber= '';
        it.UnPoNumber        = nz((String)laneQuote.get('PO__c'));
        it.Stackable         = bz((Boolean)laneQuote.get('Stackable__c'));

        rr.Items = new List<Item>{ it };

        // Accessorials (multi-select picklist -> list of ints)
        String accRaw = (String) laneQuote.get('Accessorials__c'); // multi-select returns semi-colon list
        List<Integer> acc = mapAccessorials(accRaw);
        
        // If you want a fallback when none present:
        if (acc.isEmpty()) acc = new List<Integer>(); // or defaults like new List<Integer>{12,13,14}
        
        rr.Accessorials = acc;

        return rr;
    }

    // ===== Callout =====
    private static String call(RateRequest req){

        try {
            String prettyReq = JSON.serializePretty(JSON.deserializeUntyped(JSON.serialize(req)));
            logBig('[GTZ Rate] REQUEST (pretty)', prettyReq);
        } catch (Exception ignore) {
            logBig('[GTZ Rate] REQUEST (raw)', JSON.serialize(req));
        }
        HTTPResponse res = GlobalTranzHttpRequest.send(JSON.serialize(req), 'rate/ltl/partner', 'POST');
        // Always log HTTP status
        System.debug('[GTZ Rate] STATUS: ' + res.getStatusCode() + ' ' + res.getStatus());
        
        // Log raw body
        logBig('[GTZ Rate] RESPONSE (raw)', res.getBody());
        
        // Try to pretty-print JSON for readability
        try {
            String pretty = JSON.serializePretty(JSON.deserializeUntyped(res.getBody()));
            logBig('[GTZ Rate] RESPONSE (pretty)', pretty);
        } catch (Exception e){
            System.debug('[GTZ Rate] RESPONSE pretty-print failed: ' + e.getMessage());
        }
        

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            return res.getBody(); // raw JSON (cheapest/quickest result set)
        }
        throw new CalloutException('Cheapest rate call failed: ' +
                                   res.getStatus() + ' — ' + res.getBody());
    }

    // ===== Helpers =====
    private static Integer toInt(Object v, Integer dflt){
        if (v == null) return dflt;
        if (v instanceof Integer) return (Integer)v;
        if (v instanceof Long)    return Integer.valueOf(String.valueOf((Long)v));
        if (v instanceof Decimal) return ((Decimal)v).intValue();
        if (v instanceof String)  return String.isBlank((String)v) ? dflt : Integer.valueOf((String)v);
        return dflt;
    }
    private static Boolean bz(Boolean b){ return b==null? false : b; }
    private static String nz(String s){ return String.isBlank(s)? '' : s; }

    private static String fmtMMddyyyy(Date d){
        if (d == null) return '';
        String mm = (d.month()<10?'0':'') + d.month();
        String dd = (d.day()  <10?'0':'') + d.day();
        return mm + '/' + dd + '/' + d.year();
    }

    // Handling__c (picklist label) -> PackageType code (0..17)
    private static Integer mapPackageType(String handling){
        if (String.isBlank(handling)) return 0;
        String k = handling.trim().toLowerCase();
        Map<String,Integer> m = new Map<String,Integer>{
                'Std Pallets'          => 0,
                'Pallets - Non Std'    => 1,
                'Bags'                 => 2,
                'Bales'                => 3,
                'Boxes'                => 4,
                'Bunches'              => 5,
                'Carpets'              => 6,
                'Coils'                => 7,
                'Crates'               => 8,
                'Cylinders'            => 9,
                'Drums'                => 10,
                'Pails'                => 11,
                'Reels'                => 12,
                'Rolls'                => 13,
                'Tubes/Pipes'          => 14,
                'Loose'                => 15,
                'Bundles'              => 16,
                'Tote'                 => 17
        };
        Integer code = m.get(k);
        return code==null?0:code;
    }

    // valid GTZ accessorial IDs (from the spec)
    private static final Set<Integer> VALID_ACCESSORIALS = new Set<Integer>{
        11,12,13,14,15,17,39,41,43,45,47,49,51,53,55,57,59,61,63,65,67,69,71,
            98,103,104,105,108,116,120,121,122,123,124,125,126,127,128,129,130,
            131,132,133,134,135,136,137,138,139,152,153
            };
                
                // (optional) label → id, in case your API value is labels
                private static final Map<String,Integer> ACCESSORIAL_LABELS = new Map<String,Integer>{
                    'Lift Gate Pickup' => 11,
                        'Lift Gate Delivery' => 12,
                        'Residential Pickup' => 13,
                        'Residential Delivery' => 14,
                        'Inside Delivery' => 15,
                        'Notify Prior To Arrival' => 17,
                        'Non Commercial Delivery - Airport' => 39,
                        'Non Commercial Delivery - Construction/Utility Site' => 41,
                        'Non Commercial Delivery - Correctional Facility' => 43,
                        'Non Commercial Delivery - Military Base' => 45,
                        'Non Commercial Delivery - Piers/Wharves' => 47,
                        'Non Commercial Delivery - Storage Facility' => 49,
                        'Non Commercial Delivery - Church' => 51,
                        'Non Commercial Delivery - Farm' => 53,
                        'Non Commercial Delivery - School' => 55,
                        'Non Commercial Delivery - Ranch' => 57,
                        'Non Commercial Delivery - Country Club' => 59,
                        'Non Commercial Delivery - Shopping Mall' => 61,
                        'Non Commercial Delivery - Mines/Quarries' => 63,
                        'Non Commercial Delivery - Golf Course' => 65,
                        'Non Commercial Delivery - Nursing Homes' => 67,
                        'Non Commercial Delivery - Government Site' => 69,
                        'Non Commercial Delivery - Container Freight Station' => 71,
                        'Non Commercial Delivery - Hotel' => 98, 
                        'Notification Pickup' => 103,
                        'Notification Delivery' => 104,
                        'Inside Pickup' => 105,
                        'Sort and Segregate' => 108,
                        'Protect From Freeze' => 116,
                        
                        'Non Commercial Pickup - Airport' => 120,
                        'Non Commercial Pickup - Construction/Utility Site' => 121,
                        'Non Commercial Pickup - Correctional Facility' => 122,
                        'Non Commercial Pickup - Military Base' => 123,
                        'Non Commercial Pickup - Piers / Wharves' => 124,
                        'Non Commercial Pickup - Storage Facility' => 125,
                        'Non Commercial Pickup - Church' => 126,
                        'Non Commercial Pickup - Farm' => 127,
                        'Non Commercial Pickup - School' => 128,
                        'Non Commercial Pickup - Ranch' => 129,
                        'Non Commercial Pickup - Country Club' => 130,
                        'Non Commercial Pickup - Shopping Malls' => 131,
                        'Non Commercial Pickup - Mines / Quaries' => 132,
                        'Non Commercial Pickup - Golf Course' => 133,
                        'Non Commercial Pickup - Nursing Homes' => 134,
                        'Non Commercial Pickup - Government Site' => 135,
                        'Non Commercial Pickup - Container Freight Station' => 136,
                        'Non Commercial Pickup - Hotel' => 137,
                        
                        'Non Commercial Pickup - Limited Access' => 138,
                        'Non Commercial Delivery - Limited Access' => 139,
                        
                        'Appointment Pickup' => 152,
                        'Appointment Delivery' => 153
                        };
                            
                            // Parse Accessorials__c (e.g., "12 - Lift Gate Delivery;13 - Residential Pickup;...")
                            private static List<Integer> mapAccessorials(String raw) {
                                Set<Integer> out = new Set<Integer>();
                                if (String.isBlank(raw)) return new List<Integer>();
                                
                                for (String token : raw.split(';')) {
                                    String t = String.isBlank(token) ? '' : token.trim();
                                    if (t == '') continue;
                                    
                                    // 1) try leading number before first non-digit (handles "12 - Lift Gate Delivery")
                                    Integer code;
                                    Integer i = 0;
                                    while (i < t.length() && t.substring(i, i+1) >= '0' && t.substring(i, i+1) <= '9') i++;
                                    if (i > 0) {
                                        code = Integer.valueOf(t.substring(0, i));
                                    } else {
                                        // 2) fall back to label lookup
                                        Integer mapped = ACCESSORIAL_LABELS.get(t.toLowerCase());
                                        if (mapped != null) code = mapped;
                                    }
                                    
                                    if (code != null && VALID_ACCESSORIALS.contains(code)) out.add(code);
                                }
                                return new List<Integer>(out);
                            }
}
