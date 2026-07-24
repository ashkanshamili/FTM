public without sharing class LoadBoardBidRequestHandler {

    public static void handleAfterInsert(
        List<Load_Board_Bid_Request__e> eventMessages
    ) {
        if (eventMessages == null || eventMessages.isEmpty()) {
            return;
        }

        List<RequestData> validRequests =
            parseEvents(eventMessages);

        if (validRequests.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'No valid Load Board Bid Request events were received.'
            );
            return;
        }

        Set<Id> carrierIds = new Set<Id>();
        Set<Id> loadIds = new Set<Id>();

        for (RequestData request : validRequests) {
            carrierIds.add(request.carrierId);
            loadIds.add(request.loadId);
        }

        /*
         * Revalidate Carrier eligibility in the subscriber.
         */
        Map<Id, FreightTM__Carrier__c> eligibleCarriers =
            new Map<Id, FreightTM__Carrier__c>([
                SELECT
                    Id,
                    Name,
                    Ready_for_Loads__c,
                    Load_Board_Active__c
                FROM FreightTM__Carrier__c
                WHERE Id IN :carrierIds
                    AND Ready_for_Loads__c = TRUE
                    AND Load_Board_Active__c = TRUE
            ]);

        /*
         * Revalidate and lock the Loads.
         */
        Map<Id, FreightTM__Load__c> eligibleLoads =
            new Map<Id, FreightTM__Load__c>([
                SELECT
                    Id,
                    Name,
                    FreightTM__Status__c,
                    FreightTM__Carrier_Obj__c,
                    FreightTM__Load_Canceled__c
                FROM FreightTM__Load__c
                WHERE Id IN :loadIds
                    AND FreightTM__Carrier_Obj__c = NULL
                    AND FreightTM__Load_Canceled__c = FALSE
                    AND (
                        FreightTM__Status__c = NULL
                        OR FreightTM__Status__c = 'Open'
                    )
                FOR UPDATE
            ]);

        /*
         * Find existing Carrier/Load Bid combinations.
         */
        Set<String> existingBidKeys =
            queryExistingBidKeys(
                carrierIds,
                loadIds
            );

        /*
         * Also prevent duplicate events in the same trigger batch.
         */
        Set<String> scheduledBidKeys =
            new Set<String>();

        List<FreightTM__Bid__c> bidsToInsert =
            new List<FreightTM__Bid__c>();

        List<RequestData> requestsForInsert =
            new List<RequestData>();

        for (RequestData request : validRequests) {
            if (
                !eligibleCarriers.containsKey(
                    request.carrierId
                )
            ) {
                logSkippedRequest(
                    request,
                    'Carrier is no longer eligible for the load board.'
                );
                continue;
            }

            if (
                !eligibleLoads.containsKey(
                    request.loadId
                )
            ) {
                logSkippedRequest(
                    request,
                    'Load is canceled, assigned, closed, or unavailable.'
                );
                continue;
            }

            String bidKey = buildBidKey(
                request.carrierId,
                request.loadId
            );

            if (
                existingBidKeys.contains(bidKey) ||
                scheduledBidKeys.contains(bidKey)
            ) {
                logSkippedRequest(
                    request,
                    'A Bid already exists for this Carrier and Load.'
                );
                continue;
            }

            FreightTM__Bid__c bid =
                new FreightTM__Bid__c(
                    FreightTM__Carrier__c = request.carrierId,
                    FreightTM__Load__c = request.loadId,
                    FreightTM__Rate__c = request.rate,
                    Transition_Date__c = request.transitionDate,
                    Transit_Time__c = request.transitTime
                );

            bidsToInsert.add(bid);
            requestsForInsert.add(request);
            scheduledBidKeys.add(bidKey);
        }

        if (bidsToInsert.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'No eligible Load Board Bids to insert.'
            );
            return;
        }

        Database.SaveResult[] insertResults =
            Database.insert(
                bidsToInsert,
                false
            );

        for (
            Integer index = 0;
            index < insertResults.size();
            index++
        ) {
            Database.SaveResult saveResult =
                insertResults[index];

            FreightTM__Bid__c bid =
                bidsToInsert[index];

            RequestData request =
                requestsForInsert[index];

            if (saveResult.isSuccess()) {
                System.debug(
                    LoggingLevel.INFO,
                    'Load Board Bid created successfully. ' +
                    'RequestId=' + request.requestId +
                    ', BidId=' + saveResult.getId() +
                    ', CarrierId=' + bid.FreightTM__Carrier__c +
                    ', LoadId=' + bid.FreightTM__Load__c +
                    ', Rate=' + bid.FreightTM__Rate__c
                );

                continue;
            }

            for (
                Database.Error errorValue :
                saveResult.getErrors()
            ) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Load Board Bid creation failed. ' +
                    'RequestId=' + request.requestId +
                    ', CarrierId=' +
                    bid.FreightTM__Carrier__c +
                    ', LoadId=' +
                    bid.FreightTM__Load__c +
                    ', StatusCode=' +
                    errorValue.getStatusCode() +
                    ', Message=' +
                    errorValue.getMessage()
                );
            }
        }
    }

    /*
     * This method is on the top-level class, so it can be static.
     */
    private static List<RequestData> parseEvents(
        List<Load_Board_Bid_Request__e> eventMessages
    ) {
        List<RequestData> validRequests =
            new List<RequestData>();

        Set<String> processedRequestIds =
            new Set<String>();

        for (
            Load_Board_Bid_Request__e eventMessage :
            eventMessages
        ) {
            try {
                RequestData request =
                    createRequestData(eventMessage);

                if (
                    processedRequestIds.contains(
                        request.requestId
                    )
                ) {
                    System.debug(
                        LoggingLevel.WARN,
                        'Duplicate Request ID in the same event batch: ' +
                        request.requestId
                    );
                    continue;
                }

                processedRequestIds.add(
                    request.requestId
                );

                validRequests.add(request);

            } catch (Exception errorValue) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Invalid Load Board Bid Request event. ' +
                    'RequestId=' +
                    eventMessage.Request_Id__c +
                    ', ErrorType=' +
                    errorValue.getTypeName() +
                    ', Message=' +
                    errorValue.getMessage()
                );
            }
        }

        return validRequests;
    }

    /*
     * Event-to-request conversion is kept on the top-level class.
     */
    private static RequestData createRequestData(
        Load_Board_Bid_Request__e eventMessage
    ) {
        if (eventMessage == null) {
            throw new BidRequestException(
                'Event message is required.'
            );
        }
        
        if (
            String.isBlank(
                eventMessage.Request_Id__c
            )
        ) {
            throw new BidRequestException(
                'Request ID is required.'
            );
        }
        
        if (
            String.isBlank(
                eventMessage.Carrier_Id__c
            )
        ) {
            throw new BidRequestException(
                'Carrier ID is required.'
            );
        }
        
        if (
            String.isBlank(
                eventMessage.Load_Id__c
            )
        ) {
            throw new BidRequestException(
                'Load ID is required.'
            );
        }
        
        if (
            eventMessage.Rate__c == null ||
            eventMessage.Rate__c <= 0
        ) {
            throw new BidRequestException(
                'Rate must be greater than zero.'
            );
        }
        
        if (
            eventMessage.Transition_Date__c == null
        ) {
            throw new BidRequestException(
                'Transition Date is required.'
            );
        }
        
        if (
            String.isBlank(
                eventMessage.Transit_Time__c
            )
        ) {
            throw new BidRequestException(
                'Transit Time is required.'
            );
        }
        
        String normalizedTransitTime =
            eventMessage.Transit_Time__c.trim();
        
        if (!normalizedTransitTime.isNumeric()) {
            throw new BidRequestException(
                'Transit Time must contain numbers only.'
            );
        }
        
        Integer transitTimeValue;
        
        try {
            transitTimeValue =
                Integer.valueOf(
                    normalizedTransitTime
                );
        } catch (Exception errorValue) {
            throw new BidRequestException(
                'Transit Time is invalid.'
            );
        }
        
        if (transitTimeValue <= 0) {
            throw new BidRequestException(
                'Transit Time must be greater than zero.'
            );
        }
        
        RequestData request =
            new RequestData();
        
        request.requestId =
            eventMessage.Request_Id__c.trim();
        
        try {
            request.carrierId =
                Id.valueOf(
                    eventMessage.Carrier_Id__c.trim()
                );
            
            request.loadId =
                Id.valueOf(
                    eventMessage.Load_Id__c.trim()
                );
            
        } catch (Exception errorValue) {
            throw new BidRequestException(
                'Carrier ID or Load ID is invalid.'
            );
        }
        
        request.rate =
            eventMessage.Rate__c;
        
        request.transitionDate =
            eventMessage.Transition_Date__c;
        
        request.requestedAt =
            eventMessage.Requested_At__c;
        
        request.transitTime =
            normalizedTransitTime;
        
        return request;
    }
    
    private static Set<String> queryExistingBidKeys(
        Set<Id> carrierIds,
        Set<Id> loadIds
    ) {
        Set<String> bidKeys =
            new Set<String>();

        if (
            carrierIds.isEmpty() ||
            loadIds.isEmpty()
        ) {
            return bidKeys;
        }

        for (FreightTM__Bid__c existingBid : [
            SELECT
                FreightTM__Carrier__c,
                FreightTM__Load__c
            FROM FreightTM__Bid__c
            WHERE FreightTM__Carrier__c IN :carrierIds
                AND FreightTM__Load__c IN :loadIds
        ]) {
            bidKeys.add(
                buildBidKey(
                    existingBid.FreightTM__Carrier__c,
                    existingBid.FreightTM__Load__c
                )
            );
        }

        return bidKeys;
    }

    private static String buildBidKey(
        Id carrierId,
        Id loadId
    ) {
        return String.valueOf(carrierId) +
            '|' +
            String.valueOf(loadId);
    }

    private static void logSkippedRequest(
        RequestData request,
        String reason
    ) {
        System.debug(
            LoggingLevel.WARN,
            'Load Board Bid Request skipped. ' +
            'RequestId=' + request.requestId +
            ', CarrierId=' + request.carrierId +
            ', LoadId=' + request.loadId +
            ', Reason=' + reason
        );
    }

    /*
     * This nested class only stores values.
     * It contains no static methods.
     */
    private class RequestData {
        String requestId;
        Id carrierId;
        Id loadId;
        Decimal rate;
        Datetime transitionDate;
        Datetime requestedAt;
        String transitTime;
    }

    private class BidRequestException
        extends Exception {
    }
}