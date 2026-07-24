public without sharing class LoadBoardForCarrierController {

    /*
     * This controller is designed for an Experience Cloud/public load board.
     *
     * IMPORTANT:
     * Carrier Name + MC Number is an access gate, not strong authentication.
     * Do not return confidential load or carrier information from this class.
     */

    private static final Integer MAX_LOGIN_ATTEMPT_LENGTH = 100;
    private static final Integer MAX_SEARCH_LENGTH = 100;
    private static final Integer MAX_LOAD_RESULTS = 500;

    //public class LoginRequest {
    //    @AuraEnabled public String carrierName;
    //    @AuraEnabled public String mcNumber;
    //}

    public class CarrierSession {
        @AuraEnabled public Id carrierId;
        @AuraEnabled public String carrierName;
        @AuraEnabled public String mcNumber;
    }

    public class LoadBoardResponse {
        @AuraEnabled public CarrierSession carrier;
        @AuraEnabled public List<LoadRow> loads;
        @AuraEnabled public Integer openOpportunityCount;
        @AuraEnabled public Integer submittedBidCount;
    }

    public class LoadRow {
        @AuraEnabled public Id loadId;
        @AuraEnabled public String loadName;
        @AuraEnabled public String status;
        @AuraEnabled public String trailerType;
        @AuraEnabled public Decimal loadRate;

        @AuraEnabled public Date pickupDate;
        @AuraEnabled public String pickupStreet;
        @AuraEnabled public String pickupCity;
        @AuraEnabled public String pickupState;
        @AuraEnabled public String pickupZip;
        @AuraEnabled public String pickupAddress;

        @AuraEnabled public Date deliveryDate;
        @AuraEnabled public String deliveryStreet;
        @AuraEnabled public String deliveryCity;
        @AuraEnabled public String deliveryState;
        @AuraEnabled public String deliveryZip;
        @AuraEnabled public String deliveryAddress;

        @AuraEnabled public String remarks;
        @AuraEnabled public Decimal numberOfPallets;
        @AuraEnabled public Decimal weight;
        @AuraEnabled public Decimal length;
        @AuraEnabled public Decimal width;
        @AuraEnabled public Decimal height;
        @AuraEnabled public Decimal totalCargoVolume;

        @AuraEnabled public String lane;
        @AuraEnabled public String searchText;
    }

   // public class BidRequest {
   //     @AuraEnabled public Id carrierId;
   //     @AuraEnabled public Id loadId;
   //     @AuraEnabled public Decimal rate;
   //     @AuraEnabled public Datetime transitionDate;
   // }

    public class BidResponse {
        @AuraEnabled public Id bidId;
        @AuraEnabled public String message;
        @AuraEnabled public String requestId;
    }
    
    public class MyBidRow {
        @AuraEnabled public Id bidId;
        @AuraEnabled public String bidName;
        
        @AuraEnabled public Id loadId;
        @AuraEnabled public String loadName;
        
        @AuraEnabled public Decimal rate;
        @AuraEnabled public String transitTime;
        @AuraEnabled public Datetime submittedDate;
    }
    
    public class MyBidsResponse {
        @AuraEnabled public CarrierSession carrier;
        @AuraEnabled public List<MyBidRow> bids;
        @AuraEnabled public Integer submittedBidCount;
    }
    
    public class AssignedLoadRow {
        @AuraEnabled public Id loadId;
        @AuraEnabled public String loadName;
        @AuraEnabled public String status;
        @AuraEnabled public String trailerType;
        
        @AuraEnabled public String pickupAddress;
        @AuraEnabled public Date pickupDate;
        
        @AuraEnabled public Decimal weight;
        @AuraEnabled public Decimal rate;
    }
    
    public class AssignedLoadsResponse {
        @AuraEnabled public CarrierSession carrier;
        @AuraEnabled public List<AssignedLoadRow> loads;
        @AuraEnabled public Integer assignedLoadCount;
    }

    @AuraEnabled
    public static LoadBoardResponse loginCarrier(
        String carrierName,
        String mcNumber
    ) {
        validateLoginRequest(carrierName, mcNumber);
        
        String normalizedCarrierName = carrierName.trim();
        String normalizedMcNumber = mcNumber.trim();

        /*
         * Ready_for_Loads__c and Load_Board_Active__c are mandatory.
         * LIMIT 2 allows us to reject ambiguous duplicate login records.
         */
        List<FreightTM__Carrier__c> carriers = [
            SELECT
                Id,
                Name,
                FreightTM__MC_MX_FF_Number__c,
                Ready_for_Loads__c,
                Load_Board_Active__c
            FROM FreightTM__Carrier__c
            WHERE Name = :normalizedCarrierName
                AND FreightTM__MC_MX_FF_Number__c = :normalizedMcNumber
                AND Ready_for_Loads__c = TRUE
                AND Load_Board_Active__c = TRUE
            LIMIT 2
        ];

        if (carriers.isEmpty()) {
            throw new AuraHandledException(
                'Carrier not found or the carrier is not approved for the load board.'
            );
        }

        if (carriers.size() > 1) {
            throw new AuraHandledException(
                'Multiple carrier records match this information. Contact the administrator.'
            );
        }

        FreightTM__Carrier__c carrier = carriers[0];

        LoadBoardResponse response = new LoadBoardResponse();
        response.carrier = createCarrierSession(carrier);
        response.loads =
            queryAvailableLoads(
                carrier.Id
            );
        response.openOpportunityCount = response.loads.size();
        response.submittedBidCount =
            countCarrierBids(
                carrier.Id
            );

        return response;
    }

    @AuraEnabled
    public static LoadBoardResponse refreshLoadBoard(
        Id carrierId,
        String carrierName,
        String mcNumber
    ) {
        FreightTM__Carrier__c carrier = validateCarrierSession(
            carrierId,
            carrierName,
            mcNumber
        );

        LoadBoardResponse response = new LoadBoardResponse();
        response.carrier = createCarrierSession(carrier);
        response.loads =
            queryAvailableLoads(
                carrier.Id
            );
        response.openOpportunityCount = response.loads.size();
        response.submittedBidCount =
            countCarrierBids(
                carrier.Id
            );

        return response;
    }
    
    @AuraEnabled
    public static MyBidsResponse getMyBids(
        Id carrierId,
        String carrierName,
        String mcNumber
    ) {
        FreightTM__Carrier__c carrier =
            validateCarrierSession(
                carrierId,
                carrierName,
                mcNumber
            );
        
        List<FreightTM__Bid__c> bidRecords = [
            SELECT
            Id,
            Name,
            FreightTM__Carrier__c,
            FreightTM__Load__c,
            FreightTM__Load__r.Name,
            FreightTM__Rate__c,
            Transit_Time__c,
            CreatedDate
            FROM FreightTM__Bid__c
            WHERE FreightTM__Carrier__c =
            :carrier.Id
            ORDER BY CreatedDate DESC
            LIMIT 500
        ];
        
        List<MyBidRow> bidRows =
            new List<MyBidRow>();
        
        for (
            FreightTM__Bid__c bidRecord :
            bidRecords
        ) {
            MyBidRow row =
                new MyBidRow();
            
            row.bidId =
                bidRecord.Id;
            
            row.bidName =
                bidRecord.Name;
            
            row.loadId =
                bidRecord.FreightTM__Load__c;
            
            row.loadName =
                bidRecord.FreightTM__Load__r != null
                ? bidRecord
                .FreightTM__Load__r
                .Name
                : 'Load not available';
            
            row.rate =
                bidRecord.FreightTM__Rate__c;
            
            row.transitTime =
                bidRecord.Transit_Time__c;
            
            row.submittedDate =
                bidRecord.CreatedDate;
            
            bidRows.add(row);
        }
        
        MyBidsResponse response =
            new MyBidsResponse();
        
        response.carrier =
            createCarrierSession(carrier);
        
        response.bids =
            bidRows;
        
        response.submittedBidCount =
            bidRows.size();
        
        return response;
    }
    
    @AuraEnabled
    public static AssignedLoadsResponse getAssignedLoads(
        Id carrierId,
        String carrierName,
        String mcNumber
    ) {
        FreightTM__Carrier__c carrier =
            validateCarrierSession(
                carrierId,
                carrierName,
                mcNumber
            );
        
        List<FreightTM__Load__c> loadRecords = [
            SELECT
            Id,
            Name,
            FreightTM__Status__c,
            FreightTM__Trailer__c,
            
            FreightTM__Pickup_Address__c,
            FreightTM__Pickup_City__c,
            FreightTM__Pickup_State__c,
            FreightTM__Pickup_Zip_Code__c,
            FreightTM__Pickup_Date__c,
            
            FreightTM__Weight__c,
            FreightTM__Rate_to_Carrier__c
            FROM FreightTM__Load__c
            WHERE FreightTM__Carrier_Obj__c = :carrier.Id
            AND (
                FreightTM__Status__c = NULL
                OR FreightTM__Status__c != 'Delivered'
            )
            ORDER BY
            FreightTM__Pickup_Date__c ASC NULLS LAST,
            CreatedDate DESC
            LIMIT 500
        ];
        
        List<AssignedLoadRow> assignedLoads =
            new List<AssignedLoadRow>();
        
        for (
            FreightTM__Load__c loadRecord :
            loadRecords
        ) {
            AssignedLoadRow row =
                new AssignedLoadRow();
            
            row.loadId =
                loadRecord.Id;
            
            row.loadName =
                loadRecord.Name;
            
            row.status =
                String.isBlank(
                    loadRecord.FreightTM__Status__c
                )
                ? 'Open'
                : loadRecord.FreightTM__Status__c;
            
            row.trailerType =
                loadRecord.FreightTM__Trailer__c;
            
            row.pickupAddress =
                buildAddress(
                    loadRecord.FreightTM__Pickup_Address__c,
                    loadRecord.FreightTM__Pickup_City__c,
                    loadRecord.FreightTM__Pickup_State__c,
                    loadRecord.FreightTM__Pickup_Zip_Code__c
                );
            
            row.pickupDate =
                loadRecord.FreightTM__Pickup_Date__c;
            
            row.weight =
                loadRecord.FreightTM__Weight__c;
            
            row.rate =
                loadRecord.FreightTM__Rate_to_Carrier__c;
            
            assignedLoads.add(row);
        }
        
        AssignedLoadsResponse response =
            new AssignedLoadsResponse();
        
        response.carrier =
            createCarrierSession(
                carrier
            );
        
        response.loads =
            assignedLoads;
        
        response.assignedLoadCount =
            assignedLoads.size();
        
        return response;
    }

    @AuraEnabled
    public static BidResponse createBid(
        Id carrierId,
        Id loadId,
        Decimal rate,
        Datetime transitionDate,
        String transitTime
    ) {
        validateBidRequest(
            carrierId,
            loadId,
            rate,
            transitionDate,
            transitTime
        );
        
        /*
* Validate that the carrier is still authorized before publishing.
*/
        List<FreightTM__Carrier__c> eligibleCarriers = [
            SELECT
            Id,
            Ready_for_Loads__c,
            Load_Board_Active__c
            FROM FreightTM__Carrier__c
            WHERE Id = :carrierId
            AND Ready_for_Loads__c = TRUE
            AND Load_Board_Active__c = TRUE
            LIMIT 1
        ];
        
        if (eligibleCarriers.isEmpty()) {
            throw new AuraHandledException(
                'This carrier is no longer approved to submit rates.'
            );
        }
        
        /*
* Validate the current state before accepting the request.
* The platform-event subscriber validates it again.
*/
        List<FreightTM__Load__c> eligibleLoads = [
            SELECT
            Id,
            FreightTM__Status__c,
            FreightTM__Carrier_Obj__c,
            FreightTM__Load_Canceled__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            AND FreightTM__Carrier_Obj__c = NULL
            AND FreightTM__Load_Canceled__c = FALSE
            AND (
                FreightTM__Status__c = NULL
                OR FreightTM__Status__c = 'Open'
            )
            LIMIT 1
        ];
        
        if (eligibleLoads.isEmpty()) {
            throw new AuraHandledException(
                'This load is no longer open or is already assigned.'
            );
        }
        
        /*
* Reject a duplicate that already exists before publishing.
* The subscriber performs this validation again.
*/
        Integer existingBidCount = [
            SELECT COUNT()
            FROM FreightTM__Bid__c
            WHERE FreightTM__Carrier__c = :carrierId
            AND FreightTM__Load__c = :loadId
        ];
        
        if (existingBidCount > 0) {
            throw new AuraHandledException(
                'A bid from this carrier already exists for this load.'
            );
        }
        
        String requestId = generateRequestId();
        
        Load_Board_Bid_Request__e eventMessage =
            new Load_Board_Bid_Request__e(
                Request_Id__c = requestId,
                Carrier_Id__c = String.valueOf(carrierId),
                Load_Id__c = String.valueOf(loadId),
                Rate__c = rate,
                Transition_Date__c = transitionDate,
                Transit_Time__c = transitTime,
                Requested_At__c = System.now()
            );
        
        Database.SaveResult publishResult =
            EventBus.publish(eventMessage);
        
        if (!publishResult.isSuccess()) {
            String publishError =
                'The bid request could not be submitted.';
            
            if (
                publishResult.getErrors() != null &&
                !publishResult.getErrors().isEmpty()
            ) {
                Database.Error firstError =
                    publishResult.getErrors()[0];
                
                publishError +=
                    ' ' +
                    firstError.getStatusCode() +
                    ': ' +
                    firstError.getMessage();
            }
            
            throw new AuraHandledException(publishError);
        }
        
        BidResponse response = new BidResponse();
        response.bidId = null;
        response.requestId = requestId;
        response.message =
            'Your bid request was received and will be processed shortly.';
        
        return response;
    }
    
    private static String generateRequestId() {
        String seed =
            String.valueOf(System.now().getTime()) +
            ':' +
            String.valueOf(Crypto.getRandomLong());
        
        Blob digest = Crypto.generateDigest(
            'SHA-256',
            Blob.valueOf(seed)
        );
        
        String hexadecimalValue =
            EncodingUtil.convertToHex(digest);
        
        return hexadecimalValue.substring(0, 36);
    }

    private static FreightTM__Carrier__c validateCarrierSession(
        Id carrierId,
        String carrierName,
        String mcNumber
    ) {
        if (
            carrierId == null ||
            String.isBlank(carrierName) ||
            String.isBlank(mcNumber)
        ) {
            throw new AuraHandledException(
                'Your load board session is invalid. Please sign in again.'
            );
        }

        List<FreightTM__Carrier__c> carriers = [
            SELECT
                Id,
                Name,
                FreightTM__MC_MX_FF_Number__c,
                Ready_for_Loads__c,
                Load_Board_Active__c
            FROM FreightTM__Carrier__c
            WHERE Id = :carrierId
                AND Name = :carrierName
                AND FreightTM__MC_MX_FF_Number__c = :mcNumber
                AND Ready_for_Loads__c = TRUE
                AND Load_Board_Active__c = TRUE
            LIMIT 1
        ];

        if (carriers.isEmpty()) {
            throw new AuraHandledException(
                'Your carrier session is no longer valid. Please sign in again.'
            );
        }

        return carriers[0];
    }

    private static List<LoadRow> queryAvailableLoads(
        Id carrierId
    ) {
        if (carrierId == null) {
            throw new AuraHandledException(
                'Carrier information is required.'
            );
        }
        List<FreightTM__Load__c> loadRecords = [
            SELECT Id,Name,
                FreightTM__Status__c,
                FreightTM__Trailer__c,

                FreightTM__Pickup_Date__c,
                FreightTM__Pickup_Address__c,
                FreightTM__Pickup_City__c,
                FreightTM__Pickup_State__c,
                FreightTM__Pickup_Zip_Code__c,

                FreightTM__Delivery_Date__c,
                FreightTM__Delivery_Address__c,
                FreightTM__Delivery_City__c,
                FreightTM__Delivery_State__c,
                FreightTM__Delivery_Zip_Code__c,

                FreightTM__Remarks__c,
                FreightTM__Number_of_Pallets__c,
                FreightTM__Weight__c,
                FreightTM__Length__c,
                FreightTM__Width__c,
                FreightTM__Height__c,
                FreightTM__Total_Cargo_Volume__c,
                FreightTM__Rate__c,

                FreightTM__Carrier_Obj__c,
                FreightTM__Load_Canceled__c
            FROM FreightTM__Load__c
            WHERE FreightTM__Carrier_Obj__c = NULL
            AND FreightTM__Load_Canceled__c = FALSE
            AND (
                FreightTM__Status__c = NULL
                OR FreightTM__Status__c = 'Open'
            )
            AND Id NOT IN (
                SELECT FreightTM__Load__c
                FROM FreightTM__Bid__c
                WHERE FreightTM__Carrier__c =
                :carrierId
            )
            ORDER BY FreightTM__Pickup_Date__c ASC NULLS LAST, CreatedDate ASC
            LIMIT :MAX_LOAD_RESULTS
        ];

        List<LoadRow> rows = new List<LoadRow>();

        for (FreightTM__Load__c loadRecord : loadRecords) {
            rows.add(createLoadRow(loadRecord));
        }

        return rows;
    }

    private static LoadRow createLoadRow(FreightTM__Load__c loadRecord) {
        LoadRow row = new LoadRow();

        row.loadId = loadRecord.Id;
        row.loadName = loadRecord.Name;
        row.status = String.isBlank(loadRecord.FreightTM__Status__c)
            ? 'Open'
            : loadRecord.FreightTM__Status__c;

        row.trailerType = loadRecord.FreightTM__Trailer__c;
        row.loadRate = loadRecord.FreightTM__Rate__c;

        row.pickupDate = loadRecord.FreightTM__Pickup_Date__c;
        row.pickupStreet = loadRecord.FreightTM__Pickup_Address__c;
        row.pickupCity = loadRecord.FreightTM__Pickup_City__c;
        row.pickupState = loadRecord.FreightTM__Pickup_State__c;
        row.pickupZip = loadRecord.FreightTM__Pickup_Zip_Code__c;
        row.pickupAddress = buildAddress(
            row.pickupStreet,
            row.pickupCity,
            row.pickupState,
            row.pickupZip
        );

        row.deliveryDate = loadRecord.FreightTM__Delivery_Date__c;
        row.deliveryStreet = loadRecord.FreightTM__Delivery_Address__c;
        row.deliveryCity = loadRecord.FreightTM__Delivery_City__c;
        row.deliveryState = loadRecord.FreightTM__Delivery_State__c;
        row.deliveryZip = loadRecord.FreightTM__Delivery_Zip_Code__c;
        row.deliveryAddress = buildAddress(
            row.deliveryStreet,
            row.deliveryCity,
            row.deliveryState,
            row.deliveryZip
        );

        row.remarks = loadRecord.FreightTM__Remarks__c;
        row.numberOfPallets =
            loadRecord.FreightTM__Number_of_Pallets__c;
        row.weight = loadRecord.FreightTM__Weight__c;
        row.length = loadRecord.FreightTM__Length__c;
        row.width = loadRecord.FreightTM__Width__c;
        row.height = loadRecord.FreightTM__Height__c;
        row.totalCargoVolume =
            loadRecord.FreightTM__Total_Cargo_Volume__c;

        row.lane =
            safeText(row.pickupCity) +
            stateSeparator(row.pickupState) +
            ' → ' +
            safeText(row.deliveryCity) +
            stateSeparator(row.deliveryState);

        row.searchText = String.join(
            new List<String>{
                safeText(row.loadName),
                safeText(row.pickupCity),
                safeText(row.pickupState),
                firstThreeCharacters(row.pickupZip),
                safeText(row.trailerType)
            },
            ' '
        ).toLowerCase();

        return row;
    }

    private static CarrierSession createCarrierSession(
        FreightTM__Carrier__c carrier
    ) {
        CarrierSession session = new CarrierSession();
        session.carrierId = carrier.Id;
        session.carrierName = carrier.Name;
        session.mcNumber = carrier.FreightTM__MC_MX_FF_Number__c;
        return session;
    }

    private static void validateLoginRequest(
        String carrierName,
        String mcNumber
    ) {
        if (
            String.isBlank(carrierName) ||
            String.isBlank(mcNumber)
        ) {
            throw new AuraHandledException(
                'Enter both the carrier name and MC number.'
            );
        }
        
        if (
            carrierName.length() > MAX_LOGIN_ATTEMPT_LENGTH ||
            mcNumber.length() > MAX_LOGIN_ATTEMPT_LENGTH
        ) {
            throw new AuraHandledException(
                'The carrier information is too long.'
            );
        }
    }

    private static void validateBidRequest(
        Id carrierId,
        Id loadId,
        Decimal rate,
        Datetime transitionDate,
        String transitTime
    ) {
        if (
            carrierId == null ||
            loadId == null
        ) {
            throw new AuraHandledException(
                'Carrier and load information are required.'
            );
        }
        
        if (rate == null || rate <= 0) {
            throw new AuraHandledException(
                'Enter a rate greater than zero.'
            );
        }
        
        if (transitionDate == null) {
            throw new AuraHandledException(
                'Enter a transition date and time.'
            );
        }
        
        if (String.isBlank(transitTime)) {
            throw new AuraHandledException(
                'Enter the transit time.'
            );
        }
        
        String normalizedTransitTime =
            transitTime.trim();
        
        if (!normalizedTransitTime.isNumeric()) {
            throw new AuraHandledException(
                'Transit time must contain numbers only.'
            );
        }
        
        Integer transitTimeValue;
        
        try {
            transitTimeValue =
                Integer.valueOf(normalizedTransitTime);
        } catch (Exception errorValue) {
            throw new AuraHandledException(
                'Enter a valid transit time.'
            );
        }
        
        if (transitTimeValue <= 0) {
            throw new AuraHandledException(
                'Transit time must be greater than zero.'
            );
        }
    }

        

    private static String buildAddress(
        String street,
        String city,
        String state,
        String zipCode
    ) {
        List<String> addressParts = new List<String>();

        if (!String.isBlank(street)) {
            addressParts.add(street.trim());
        }

        String cityStateZip = '';

        if (!String.isBlank(city)) {
            cityStateZip = city.trim();
        }

        if (!String.isBlank(state)) {
            cityStateZip +=
                String.isBlank(cityStateZip)
                    ? state.trim()
                    : ', ' + state.trim();
        }

        if (!String.isBlank(zipCode)) {
            cityStateZip +=
                String.isBlank(cityStateZip)
                    ? zipCode.trim()
                    : ' ' + zipCode.trim();
        }

        if (!String.isBlank(cityStateZip)) {
            addressParts.add(cityStateZip);
        }

        return addressParts.isEmpty()
            ? 'Not specified'
            : String.join(addressParts, ', ');
    }

    private static String safeText(String value) {
        return String.isBlank(value) ? '' : value.trim();
    }

    private static String stateSeparator(String stateValue) {
        return String.isBlank(stateValue)
            ? ''
            : ', ' + stateValue.trim();
    }

    private static String firstThreeCharacters(String value) {
        if (String.isBlank(value)) {
            return '';
        }

        String trimmedValue = value.trim();
        return trimmedValue.length() <= 3
            ? trimmedValue
            : trimmedValue.substring(0, 3);
    }
    
    private static Integer countCarrierBids(
        Id carrierId
    ) {
        if (carrierId == null) {
            return 0;
        }
        
        return [
            SELECT COUNT()
            FROM FreightTM__Bid__c
            WHERE FreightTM__Carrier__c =
            :carrierId
        ];
    }
    
    
}