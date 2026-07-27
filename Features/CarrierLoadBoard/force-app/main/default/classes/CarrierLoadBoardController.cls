public without sharing class CarrierLoadBoardController {

    private static final String OPEN_STATUS = 'Open';

    public class BidMatch {
        @AuraEnabled public Id bidId;
        @AuraEnabled public String bidName;

        @AuraEnabled public Id carrierId;
        @AuraEnabled public String carrierName;
        @AuraEnabled public String initials;

        @AuraEnabled public String contactName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String rating;

        @AuraEnabled public Decimal rate;
        @AuraEnabled public Datetime transitionDate;
        @AuraEnabled public String transitTime;
        @AuraEnabled public Datetime submittedDate;
    }

    public class PublicLoadRow {
        @AuraEnabled public Id loadId;
        @AuraEnabled public String loadNumber;

        @AuraEnabled public String pickupStreet;
        @AuraEnabled public String pickupCity;
        @AuraEnabled public String pickupState;
        @AuraEnabled public String pickupZip;
        @AuraEnabled public Date pickupDate;

        @AuraEnabled public String deliveryStreet;
        @AuraEnabled public String deliveryCity;
        @AuraEnabled public String deliveryState;
        @AuraEnabled public String deliveryZip;
        @AuraEnabled public Date deliveryDate;

        @AuraEnabled public String origin;
        @AuraEnabled public String destination;

        @AuraEnabled public String trailerType;
        @AuraEnabled public String requiredTrailer;
        @AuraEnabled public String requirements;
        @AuraEnabled public String commodity;

        @AuraEnabled public Decimal weight;
        @AuraEnabled public Decimal palletCount;
        @AuraEnabled public Decimal distance;
        @AuraEnabled public Decimal totalMiles;

        @AuraEnabled public Boolean hazmat;
        @AuraEnabled public Decimal temperature;
        @AuraEnabled public String size;
        @AuraEnabled public String priority;
        @AuraEnabled public String loadStatus;
        @AuraEnabled public Decimal totalRateToCarrier;

        @AuraEnabled public List<BidMatch> bids;
    }

    public class LoadBoardResult {
        @AuraEnabled public Integer openOpportunityCount;
        @AuraEnabled public Integer approvedCarrierCount;
        @AuraEnabled public String averageResponseDisplay;
        @AuraEnabled public List<PublicLoadRow> loads;
    }

    public class AssignBidResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id loadId;
        @AuraEnabled public Id bidId;
        @AuraEnabled public Id carrierId;
    }

    /*
     * On a Load record page, currentLoadId contains the current record.
     * On a tab or app page, currentLoadId is null and all eligible Loads
     * are returned.
     */
    @AuraEnabled
    public static LoadBoardResult getLoadBoardData(
        Id currentLoadId
    ) {
        List<FreightTM__Load__c> loadRecords =
            queryAvailableLoads(currentLoadId);

        return buildLoadBoardResult(loadRecords);
    }

    @AuraEnabled
    public static PublicLoadRow getLoadDetails(
        Id loadId
    ) {
        if (loadId == null) {
            throw publicException(
                'A load was not selected.'
            );
        }

        List<FreightTM__Load__c> loadRecords =
            queryAvailableLoads(loadId);

        if (loadRecords.isEmpty()) {
            throw publicException(
                'This load is no longer available or has no bids.'
            );
        }

        Map<Id, List<BidMatch>> bidsByLoadId =
            queryBidsByLoadId(
                new Set<Id>{ loadId }
            );

        return mapPublicLoad(
            loadRecords[0],
            bidsByLoadId
        );
    }

    /*
     * Assigns the Bid carrier to the Load and queues the RateCon email.
     */
    @AuraEnabled
    public static AssignBidResult assignBid(
        Id loadId,
        Id bidId
    ) {
        if (loadId == null || bidId == null) {
            throw publicException(
                'A load and bid must be selected.'
            );
        }

        List<FreightTM__Bid__c> bids = [
            SELECT
            Id,
            Name,
            FreightTM__Load__c,
            FreightTM__Carrier__c,
            FreightTM__Rate__c,
            FreightTM__Carrier__r.Name,
            FreightTM__Carrier__r.FreightTM__Email__c,
            FreightTM__Carrier__r.Ready_for_Loads__c,
            FreightTM__Carrier__r.Load_Board_Active__c
            FROM FreightTM__Bid__c
            WHERE Id = :bidId
            AND FreightTM__Load__c = :loadId
            LIMIT 1
        ];

        if (bids.isEmpty()) {
            throw publicException(
                'The selected bid does not belong to this load.'
            );
        }

        FreightTM__Bid__c selectedBid = bids[0];

        if (selectedBid.FreightTM__Carrier__c == null) {
            throw publicException(
                'The selected bid does not have a carrier.'
            );
        }

        if (
            selectedBid.FreightTM__Carrier__r == null ||
            selectedBid.FreightTM__Carrier__r.Ready_for_Loads__c != true ||
            selectedBid.FreightTM__Carrier__r.Load_Board_Active__c != true
        ) {
            throw publicException(
                'The selected carrier is no longer approved for loads.'
            );
        }

        if (
            String.isBlank(
                selectedBid.FreightTM__Carrier__r.FreightTM__Email__c
            )
        ) {
            throw publicException(
                'The selected carrier does not have an email address.'
            );
        }

        List<FreightTM__Load__c> loads = [
            SELECT
            Id,
            Name,
            FreightTM__Status__c,
            FreightTM__Load_Canceled__c,
            FreightTM__Rate_to_Carrier__c,
            FreightTM__Carrier_Obj__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
            FOR UPDATE
        ];

        if (loads.isEmpty()) {
            throw publicException(
                'The selected load could not be found.'
            );
        }

        FreightTM__Load__c loadRecord = loads[0];

        if (loadRecord.FreightTM__Load_Canceled__c == true) {
            throw publicException(
                'The selected load has been canceled.'
            );
        }

        if (loadRecord.FreightTM__Carrier_Obj__c != null) {
            throw publicException(
                'The selected load already has a carrier assigned.'
            );
        }

        if (
            !String.isBlank(loadRecord.FreightTM__Status__c) &&
            loadRecord.FreightTM__Status__c != OPEN_STATUS
        ) {
            throw publicException(
                'The selected load is no longer open.'
            );
        }

        /*
* Assign the carrier selected through the Bid.
*
* Do not assign FreightTM__Total_Rate_to_Carrier__c because
* Salesforce reports that field as read-only.
*/
        loadRecord.FreightTM__Carrier_Obj__c =
            selectedBid.FreightTM__Carrier__c;
        loadRecord.FreightTM__Rate_to_Carrier__c =
            selectedBid.FreightTM__Rate__c;
        loadRecord.FreightTM__Status__c =
            'Assigned';

        try {
            update loadRecord;
        } catch (DmlException errorValue) {
            String detail =
                errorValue.getNumDml() > 0
                ? errorValue.getDmlMessage(0)
                : errorValue.getMessage();

            throw publicException(
                'The carrier could not be assigned: ' +
                detail
            );
        }

        try {
            System.enqueueJob(
                new CarrierLoadBoardRateConJob(
                    loadRecord.Id,
                    selectedBid.Id
                )
            );
        } catch (Exception errorValue) {
            throw publicException(
                'The carrier was assigned, but the Rate Confirmation ' +
                'email could not be queued: ' +
                errorValue.getMessage()
            );
        }

        AssignBidResult result =
            new AssignBidResult();

        result.success = true;
        result.loadId = loadRecord.Id;
        result.bidId = selectedBid.Id;
        result.carrierId =
            selectedBid.FreightTM__Carrier__c;

        result.message =
            selectedBid.FreightTM__Carrier__r.Name +
            ' was assigned to ' +
            loadRecord.Name +
            '. The Rate Confirmation email has been queued.';

        return result;
    }

    private static List<FreightTM__Load__c>
        queryAvailableLoads(
            Id currentLoadId
        ) {

        if (currentLoadId != null) {
            return [
                SELECT
                    Id,
                    Name,

                    FreightTM__Pickup_Address__c,
                    FreightTM__Pickup_City__c,
                    FreightTM__Pickup_State__c,
                    FreightTM__Pickup_Zip_Code__c,
                    FreightTM__Pickup_Date__c,

                    FreightTM__Delivery_Address__c,
                    FreightTM__Delivery_City__c,
                    FreightTM__Delivery_State__c,
                    FreightTM__Delivery_Zip_Code__c,
                    FreightTM__Delivery_Date__c,

                    FreightTM__Trailer__c,
                    FreightTM__Required_Trailer__c,
                    FreightTM__Requirements__c,
                    FreightTM__Commodity__c,

                    FreightTM__Weight__c,
                    FreightTM__Number_of_Pallets__c,
                    FreightTM__Distance__c,
                    FreightTM__Total_Miles__c,

                    FreightTM__Hazmat__c,
                    FreightTM__Temperature__c,
                    FreightTM__Size__c,
                    FreightTM__Priority__c,
                    FreightTM__Status__c,
                    FreightTM__Rate_to_Carrier__c,
                    FreightTM__Total_Rate_to_Carrier__c
                FROM FreightTM__Load__c
                WHERE Id = :currentLoadId
                    AND (
                        FreightTM__Status__c = NULL
                        OR FreightTM__Status__c = :OPEN_STATUS
                    )
                    AND FreightTM__Load_Canceled__c = FALSE
                    AND FreightTM__Carrier_Obj__c = NULL
                    AND Id IN (
                        SELECT FreightTM__Load__c
                        FROM FreightTM__Bid__c
                    )
                LIMIT 1
            ];
        }

        return [
            SELECT
                Id,
                Name,

                FreightTM__Pickup_Address__c,
                FreightTM__Pickup_City__c,
                FreightTM__Pickup_State__c,
                FreightTM__Pickup_Zip_Code__c,
                FreightTM__Pickup_Date__c,

                FreightTM__Delivery_Address__c,
                FreightTM__Delivery_City__c,
                FreightTM__Delivery_State__c,
                FreightTM__Delivery_Zip_Code__c,
                FreightTM__Delivery_Date__c,

                FreightTM__Trailer__c,
                FreightTM__Required_Trailer__c,
                FreightTM__Requirements__c,
                FreightTM__Commodity__c,

                FreightTM__Weight__c,
                FreightTM__Number_of_Pallets__c,
                FreightTM__Distance__c,
                FreightTM__Total_Miles__c,

                FreightTM__Hazmat__c,
                FreightTM__Temperature__c,
                FreightTM__Size__c,
                FreightTM__Priority__c,
                FreightTM__Status__c,
                FreightTM__Rate_to_Carrier__c,
                FreightTM__Total_Rate_to_Carrier__c
            FROM FreightTM__Load__c
            WHERE (
                FreightTM__Status__c = NULL
                OR FreightTM__Status__c = :OPEN_STATUS
            )
                AND FreightTM__Load_Canceled__c = FALSE
                AND FreightTM__Carrier_Obj__c = NULL
                AND Id IN (
                    SELECT FreightTM__Load__c
                    FROM FreightTM__Bid__c
                )
            ORDER BY
                FreightTM__Pickup_Date__c ASC NULLS LAST,
                CreatedDate DESC
            LIMIT 500
        ];
    }

    private static LoadBoardResult buildLoadBoardResult(
        List<FreightTM__Load__c> loadRecords
    ) {
        Set<Id> loadIds = new Set<Id>();

        for (
            FreightTM__Load__c loadRecord :
            loadRecords
        ) {
            loadIds.add(loadRecord.Id);
        }

        Map<Id, List<BidMatch>> bidsByLoadId =
            queryBidsByLoadId(loadIds);

        Set<Id> carrierIds = new Set<Id>();

        for (
            List<BidMatch> matches :
            bidsByLoadId.values()
        ) {
            for (BidMatch match : matches) {
                if (match.carrierId != null) {
                    carrierIds.add(match.carrierId);
                }
            }
        }

        LoadBoardResult result =
            new LoadBoardResult();

        result.openOpportunityCount =
            loadRecords.size();

        result.approvedCarrierCount =
            carrierIds.size();

        result.averageResponseDisplay = '—';

        result.loads = new List<PublicLoadRow>();

        for (
            FreightTM__Load__c loadRecord :
            loadRecords
        ) {
            result.loads.add(
                mapPublicLoad(
                    loadRecord,
                    bidsByLoadId
                )
            );
        }

        return result;
    }

    private static Map<Id, List<BidMatch>>
        queryBidsByLoadId(
            Set<Id> loadIds
        ) {

        Map<Id, List<BidMatch>> result =
            new Map<Id, List<BidMatch>>();

        if (loadIds == null || loadIds.isEmpty()) {
            return result;
        }

        List<FreightTM__Bid__c> bidRecords = [
            SELECT
                Id,
                Name,
                FreightTM__Load__c,
                FreightTM__Carrier__c,
                FreightTM__Rate__c,
                CreatedDate,

                FreightTM__Carrier__r.Name,
                FreightTM__Carrier__r.FreightTM__Primary_Contact__c,
                FreightTM__Carrier__r.FreightTM__Email__c,
                FreightTM__Carrier__r.FreightTM__Phone__c,
                FreightTM__Carrier__r.FreightTM__Rating__c,
                FreightTM__Carrier__r.Ready_for_Loads__c,
                FreightTM__Carrier__r.Load_Board_Active__c
            FROM FreightTM__Bid__c
            WHERE FreightTM__Load__c IN :loadIds
                AND FreightTM__Carrier__c != NULL
                AND FreightTM__Carrier__r.Ready_for_Loads__c = TRUE
                AND FreightTM__Carrier__r.Load_Board_Active__c = TRUE
            ORDER BY
                FreightTM__Load__c,
                FreightTM__Rate__c ASC NULLS LAST,
                CreatedDate ASC
        ];

        for (
            FreightTM__Bid__c bidRecord :
            bidRecords
        ) {
            if (
                !result.containsKey(
                    bidRecord.FreightTM__Load__c
                )
            ) {
                result.put(
                    bidRecord.FreightTM__Load__c,
                    new List<BidMatch>()
                );
            }

            BidMatch match = new BidMatch();

            match.bidId = bidRecord.Id;
            match.bidName = bidRecord.Name;

            match.carrierId =
                bidRecord.FreightTM__Carrier__c;

            match.carrierName =
                bidRecord.FreightTM__Carrier__r.Name;

            match.initials =
                makeInitials(match.carrierName);

            match.contactName =
                bidRecord.FreightTM__Carrier__r
                    .FreightTM__Primary_Contact__c;

            match.email =
                bidRecord.FreightTM__Carrier__r
                    .FreightTM__Email__c;

            match.phone =
                bidRecord.FreightTM__Carrier__r
                    .FreightTM__Phone__c;

            match.rating =
                bidRecord.FreightTM__Carrier__r
                    .FreightTM__Rating__c;

            match.rate =
                bidRecord.FreightTM__Rate__c;

            // These optional Bid fields are not installed in every org.
            // Keep the response properties available without querying missing fields.
            match.transitionDate = null;
            match.transitTime = null;

            match.submittedDate =
                bidRecord.CreatedDate;

            result
                .get(bidRecord.FreightTM__Load__c)
                .add(match);
        }

        return result;
    }

    private static PublicLoadRow mapPublicLoad(
        FreightTM__Load__c loadRecord,
        Map<Id, List<BidMatch>> bidsByLoadId
    ) {
        PublicLoadRow row =
            new PublicLoadRow();

        row.loadId = loadRecord.Id;
        row.loadNumber = loadRecord.Name;

        row.pickupStreet =
            loadRecord.FreightTM__Pickup_Address__c;

        row.pickupCity =
            loadRecord.FreightTM__Pickup_City__c;

        row.pickupState =
            loadRecord.FreightTM__Pickup_State__c;

        row.pickupZip =
            loadRecord.FreightTM__Pickup_Zip_Code__c;

        row.pickupDate =
            loadRecord.FreightTM__Pickup_Date__c;

        row.deliveryStreet =
            loadRecord.FreightTM__Delivery_Address__c;

        row.deliveryCity =
            loadRecord.FreightTM__Delivery_City__c;

        row.deliveryState =
            loadRecord.FreightTM__Delivery_State__c;

        row.deliveryZip =
            loadRecord.FreightTM__Delivery_Zip_Code__c;

        row.deliveryDate =
            loadRecord.FreightTM__Delivery_Date__c;

        row.origin =
            joinLocation(
                row.pickupCity,
                row.pickupState
            );

        row.destination =
            joinLocation(
                row.deliveryCity,
                row.deliveryState
            );

        row.trailerType =
            loadRecord.FreightTM__Trailer__c;

        row.requiredTrailer =
            loadRecord.FreightTM__Required_Trailer__c;

        row.requirements =
            loadRecord.FreightTM__Requirements__c;

        row.commodity =
            loadRecord.FreightTM__Commodity__c;

        row.weight =
            loadRecord.FreightTM__Weight__c;

        row.palletCount =
            loadRecord.FreightTM__Number_of_Pallets__c;

        row.distance =
            loadRecord.FreightTM__Distance__c;

        row.totalMiles =
            loadRecord.FreightTM__Total_Miles__c;

        row.hazmat =
            loadRecord.FreightTM__Hazmat__c;

        row.temperature =
            loadRecord.FreightTM__Temperature__c;

        row.size =
            loadRecord.FreightTM__Size__c;

        row.priority =
            loadRecord.FreightTM__Priority__c;

        row.loadStatus =
            String.isBlank(
                loadRecord.FreightTM__Status__c
            )
                ? OPEN_STATUS
                : loadRecord.FreightTM__Status__c;

        row.totalRateToCarrier =
            loadRecord.FreightTM__Total_Rate_to_Carrier__c;

        row.bids =
            bidsByLoadId.containsKey(loadRecord.Id)
                ? bidsByLoadId.get(loadRecord.Id)
                : new List<BidMatch>();

        return row;
    }

    private static String joinLocation(
        String city,
        String stateValue
    ) {
        List<String> values =
            new List<String>();

        if (!String.isBlank(city)) {
            values.add(city.trim());
        }

        if (!String.isBlank(stateValue)) {
            values.add(stateValue.trim());
        }

        return values.isEmpty()
            ? 'Not provided'
            : String.join(values, ', ');
    }

    private static String makeInitials(
        String nameValue
    ) {
        if (String.isBlank(nameValue)) {
            return 'CR';
        }

        List<String> words =
            nameValue.trim().split('\\s+');

        if (words.size() == 1) {
            Integer lengthValue =
                Math.min(2, words[0].length());

            return words[0]
                .substring(0, lengthValue)
                .toUpperCase();
        }

        return (
            words[0].substring(0, 1) +
            words[1].substring(0, 1)
        ).toUpperCase();
    }

    private static AuraHandledException publicException(
        String message
    ) {
        return new AuraHandledException(message);
    }
}