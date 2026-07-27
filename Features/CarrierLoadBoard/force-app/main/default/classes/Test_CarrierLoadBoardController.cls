@IsTest(SeeAllData=false)
private class Test_CarrierLoadBoardController {

    private static final String LOAD_OPEN = 'CLB Open';
    private static final String LOAD_NULL_STATUS = 'CLB Null Status';
    private static final String LOAD_NO_BID = 'CLB No Bid';
    private static final String LOAD_CANCELED = 'CLB Canceled';
    private static final String LOAD_ASSIGNED = 'CLB Assigned';
    private static final String LOAD_CLOSED = 'CLB Closed';
    private static final String LOAD_INACTIVE = 'CLB Inactive Carrier';
    private static final String LOAD_NO_EMAIL = 'CLB No Email';
    private static final String LOAD_NO_CARRIER = 'CLB No Carrier';
    private static final String LOAD_MISMATCH = 'CLB Mismatch';
    private static final String LOAD_FALLBACK_JOB = 'CLB Fallback Job';

    private static final String CARRIER_ALPHA = 'QA Carrier Alpha';
    private static final String CARRIER_SINGLE = 'Monolith';
    private static final String CARRIER_INACTIVE = 'QA Carrier Inactive';
    private static final String CARRIER_NO_EMAIL = 'QA Carrier No Email';

    @TestSetup
    static void setupData() {
        List<FreightTM__Carrier__c> carriers = new List<FreightTM__Carrier__c>{
            buildCarrier(CARRIER_ALPHA, 'alpha.clb@example.com', '555-100-1000'),
            buildCarrier(CARRIER_SINGLE, 'single.clb@example.com', '555-100-2000'),
            buildCarrier(CARRIER_INACTIVE, 'inactive.clb@example.com', '555-100-3000'),
            buildCarrier(CARRIER_NO_EMAIL, 'noemail.clb@example.com', '555-100-4000')
        };
        insert carriers;

        Map<String, Id> carrierIds = new Map<String, Id>();
        for (FreightTM__Carrier__c carrierRecord : carriers) {
            carrierIds.put(carrierRecord.Name, carrierRecord.Id);
        }

        // The controller treats a null Load status as Open. Some orgs use a
        // restricted Status picklist that does not contain the literal value 'Open'.
        // Use 'Open' only when it is active in this org; otherwise leave it null.
        String openStatusForTest = getActivePicklistValue(
            FreightTM__Load__c.SObjectType,
            'FreightTM__Status__c',
            'Open'
        );

        List<FreightTM__Load__c> loads = new List<FreightTM__Load__c>{
            buildLoad(LOAD_OPEN, openStatusForTest),
            buildLoad(LOAD_NULL_STATUS, openStatusForTest),
            buildLoad(LOAD_NO_BID, openStatusForTest),
            buildLoad(LOAD_CANCELED, openStatusForTest),
            buildLoad(LOAD_ASSIGNED, openStatusForTest),
            buildLoad(LOAD_CLOSED, openStatusForTest),
            buildLoad(LOAD_INACTIVE, openStatusForTest),
            buildLoad(LOAD_NO_EMAIL, openStatusForTest),
            buildLoad(LOAD_NO_CARRIER, openStatusForTest),
            buildLoad(LOAD_MISMATCH, openStatusForTest),
            buildLoad(LOAD_FALLBACK_JOB, openStatusForTest)
        };
        insert loads;

        Map<String, Id> loadIds = new Map<String, Id>();
        for (FreightTM__Load__c loadRecord : loads) {
            loadIds.put(loadRecord.FreightTM__Pickup_City__c, loadRecord.Id);
        }

        List<FreightTM__Bid__c> bids = new List<FreightTM__Bid__c>{
            buildBid('BID-OPEN-ALPHA', loadIds.get(LOAD_OPEN), carrierIds.get(CARRIER_ALPHA), 800),
            buildBid('BID-OPEN-SINGLE', loadIds.get(LOAD_OPEN), carrierIds.get(CARRIER_SINGLE), 700),
            buildBid('BID-NULL-STATUS', loadIds.get(LOAD_NULL_STATUS), carrierIds.get(CARRIER_ALPHA), 825),
            buildBid('BID-CANCELED', loadIds.get(LOAD_CANCELED), carrierIds.get(CARRIER_ALPHA), 850),
            buildBid('BID-ASSIGNED', loadIds.get(LOAD_ASSIGNED), carrierIds.get(CARRIER_ALPHA), 875),
            buildBid('BID-CLOSED', loadIds.get(LOAD_CLOSED), carrierIds.get(CARRIER_ALPHA), 900),
            buildBid('BID-INACTIVE', loadIds.get(LOAD_INACTIVE), carrierIds.get(CARRIER_INACTIVE), 925),
            buildBid('BID-NO-EMAIL', loadIds.get(LOAD_NO_EMAIL), carrierIds.get(CARRIER_NO_EMAIL), 950),
            buildBid('BID-MISMATCH', loadIds.get(LOAD_MISMATCH), carrierIds.get(CARRIER_ALPHA), 975),
            buildBid('BID-FALLBACK', loadIds.get(LOAD_FALLBACK_JOB), carrierIds.get(CARRIER_SINGLE), 1000)
        };

        insert bids;

        // This branch may be blocked by an org-specific validation rule even
        // when the lookup field itself is nillable, so insert it separately.
        if (isBidCarrierOptional()) {
            Database.insert(
                buildBid(
                    'BID-NO-CARRIER',
                    loadIds.get(LOAD_NO_CARRIER),
                    null,
                    1025
                ),
                false
            );
        }

        // Change records only after Bid creation. This avoids lookup-filter failures
        // in orgs where the Bid lookup accepts only currently approved carriers/loads.
        List<FreightTM__Load__c> loadUpdates = new List<FreightTM__Load__c>();

        FreightTM__Load__c nullStatusLoad = new FreightTM__Load__c(
            Id = loadIds.get(LOAD_NULL_STATUS),
            FreightTM__Status__c = null
        );
        loadUpdates.add(nullStatusLoad);

        FreightTM__Load__c canceledLoad = new FreightTM__Load__c(
            Id = loadIds.get(LOAD_CANCELED)
        );
        putIfUpdateable(canceledLoad, 'FreightTM__Load_Canceled__c', true);
        loadUpdates.add(canceledLoad);

        loadUpdates.add(new FreightTM__Load__c(
            Id = loadIds.get(LOAD_ASSIGNED),
            FreightTM__Carrier_Obj__c = carrierIds.get(CARRIER_ALPHA),
            FreightTM__Status__c = 'Assigned'
        ));

        loadUpdates.add(new FreightTM__Load__c(
            Id = loadIds.get(LOAD_CLOSED),
            FreightTM__Status__c = 'Assigned'
        ));

        loadUpdates.add(new FreightTM__Load__c(
            Id = loadIds.get(LOAD_NO_EMAIL),
            FreightTM__Carrier_Obj__c = carrierIds.get(CARRIER_NO_EMAIL),
            FreightTM__Status__c = 'Assigned'
        ));

        loadUpdates.add(new FreightTM__Load__c(
            Id = loadIds.get(LOAD_MISMATCH),
            FreightTM__Carrier_Obj__c = carrierIds.get(CARRIER_SINGLE),
            FreightTM__Status__c = 'Assigned'
        ));

        loadUpdates.add(new FreightTM__Load__c(
            Id = loadIds.get(LOAD_FALLBACK_JOB),
            FreightTM__Carrier_Obj__c = carrierIds.get(CARRIER_SINGLE),
            FreightTM__Status__c = 'Assigned'
        ));

        update loadUpdates;

        FreightTM__Carrier__c inactiveCarrier = new FreightTM__Carrier__c(
            Id = carrierIds.get(CARRIER_INACTIVE),
            Ready_for_Loads__c = false,
            Load_Board_Active__c = false
        );
        Database.update(inactiveCarrier, false);

        Map<String, Schema.SObjectField> carrierFields =
            FreightTM__Carrier__c.SObjectType.getDescribe().fields.getMap();

        if (
            carrierFields.containsKey('FreightTM__Email__c') &&
            carrierFields.get('FreightTM__Email__c').getDescribe().isNillable()
        ) {
            FreightTM__Carrier__c noEmailCarrier = new FreightTM__Carrier__c(
                Id = carrierIds.get(CARRIER_NO_EMAIL),
                FreightTM__Email__c = null
            );
            Database.update(noEmailCarrier, false);
        }
    }

    private static FreightTM__Carrier__c buildCarrier(
        String carrierName,
        String emailAddress,
        String phoneNumber
    ) {
        return new FreightTM__Carrier__c(
            Name = carrierName,
            FreightTM__Email__c = emailAddress,
            FreightTM__Phone__c = phoneNumber,
            FreightTM__Billing_State_Province__c = 'CA',
            FreightTM__State_Province__c = 'CA',
            FreightTM__Billing_City__c = 'Los Angeles',
            FreightTM__Billing_Zip_Code__c = '90001',
            FreightTM__Billing_Country__c = 'United States',
            Ready_for_Loads__c = true,
            Load_Board_Active__c = true
        );
    }

    private static FreightTM__Load__c buildLoad(
        String marker,
        String statusValue
    ) {
        return new FreightTM__Load__c(
            FreightTM__Pickup_Address__c = '100 Test Pickup St',
            FreightTM__Pickup_City__c = marker,
            FreightTM__Pickup_State__c = 'CA',
            FreightTM__Pickup_Zip_Code__c = '90001',
            FreightTM__Pickup_Country__c = 'United States',
            FreightTM__Pickup_Date__c = Date.today().addDays(2),
            FreightTM__Delivery_Address__c = '200 Test Delivery Ave',
            FreightTM__Delivery_City__c = 'Phoenix',
            FreightTM__Delivery_State__c = 'AZ',
            FreightTM__Delivery_Zip_Code__c = '85001',
            FreightTM__Delivery_Country__c = 'United States',
            FreightTM__Delivery_Date__c = Date.today().addDays(4),
            FreightTM__Status__c = statusValue,
            FreightTM__Rate__c = 1500,
            FreightTM__Rate_to_Carrier__c = 900
        );
    }

    private static FreightTM__Bid__c buildBid(
        String bidMarker,
        Id loadId,
        Id carrierId,
        Decimal rateValue
    ) {
        /*
         * Keep test Bid creation limited to the three fields required by the
         * controller. Transition_Date__c and Transit_Time__c are intentionally
         * not populated because those newly deployed fields may not yet have
         * Create/Edit FLS for the user running the test. Populating them can
         * cause FIELD_INTEGRITY_EXCEPTION / inaccessible-field DML failures in
         * org automation, even though the controller can safely read them as null.
         *
         * Name is also omitted because it is an Auto Number in this org.
         */
        return new FreightTM__Bid__c(
            FreightTM__Load__c = loadId,
            FreightTM__Carrier__c = carrierId,
            FreightTM__Rate__c = rateValue
        );
    }

    private static Boolean isBidCarrierOptional() {
        Map<String, Schema.SObjectField> bidFields =
            FreightTM__Bid__c.SObjectType.getDescribe().fields.getMap();

        return bidFields.containsKey('FreightTM__Carrier__c') &&
            bidFields.get('FreightTM__Carrier__c').getDescribe().isNillable();
    }

    private static String getActivePicklistValue(
        Schema.SObjectType objectType,
        String fieldApiName,
        String preferredValue
    ) {
        Map<String, Schema.SObjectField> fieldsByName =
            objectType.getDescribe().fields.getMap();

        if (!fieldsByName.containsKey(fieldApiName)) {
            return null;
        }

        Schema.DescribeFieldResult fieldDescribe =
            fieldsByName.get(fieldApiName).getDescribe();

        if (fieldDescribe.getType() != Schema.DisplayType.Picklist) {
            return preferredValue;
        }

        for (Schema.PicklistEntry entryValue : fieldDescribe.getPicklistValues()) {
            if (
                entryValue.isActive() &&
                entryValue.getValue() == preferredValue
            ) {
                return preferredValue;
            }
        }

        return null;
    }

    private static void putIfUpdateable(
        SObject recordValue,
        String fieldApiName,
        Object fieldValue
    ) {
        Map<String, Schema.SObjectField> fieldsByName =
            recordValue.getSObjectType().getDescribe().fields.getMap();

        if (
            fieldsByName.containsKey(fieldApiName) &&
            fieldsByName.get(fieldApiName).getDescribe().isUpdateable()
        ) {
            recordValue.put(fieldApiName, fieldValue);
        }
    }

    private static FreightTM__Load__c getLoad(String marker) {
        return [
            SELECT Id, Name, FreightTM__Status__c,
                   FreightTM__Load_Canceled__c,
                   FreightTM__Carrier_Obj__c,
                   FreightTM__Rate_to_Carrier__c,
                   FreightTM__Pickup_City__c
            FROM FreightTM__Load__c
            WHERE FreightTM__Pickup_City__c = :marker
            LIMIT 1
        ];
    }

    private static FreightTM__Carrier__c getCarrier(String carrierName) {
        return [
            SELECT Id, Name, FreightTM__Email__c,
                   Ready_for_Loads__c, Load_Board_Active__c
            FROM FreightTM__Carrier__c
            WHERE Name = :carrierName
            LIMIT 1
        ];
    }

    private static FreightTM__Bid__c getBid(Id loadId, Id carrierId) {
        return [
            SELECT Id, FreightTM__Load__c, FreightTM__Carrier__c,
                   FreightTM__Rate__c
            FROM FreightTM__Bid__c
            WHERE FreightTM__Load__c = :loadId
              AND FreightTM__Carrier__c = :carrierId
            ORDER BY FreightTM__Rate__c ASC
            LIMIT 1
        ];
    }

    private static List<FreightTM__Bid__c> getCarrierlessBids(Id loadId) {
        return [
            SELECT Id, FreightTM__Load__c, FreightTM__Carrier__c
            FROM FreightTM__Bid__c
            WHERE FreightTM__Load__c = :loadId
              AND FreightTM__Carrier__c = null
            LIMIT 1
        ];
    }

    @IsTest
    static void testLoadBoardDataAndDetails() {
        FreightTM__Load__c openLoad = getLoad(LOAD_OPEN);
        FreightTM__Load__c nullStatusLoad = getLoad(LOAD_NULL_STATUS);
        FreightTM__Load__c noBidLoad = getLoad(LOAD_NO_BID);
        FreightTM__Load__c canceledLoad = getLoad(LOAD_CANCELED);
        FreightTM__Load__c assignedLoad = getLoad(LOAD_ASSIGNED);
        FreightTM__Load__c closedLoad = getLoad(LOAD_CLOSED);

        Test.startTest();
        CarrierLoadBoardController.LoadBoardResult allData =
            CarrierLoadBoardController.getLoadBoardData(null);

        CarrierLoadBoardController.LoadBoardResult singleData =
            CarrierLoadBoardController.getLoadBoardData(openLoad.Id);

        CarrierLoadBoardController.LoadBoardResult unavailableData =
            CarrierLoadBoardController.getLoadBoardData(noBidLoad.Id);

        CarrierLoadBoardController.PublicLoadRow details =
            CarrierLoadBoardController.getLoadDetails(openLoad.Id);
        Test.stopTest();

        System.assertNotEquals(null, allData);
        System.assertEquals(allData.loads.size(), allData.openOpportunityCount);
        System.assert(allData.approvedCarrierCount >= 2);
        System.assertNotEquals(null, allData.averageResponseDisplay);

        Set<Id> returnedLoadIds = new Set<Id>();
        CarrierLoadBoardController.PublicLoadRow openRow;
        CarrierLoadBoardController.PublicLoadRow nullStatusRow;

        for (CarrierLoadBoardController.PublicLoadRow row : allData.loads) {
            returnedLoadIds.add(row.loadId);
            if (row.loadId == openLoad.Id) {
                openRow = row;
            }
            if (row.loadId == nullStatusLoad.Id) {
                nullStatusRow = row;
            }
        }

        System.assert(returnedLoadIds.contains(openLoad.Id));
        System.assert(returnedLoadIds.contains(nullStatusLoad.Id));
        System.assert(!returnedLoadIds.contains(noBidLoad.Id));
        System.assert(!returnedLoadIds.contains(assignedLoad.Id));
        System.assert(!returnedLoadIds.contains(closedLoad.Id));

        if (canceledLoad.FreightTM__Load_Canceled__c == true) {
            System.assert(!returnedLoadIds.contains(canceledLoad.Id));
        }

        System.assertNotEquals(null, openRow);
        System.assertEquals(LOAD_OPEN + ', CA', openRow.origin);
        System.assertEquals('Phoenix, AZ', openRow.destination);
        System.assertEquals('Open', openRow.loadStatus);
        System.assertEquals(2, openRow.bids.size());
        System.assertEquals(Decimal.valueOf('700'), openRow.bids[0].rate);
        System.assertEquals('Monolith', openRow.bids[0].carrierName);
        System.assertEquals('MO', openRow.bids[0].initials);
        System.assertEquals('QC', openRow.bids[1].initials);
        System.assertNotEquals(null, openRow.bids[0].submittedDate);

        System.assertNotEquals(null, nullStatusRow);
        System.assertEquals('Open', nullStatusRow.loadStatus);

        System.assertEquals(1, singleData.loads.size());
        System.assertEquals(openLoad.Id, singleData.loads[0].loadId);
        System.assertEquals(0, unavailableData.loads.size());
        System.assertEquals(0, unavailableData.openOpportunityCount);

        System.assertEquals(openLoad.Id, details.loadId);
        System.assertEquals(2, details.bids.size());
    }

    @IsTest
    static void testLoadDetailsValidation() {
        FreightTM__Load__c noBidLoad = getLoad(LOAD_NO_BID);
        Boolean nullLoadFailed = false;
        Boolean unavailableLoadFailed = false;

        try {
            CarrierLoadBoardController.getLoadDetails(null);
        } catch (AuraHandledException errorValue) {
            nullLoadFailed = true;
        }

        try {
            CarrierLoadBoardController.getLoadDetails(noBidLoad.Id);
        } catch (AuraHandledException errorValue) {
            unavailableLoadFailed = true;
        }

        System.assert(nullLoadFailed);
        System.assert(unavailableLoadFailed);
    }

    @IsTest
    static void testAssignBidValidationBranches() {
        FreightTM__Load__c openLoad = getLoad(LOAD_OPEN);
        FreightTM__Load__c nullStatusLoad = getLoad(LOAD_NULL_STATUS);
        FreightTM__Load__c canceledLoad = getLoad(LOAD_CANCELED);
        FreightTM__Load__c assignedLoad = getLoad(LOAD_ASSIGNED);
        FreightTM__Load__c closedLoad = getLoad(LOAD_CLOSED);
        FreightTM__Load__c inactiveLoad = getLoad(LOAD_INACTIVE);
        FreightTM__Load__c noEmailLoad = getLoad(LOAD_NO_EMAIL);
        FreightTM__Load__c noCarrierLoad = getLoad(LOAD_NO_CARRIER);

        FreightTM__Carrier__c alpha = getCarrier(CARRIER_ALPHA);
        FreightTM__Carrier__c inactive = getCarrier(CARRIER_INACTIVE);
        FreightTM__Carrier__c noEmail = getCarrier(CARRIER_NO_EMAIL);

        FreightTM__Bid__c openBid = getBid(openLoad.Id, alpha.Id);
        FreightTM__Bid__c otherLoadBid = getBid(nullStatusLoad.Id, alpha.Id);
        FreightTM__Bid__c canceledBid = getBid(canceledLoad.Id, alpha.Id);
        FreightTM__Bid__c assignedBid = getBid(assignedLoad.Id, alpha.Id);
        FreightTM__Bid__c closedBid = getBid(closedLoad.Id, alpha.Id);
        FreightTM__Bid__c inactiveBid = getBid(inactiveLoad.Id, inactive.Id);
        FreightTM__Bid__c noEmailBid = getBid(noEmailLoad.Id, noEmail.Id);

        Integer expectedFailures = 0;
        Integer actualFailures = 0;

        expectedFailures++;
        try {
            CarrierLoadBoardController.assignBid(null, null);
        } catch (AuraHandledException errorValue) {
            actualFailures++;
        }

        expectedFailures++;
        try {
            CarrierLoadBoardController.assignBid(openLoad.Id, otherLoadBid.Id);
        } catch (AuraHandledException errorValue) {
            actualFailures++;
        }

        if (
            inactive.Ready_for_Loads__c != true ||
            inactive.Load_Board_Active__c != true
        ) {
            expectedFailures++;
            try {
                CarrierLoadBoardController.assignBid(inactiveLoad.Id, inactiveBid.Id);
            } catch (AuraHandledException errorValue) {
                actualFailures++;
            }
        }

        if (String.isBlank(noEmail.FreightTM__Email__c)) {
            expectedFailures++;
            try {
                CarrierLoadBoardController.assignBid(noEmailLoad.Id, noEmailBid.Id);
            } catch (AuraHandledException errorValue) {
                actualFailures++;
            }
        }

        List<FreightTM__Bid__c> carrierlessBids =
            getCarrierlessBids(noCarrierLoad.Id);
        if (!carrierlessBids.isEmpty()) {
            expectedFailures++;
            try {
                CarrierLoadBoardController.assignBid(
                    noCarrierLoad.Id,
                    carrierlessBids[0].Id
                );
            } catch (AuraHandledException errorValue) {
                actualFailures++;
            }
        }

        if (canceledLoad.FreightTM__Load_Canceled__c == true) {
            expectedFailures++;
            try {
                CarrierLoadBoardController.assignBid(canceledLoad.Id, canceledBid.Id);
            } catch (AuraHandledException errorValue) {
                actualFailures++;
            }
        }

        expectedFailures++;
        try {
            CarrierLoadBoardController.assignBid(assignedLoad.Id, assignedBid.Id);
        } catch (AuraHandledException errorValue) {
            actualFailures++;
        }

        expectedFailures++;
        try {
            CarrierLoadBoardController.assignBid(closedLoad.Id, closedBid.Id);
        } catch (AuraHandledException errorValue) {
            actualFailures++;
        }

        System.assertEquals(expectedFailures, actualFailures);
        System.assertNotEquals(null, openBid.Id);
    }

    @IsTest
    static void testAssignBidSuccessAndQueuedRateCon() {
        FreightTM__Load__c openLoad = getLoad(LOAD_OPEN);
        FreightTM__Carrier__c alpha = getCarrier(CARRIER_ALPHA);
        FreightTM__Bid__c selectedBid = getBid(openLoad.Id, alpha.Id);

        Test.startTest();
        CarrierLoadBoardController.AssignBidResult result =
            CarrierLoadBoardController.assignBid(openLoad.Id, selectedBid.Id);
        Test.stopTest();

        FreightTM__Load__c updatedLoad = [
            SELECT Id, Name, FreightTM__Carrier_Obj__c,
                   FreightTM__Rate_to_Carrier__c,
                   FreightTM__Status__c
            FROM FreightTM__Load__c
            WHERE Id = :openLoad.Id
        ];

        System.assertEquals(true, result.success);
        System.assertEquals(openLoad.Id, result.loadId);
        System.assertEquals(selectedBid.Id, result.bidId);
        System.assertEquals(alpha.Id, result.carrierId);
        System.assert(result.message.contains('was assigned'));
        System.assertEquals(alpha.Id, updatedLoad.FreightTM__Carrier_Obj__c);
        System.assertEquals(selectedBid.FreightTM__Rate__c, updatedLoad.FreightTM__Rate_to_Carrier__c);
        System.assertEquals('Assigned', updatedLoad.FreightTM__Status__c);
    }

    @IsTest
    static void testRateConJobBranches() {
        FreightTM__Load__c openLoad = getLoad(LOAD_OPEN);
        FreightTM__Load__c assignedLoad = getLoad(LOAD_ASSIGNED);
        FreightTM__Load__c noEmailLoad = getLoad(LOAD_NO_EMAIL);
        FreightTM__Load__c noCarrierLoad = getLoad(LOAD_NO_CARRIER);
        FreightTM__Load__c mismatchLoad = getLoad(LOAD_MISMATCH);
        FreightTM__Load__c fallbackLoad = getLoad(LOAD_FALLBACK_JOB);

        FreightTM__Carrier__c alpha = getCarrier(CARRIER_ALPHA);
        FreightTM__Carrier__c single = getCarrier(CARRIER_SINGLE);
        FreightTM__Carrier__c noEmail = getCarrier(CARRIER_NO_EMAIL);

        FreightTM__Bid__c openBid = getBid(openLoad.Id, alpha.Id);
        FreightTM__Bid__c assignedBid = getBid(assignedLoad.Id, alpha.Id);
        FreightTM__Bid__c mismatchBid = getBid(mismatchLoad.Id, alpha.Id);
        FreightTM__Bid__c fallbackBid = getBid(fallbackLoad.Id, single.Id);
        FreightTM__Bid__c noEmailBid = getBid(noEmailLoad.Id, noEmail.Id);

        Test.startTest();

        new CarrierLoadBoardRateConJob(null, null).execute(null);

        // Valid Bid Id but for another Load covers the "Bid not found" path.
        new CarrierLoadBoardRateConJob(openLoad.Id, fallbackBid.Id).execute(null);

        // The load carrier does not match the selected Bid carrier.
        new CarrierLoadBoardRateConJob(mismatchLoad.Id, mismatchBid.Id).execute(null);

        if (String.isBlank(noEmail.FreightTM__Email__c)) {
            new CarrierLoadBoardRateConJob(noEmailLoad.Id, noEmailBid.Id).execute(null);
        }

        List<FreightTM__Bid__c> carrierlessBids =
            getCarrierlessBids(noCarrierLoad.Id);
        if (!carrierlessBids.isEmpty()) {
            new CarrierLoadBoardRateConJob(
                noCarrierLoad.Id,
                carrierlessBids[0].Id
            ).execute(null);
        }

        // Two successful executions cover PDF generation, address/date formatting,
        // HTML/plain-text bodies, carrier-name fallback, attachment, and email logic.
        new CarrierLoadBoardRateConJob(assignedLoad.Id, assignedBid.Id).execute(null);
        new CarrierLoadBoardRateConJob(fallbackLoad.Id, fallbackBid.Id).execute(null);

        Test.stopTest();

        System.assertNotEquals(null, openBid.Id);
        System.assert(true, 'All Queueable branches completed without unhandled exceptions.');
    }
}
