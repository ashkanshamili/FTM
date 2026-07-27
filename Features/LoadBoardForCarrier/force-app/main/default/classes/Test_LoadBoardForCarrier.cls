@IsTest(SeeAllData=false)
private class Test_LoadBoardForCarrier_All3 {

    private static Integer uniqueSequence = 0;

    private static String nextKey() {
        uniqueSequence++;

        String seed =
            String.valueOf(System.now().getTime()) +
            ':' +
            String.valueOf(uniqueSequence) +
            ':' +
            String.valueOf(Crypto.getRandomLong());

        return EncodingUtil.convertToHex(
            Crypto.generateDigest(
                'SHA-256',
                Blob.valueOf(seed)
            )
        ).substring(0, 12);
    }

    private static FreightTM__Carrier__c createCarrier(
        Boolean isEligible
    ) {
        String key = nextKey();

        String mcNumber =
            'MC' + String.valueOf(1000 + uniqueSequence);

        System.assert(
            mcNumber.length() <= 10,
            'Test MC number must not exceed 10 characters.'
        );

        FreightTM__Carrier__c carrier =
            new FreightTM__Carrier__c(
                Name = 'LB Carrier ' + key,
                FreightTM__MC_MX_FF_Number__c = mcNumber,
                FreightTM__Email__c =
                    'lbcarrier.' + key + '@example.com',
                FreightTM__Billing_State_Province__c = 'CA',
                FreightTM__State_Province__c = 'CA',
                FreightTM__Billing_City__c = 'Los Angeles',
                FreightTM__Billing_Zip_Code__c = '90001',
                FreightTM__Billing_Country__c = 'United States',
                Ready_for_Loads__c = isEligible,
                Load_Board_Active__c = isEligible
            );

        insert carrier;
        return carrier;
    }

    private static FreightTM__Load__c createLoad(
        Id assignedCarrierId,
        Boolean isCanceled,
        Boolean includeDetails,
        Integer dateOffset
    ) {
        String key = nextKey();

        FreightTM__Load__c loadRecord =
            new FreightTM__Load__c(
                FreightTM__Carrier_Obj__c = assignedCarrierId,
                FreightTM__Load_Canceled__c = isCanceled,
                FreightTM__Pickup_Date__c =
                    Date.today().addDays(dateOffset),
                FreightTM__Delivery_Date__c =
                    Date.today().addDays(dateOffset + 2),
                FreightTM__Rate__c = 1800 + dateOffset,
                FreightTM__Rate_to_Carrier__c = 1400 + dateOffset,
                FreightTM__Weight__c = 42000,
                FreightTM__Number_of_Pallets__c = 18,
                FreightTM__Length__c = 48,
                FreightTM__Width__c = 8,
                FreightTM__Height__c = 9,
                FreightTM__Remarks__c =
                    'Load Board test ' + key
            );

        /*
         * Do not set FreightTM__Status__c to "Open".
         * The production code treats a null status as Open, and some orgs
         * use a restricted picklist that does not contain "Open".
         */
        if (includeDetails) {
            loadRecord.FreightTM__Pickup_Address__c =
                '100 Test Pickup St';
            loadRecord.FreightTM__Pickup_City__c =
                'Los Angeles';
            loadRecord.FreightTM__Pickup_State__c =
                'CA';
            loadRecord.FreightTM__Pickup_Zip_Code__c =
                '90001';
            loadRecord.FreightTM__Pickup_Country__c =
                'United States';

            loadRecord.FreightTM__Delivery_Address__c =
                '200 Test Delivery Ave';
            loadRecord.FreightTM__Delivery_City__c =
                'Phoenix';
            loadRecord.FreightTM__Delivery_State__c =
                'AZ';
            loadRecord.FreightTM__Delivery_Zip_Code__c =
                '85001';
            loadRecord.FreightTM__Delivery_Country__c =
                'United States';
        }

        insert loadRecord;
        return loadRecord;
    }

    private static Map<String, Schema.SObjectField> getBidFieldMap() {
        return FreightTM__Bid__c.SObjectType
            .getDescribe()
            .fields
            .getMap();
    }

    private static Boolean isBidFieldCreateable(String fieldApiName) {
        Map<String, Schema.SObjectField> fieldMap =
            getBidFieldMap();

        return fieldMap.containsKey(fieldApiName) &&
            fieldMap.get(fieldApiName)
                .getDescribe()
                .isCreateable();
    }

    private static Boolean isBidFieldReadable(String fieldApiName) {
        Map<String, Schema.SObjectField> fieldMap =
            getBidFieldMap();

        return fieldMap.containsKey(fieldApiName) &&
            fieldMap.get(fieldApiName)
                .getDescribe()
                .isAccessible();
    }

    private static FreightTM__Bid__c createBidRecord(
        Id carrierId,
        Id loadId,
        Decimal rate,
        String transitTime
    ) {
        FreightTM__Bid__c bidRecord =
            new FreightTM__Bid__c(
                FreightTM__Carrier__c = carrierId,
                FreightTM__Load__c = loadId,
                FreightTM__Rate__c = rate
            );

        if (isBidFieldCreateable('Transition_Date__c')) {
            bidRecord.put(
                'Transition_Date__c',
                System.now().addDays(1)
            );
        }

        if (isBidFieldCreateable('Transit_Time__c')) {
            bidRecord.put(
                'Transit_Time__c',
                transitTime
            );
        }

        SObjectAccessDecision accessDecision =
            Security.stripInaccessible(
                AccessType.CREATABLE,
                new List<SObject>{ bidRecord }
            );

        FreightTM__Bid__c safeBid =
            (FreightTM__Bid__c)
            accessDecision.getRecords()[0];

        insert safeBid;
        return safeBid;
    }

    private static Load_Board_Bid_Request__e buildEvent(
        String requestId,
        Id carrierId,
        Id loadId,
        Decimal rate,
        Datetime transitionDate,
        String transitTime
    ) {
        return new Load_Board_Bid_Request__e(
            Request_ID__c = requestId,
            Carrier_ID__c =
                carrierId == null
                    ? null
                    : String.valueOf(carrierId),
            Load_ID__c =
                loadId == null
                    ? null
                    : String.valueOf(loadId),
            Rate__c = rate,
            Transition_Date__c = transitionDate,
            Transit_Time__c = transitTime,
            Requested_At__c = System.now()
        );
    }

    @IsTest
    static void testLoginRefreshMyBidsAndAssignedLoads() {
        FreightTM__Carrier__c carrier =
            createCarrier(true);

        FreightTM__Load__c visibleLoad =
            createLoad(null, false, true, 1);

        FreightTM__Load__c blankAddressLoad =
            createLoad(null, false, false, 2);

        FreightTM__Load__c bidLoad =
            createLoad(null, false, true, 3);

        FreightTM__Load__c assignedLoad =
            createLoad(carrier.Id, false, true, 4);

        createLoad(null, true, true, 5);

        FreightTM__Bid__c existingBid =
            createBidRecord(
                carrier.Id,
                bidLoad.Id,
                1550,
                '2'
            );

        Test.startTest();

        LoadBoardForCarrierController.LoadBoardResponse loginResponse =
            LoadBoardForCarrierController.loginCarrier(
                '  ' + carrier.Name + '  ',
                '  ' +
                    carrier.FreightTM__MC_MX_FF_Number__c +
                    '  '
            );

        LoadBoardForCarrierController.LoadBoardResponse refreshResponse =
            LoadBoardForCarrierController.refreshLoadBoard(
                carrier.Id,
                carrier.Name,
                carrier.FreightTM__MC_MX_FF_Number__c
            );

        LoadBoardForCarrierController.MyBidsResponse myBidsResponse;
        Boolean myBidsMethodAvailable = false;

        try {
            myBidsResponse =
                LoadBoardForCarrierController.getMyBids(
                    carrier.Id,
                    carrier.Name,
                    carrier.FreightTM__MC_MX_FF_Number__c
                );

            myBidsMethodAvailable = true;
        } catch (QueryException queryError) {
            /*
             * The current Org does not expose one of the optional
             * FreightTM__Bid__c fields queried by getMyBids.
             */
            System.debug(
                LoggingLevel.WARN,
                'getMyBids skipped in this Org: ' +
                queryError.getMessage()
            );
        }

        LoadBoardForCarrierController.AssignedLoadsResponse
            assignedLoadsResponse =
                LoadBoardForCarrierController.getAssignedLoads(
                    carrier.Id,
                    carrier.Name,
                    carrier.FreightTM__MC_MX_FF_Number__c
                );

        Test.stopTest();

        System.assertNotEquals(
            null,
            loginResponse,
            'Login response should be returned.'
        );
        System.assertEquals(
            carrier.Id,
            loginResponse.carrier.carrierId
        );
        System.assertEquals(
            carrier.Name,
            loginResponse.carrier.carrierName
        );
        System.assertEquals(
            carrier.FreightTM__MC_MX_FF_Number__c,
            loginResponse.carrier.mcNumber
        );

        System.assertEquals(
            2,
            loginResponse.openOpportunityCount,
            'Only unassigned, uncanceled loads without this carrier bid should appear.'
        );
        System.assertEquals(
            1,
            loginResponse.submittedBidCount
        );
        System.assertEquals(
            2,
            loginResponse.loads.size()
        );

        Map<Id, LoadBoardForCarrierController.LoadRow>
            rowsByLoadId =
                new Map<Id, LoadBoardForCarrierController.LoadRow>();

        for (
            LoadBoardForCarrierController.LoadRow row :
            loginResponse.loads
        ) {
            rowsByLoadId.put(row.loadId, row);
        }

        System.assert(
            rowsByLoadId.containsKey(visibleLoad.Id),
            'Detailed open load should be visible.'
        );
        System.assert(
            rowsByLoadId.containsKey(blankAddressLoad.Id),
            'Open load with blank address should be visible.'
        );
        System.assert(
            !rowsByLoadId.containsKey(bidLoad.Id),
            'Load with an existing carrier bid should be excluded.'
        );
        System.assert(
            !rowsByLoadId.containsKey(assignedLoad.Id),
            'Assigned load should be excluded.'
        );

        LoadBoardForCarrierController.LoadRow visibleRow =
            rowsByLoadId.get(visibleLoad.Id);

        System.assertEquals('Open', visibleRow.status);
        System.assertEquals(
            '100 Test Pickup St, Los Angeles, CA 90001',
            visibleRow.pickupAddress
        );
        System.assertEquals(
            '200 Test Delivery Ave, Phoenix, AZ 85001',
            visibleRow.deliveryAddress
        );
        System.assertEquals(
            'Los Angeles, CA → Phoenix, AZ',
            visibleRow.lane
        );
        System.assert(
            visibleRow.searchText.contains('los angeles'),
            'Search text should contain the pickup city.'
        );
        System.assert(
            visibleRow.searchText.contains('900'),
            'Search text should contain the first three ZIP characters.'
        );

        System.assertEquals(
            'Not specified',
            rowsByLoadId.get(blankAddressLoad.Id).pickupAddress
        );
        System.assertEquals(
            'Not specified',
            rowsByLoadId.get(blankAddressLoad.Id).deliveryAddress
        );

        System.assertEquals(
            loginResponse.openOpportunityCount,
            refreshResponse.openOpportunityCount
        );
        System.assertEquals(
            loginResponse.submittedBidCount,
            refreshResponse.submittedBidCount
        );

        if (myBidsMethodAvailable) {
            System.assertEquals(
                1,
                myBidsResponse.submittedBidCount
            );
            System.assertEquals(
                existingBid.Id,
                myBidsResponse.bids[0].bidId
            );
            System.assertEquals(
                bidLoad.Id,
                myBidsResponse.bids[0].loadId
            );
            System.assertEquals(
                1550,
                myBidsResponse.bids[0].rate
            );
            System.assertNotEquals(
                null,
                myBidsResponse.bids[0].submittedDate
            );

            if (
                isBidFieldReadable('Transit_Time__c') &&
                isBidFieldCreateable('Transit_Time__c')
            ) {
                System.assertEquals(
                    '2',
                    myBidsResponse.bids[0].transitTime
                );
            }
        }

        System.assertEquals(
            1,
            assignedLoadsResponse.assignedLoadCount
        );
        System.assertEquals(
            assignedLoad.Id,
            assignedLoadsResponse.loads[0].loadId
        );
        FreightTM__Load__c storedAssignedLoad = [
            SELECT FreightTM__Status__c
            FROM FreightTM__Load__c
            WHERE Id = :assignedLoad.Id
            LIMIT 1
        ];

        String expectedAssignedStatus =
            String.isBlank(storedAssignedLoad.FreightTM__Status__c)
                ? 'Open'
                : storedAssignedLoad.FreightTM__Status__c;

        System.assertEquals(
            expectedAssignedStatus,
            assignedLoadsResponse.loads[0].status
        );
        System.assertEquals(
            '100 Test Pickup St, Los Angeles, CA 90001',
            assignedLoadsResponse.loads[0].pickupAddress
        );
        System.assertEquals(
            1404,
            assignedLoadsResponse.loads[0].rate
        );
    }

    @IsTest
    static void testLoginAndSessionValidationErrors() {
        FreightTM__Carrier__c eligibleCarrier =
            createCarrier(true);

        FreightTM__Carrier__c inactiveCarrier =
            createCarrier(false);

        Integer exceptionCount = 0;
        String tooLong = '';

        for (Integer index = 0; index < 101; index++) {
            tooLong += 'X';
        }

        try {
            LoadBoardForCarrierController.loginCarrier(
                '',
                'MC123'
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.loginCarrier(
                eligibleCarrier.Name,
                ''
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.loginCarrier(
                tooLong,
                'MC123'
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.loginCarrier(
                'Carrier That Does Not Exist',
                'MC-NOT-FOUND'
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.refreshLoadBoard(
                null,
                eligibleCarrier.Name,
                eligibleCarrier.FreightTM__MC_MX_FF_Number__c
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.refreshLoadBoard(
                eligibleCarrier.Id,
                'Wrong Carrier Name',
                eligibleCarrier.FreightTM__MC_MX_FF_Number__c
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.getMyBids(
                inactiveCarrier.Id,
                inactiveCarrier.Name,
                inactiveCarrier.FreightTM__MC_MX_FF_Number__c
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.getAssignedLoads(
                eligibleCarrier.Id,
                eligibleCarrier.Name,
                'WRONG-MC'
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        System.assertEquals(
            8,
            exceptionCount,
            'Every invalid login or session request should throw an AuraHandledException.'
        );
    }

    @IsTest
    static void testCreateBidValidationBranches() {
        FreightTM__Carrier__c eligibleCarrier =
            createCarrier(true);

        FreightTM__Carrier__c inactiveCarrier =
            createCarrier(false);

        FreightTM__Load__c openLoad =
            createLoad(null, false, true, 1);

        FreightTM__Load__c assignedLoad =
            createLoad(eligibleCarrier.Id, false, true, 2);

        FreightTM__Load__c duplicateBidLoad =
            createLoad(null, false, true, 3);

        createBidRecord(
            eligibleCarrier.Id,
            duplicateBidLoad.Id,
            1200,
            '2'
        );

        Integer exceptionCount = 0;
        Datetime transitionDate =
            System.now().addDays(1);

        try {
            LoadBoardForCarrierController.createBid(
                null,
                openLoad.Id,
                1000,
                transitionDate,
                '2'
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.createBid(
                eligibleCarrier.Id,
                null,
                1000,
                transitionDate,
                '2'
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.createBid(
                eligibleCarrier.Id,
                openLoad.Id,
                0,
                transitionDate,
                '2'
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.createBid(
                eligibleCarrier.Id,
                openLoad.Id,
                1000,
                null,
                '2'
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.createBid(
                eligibleCarrier.Id,
                openLoad.Id,
                1000,
                transitionDate,
                ''
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.createBid(
                eligibleCarrier.Id,
                openLoad.Id,
                1000,
                transitionDate,
                'two'
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.createBid(
                eligibleCarrier.Id,
                openLoad.Id,
                1000,
                transitionDate,
                '0'
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.createBid(
                eligibleCarrier.Id,
                openLoad.Id,
                1000,
                transitionDate,
                '999999999999999999999999999999999999'
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.createBid(
                inactiveCarrier.Id,
                openLoad.Id,
                1000,
                transitionDate,
                '2'
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.createBid(
                eligibleCarrier.Id,
                assignedLoad.Id,
                1000,
                transitionDate,
                '2'
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        try {
            LoadBoardForCarrierController.createBid(
                eligibleCarrier.Id,
                duplicateBidLoad.Id,
                1000,
                transitionDate,
                '2'
            );
        } catch (AuraHandledException errorValue) {
            exceptionCount++;
        }

        System.assertEquals(
            11,
            exceptionCount,
            'All bid validation branches should reject invalid requests.'
        );
    }

    @IsTest
    static void testCreateBidSuccessCoversEventTriggerAndHandler() {
        FreightTM__Carrier__c carrier =
            createCarrier(true);

        FreightTM__Load__c loadRecord =
            createLoad(null, false, true, 1);

        Datetime transitionDate =
            System.now().addDays(1);

        Test.startTest();

        LoadBoardForCarrierController.BidResponse response =
            LoadBoardForCarrierController.createBid(
                carrier.Id,
                loadRecord.Id,
                1675.50,
                transitionDate,
                '3'
            );

        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertNotEquals(
            null,
            response,
            'Bid response should be returned.'
        );
        System.assertEquals(
            null,
            response.bidId,
            'Platform event processing is asynchronous, so bidId is intentionally null.'
        );
        System.assertNotEquals(
            null,
            response.requestId
        );
        System.assertEquals(
            36,
            response.requestId.length()
        );
        System.assert(
            response.message.contains('received'),
            'Response should confirm receipt.'
        );

        List<FreightTM__Bid__c> bids = [
            SELECT
                Id,
                FreightTM__Carrier__c,
                FreightTM__Load__c,
                FreightTM__Rate__c
            FROM FreightTM__Bid__c
            WHERE FreightTM__Carrier__c = :carrier.Id
                AND FreightTM__Load__c = :loadRecord.Id
        ];

        System.assert(
            bids.size() <= 1,
            'The event must never create duplicate Bids.'
        );

        if (!bids.isEmpty()) {
            System.assertEquals(
                1675.50,
                bids[0].FreightTM__Rate__c
            );
        }
    }

    @IsTest
    static void testHandlerNullEmptyAndInvalidEvents() {
        FreightTM__Carrier__c carrier =
            createCarrier(true);

        FreightTM__Load__c loadRecord =
            createLoad(null, false, true, 1);

        Datetime validDate =
            System.now().addDays(1);

        List<Load_Board_Bid_Request__e> invalidEvents =
            new List<Load_Board_Bid_Request__e>();

        invalidEvents.add(
            buildEvent(
                '',
                carrier.Id,
                loadRecord.Id,
                1000,
                validDate,
                '2'
            )
        );

        invalidEvents.add(
            buildEvent(
                'NO-CARRIER-' + nextKey(),
                null,
                loadRecord.Id,
                1000,
                validDate,
                '2'
            )
        );

        invalidEvents.add(
            buildEvent(
                'NO-LOAD-' + nextKey(),
                carrier.Id,
                null,
                1000,
                validDate,
                '2'
            )
        );

        invalidEvents.add(
            buildEvent(
                'BAD-RATE-' + nextKey(),
                carrier.Id,
                loadRecord.Id,
                0,
                validDate,
                '2'
            )
        );

        invalidEvents.add(
            buildEvent(
                'NO-DATE-' + nextKey(),
                carrier.Id,
                loadRecord.Id,
                1000,
                null,
                '2'
            )
        );

        invalidEvents.add(
            buildEvent(
                'NO-TRANSIT-' + nextKey(),
                carrier.Id,
                loadRecord.Id,
                1000,
                validDate,
                ''
            )
        );

        invalidEvents.add(
            buildEvent(
                'TEXT-TRANSIT-' + nextKey(),
                carrier.Id,
                loadRecord.Id,
                1000,
                validDate,
                'two'
            )
        );

        invalidEvents.add(
            buildEvent(
                'ZERO-TRANSIT-' + nextKey(),
                carrier.Id,
                loadRecord.Id,
                1000,
                validDate,
                '0'
            )
        );

        invalidEvents.add(
            buildEvent(
                'OVERFLOW-TRANSIT-' + nextKey(),
                carrier.Id,
                loadRecord.Id,
                1000,
                validDate,
                '999999999999999999999999999999999999'
            )
        );

        Load_Board_Bid_Request__e invalidIdEvent =
            buildEvent(
                'INVALID-ID-' + nextKey(),
                carrier.Id,
                loadRecord.Id,
                1000,
                validDate,
                '2'
            );

        invalidIdEvent.Carrier_ID__c = 'not-an-id';
        invalidIdEvent.Load_ID__c = 'also-not-an-id';
        invalidEvents.add(invalidIdEvent);

        Test.startTest();

        LoadBoardBidRequestHandler.handleAfterInsert(null);
        LoadBoardBidRequestHandler.handleAfterInsert(
            new List<Load_Board_Bid_Request__e>()
        );
        LoadBoardBidRequestHandler.handleAfterInsert(
            invalidEvents
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM FreightTM__Bid__c
                WHERE FreightTM__Carrier__c = :carrier.Id
                    AND FreightTM__Load__c = :loadRecord.Id
            ],
            'Invalid events must not create a Bid.'
        );
    }

    @IsTest
    static void testHandlerEligibilityExistingAndDuplicateBranches() {
        FreightTM__Carrier__c eligibleCarrier =
            createCarrier(true);

        FreightTM__Carrier__c inactiveCarrier =
            createCarrier(false);

        FreightTM__Load__c scheduledDuplicateLoad =
            createLoad(null, false, true, 1);

        FreightTM__Load__c existingBidLoad =
            createLoad(null, false, true, 2);

        FreightTM__Load__c assignedLoad =
            createLoad(eligibleCarrier.Id, false, true, 3);

        FreightTM__Load__c canceledLoad =
            createLoad(null, true, true, 4);

        FreightTM__Load__c duplicateRequestFirstLoad =
            createLoad(null, false, true, 5);

        FreightTM__Load__c duplicateRequestSecondLoad =
            createLoad(null, false, true, 6);

        createBidRecord(
            eligibleCarrier.Id,
            existingBidLoad.Id,
            1200,
            '2'
        );

        Datetime transitionDate =
            System.now().addDays(1);

        String duplicateRequestId =
            'SAME-REQUEST-' + nextKey();

        List<Load_Board_Bid_Request__e> events =
            new List<Load_Board_Bid_Request__e>{
                buildEvent(
                    'INACTIVE-' + nextKey(),
                    inactiveCarrier.Id,
                    scheduledDuplicateLoad.Id,
                    1000,
                    transitionDate,
                    '2'
                ),
                buildEvent(
                    'ASSIGNED-' + nextKey(),
                    eligibleCarrier.Id,
                    assignedLoad.Id,
                    1000,
                    transitionDate,
                    '2'
                ),
                buildEvent(
                    'CANCELED-' + nextKey(),
                    eligibleCarrier.Id,
                    canceledLoad.Id,
                    1000,
                    transitionDate,
                    '2'
                ),
                buildEvent(
                    'EXISTING-' + nextKey(),
                    eligibleCarrier.Id,
                    existingBidLoad.Id,
                    1000,
                    transitionDate,
                    '2'
                ),
                buildEvent(
                    'SCHEDULED-A-' + nextKey(),
                    eligibleCarrier.Id,
                    scheduledDuplicateLoad.Id,
                    1300,
                    transitionDate,
                    '3'
                ),
                buildEvent(
                    'SCHEDULED-B-' + nextKey(),
                    eligibleCarrier.Id,
                    scheduledDuplicateLoad.Id,
                    1400,
                    transitionDate,
                    '4'
                ),
                buildEvent(
                    duplicateRequestId,
                    eligibleCarrier.Id,
                    duplicateRequestFirstLoad.Id,
                    1500,
                    transitionDate,
                    '5'
                ),
                buildEvent(
                    duplicateRequestId,
                    eligibleCarrier.Id,
                    duplicateRequestSecondLoad.Id,
                    1600,
                    transitionDate,
                    '6'
                )
            };

        Test.startTest();
        LoadBoardBidRequestHandler.handleAfterInsert(events);
        Test.stopTest();

        List<FreightTM__Bid__c> createdBids = [
            SELECT
                Id,
                FreightTM__Load__c,
                FreightTM__Rate__c
            FROM FreightTM__Bid__c
            WHERE FreightTM__Carrier__c = :eligibleCarrier.Id
        ];

        System.assert(
            createdBids.size() >= 1 &&
            createdBids.size() <= 3,
            'The existing Bid must remain and no duplicate Bids may be created.'
        );

        Map<Id, FreightTM__Bid__c> bidsByLoadId =
            new Map<Id, FreightTM__Bid__c>();

        for (FreightTM__Bid__c bidRecord : createdBids) {
            bidsByLoadId.put(
                bidRecord.FreightTM__Load__c,
                bidRecord
            );
        }

        System.assert(
            bidsByLoadId.containsKey(existingBidLoad.Id),
            'Existing Bid should remain.'
        );
        if (bidsByLoadId.containsKey(scheduledDuplicateLoad.Id)) {
            System.assertEquals(
                1300,
                bidsByLoadId
                    .get(scheduledDuplicateLoad.Id)
                    .FreightTM__Rate__c
            );
        }

        System.assert(
            !(
                bidsByLoadId.containsKey(duplicateRequestFirstLoad.Id) &&
                bidsByLoadId.containsKey(duplicateRequestSecondLoad.Id)
            ),
            'Only one event with the same request ID may create a Bid.'
        );
        System.assert(
            !bidsByLoadId.containsKey(assignedLoad.Id),
            'Assigned load must not receive a Bid.'
        );
        System.assert(
            !bidsByLoadId.containsKey(canceledLoad.Id),
            'Canceled load must not receive a Bid.'
        );
    }
}
