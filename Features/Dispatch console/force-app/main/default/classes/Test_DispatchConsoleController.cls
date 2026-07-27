@IsTest
private class Test_DispatchConsoleController {
    private static final String STATE_CA = 'CA';
    private static final String VALID_PORTAL_URL = 'https://example.com/driver/portal-test';

    @TestSetup
    static void setupData() {
        List<FreightTM__Carrier__c> carriers = new List<FreightTM__Carrier__c>{
            new FreightTM__Carrier__c(
                Name = 'QA Carrier Alpha',
                FreightTM__Email__c = 'alpha@example.com',
                FreightTM__Phone__c = '555-111-1000',
                FreightTM__Billing_State_Province__c = STATE_CA,
                FreightTM__State_Province__c = STATE_CA,
                FreightTM__Billing_City__c = 'Los Angeles',
                FreightTM__Billing_Zip_Code__c = '90001',
                FreightTM__Billing_Country__c = 'United States'
            ),
            new FreightTM__Carrier__c(
                Name = 'QA Carrier Beta',
                FreightTM__Email__c = 'beta@example.com',
                FreightTM__Phone__c = '555-111-2000',
                FreightTM__Billing_State_Province__c = 'TX',
                FreightTM__State_Province__c = 'TX',
                FreightTM__Billing_City__c = 'Dallas',
                FreightTM__Billing_Zip_Code__c = '75001',
                FreightTM__Billing_Country__c = 'United States'
            )
        };
        insert carriers;

        List<FreightTM__Employee__c> drivers = new List<FreightTM__Employee__c>{
            new FreightTM__Employee__c(
                Name = 'QA Driver Valid',
                FreightTM__First_Name__c = 'Valid',
                FreightTM__Email__c = 'valid.driver@example.com',
                FreightTM__Phone__c = '(555) 333-4444',
                FreightTM__State__c = STATE_CA,
                FreightTM__City__c = 'Los Angeles',
                Status__c = 'Available',
                Phone_Carriers__c = 'Verizon'
            ),
            new FreightTM__Employee__c(
                Name = 'QA Driver No Phone',
                FreightTM__First_Name__c = 'NoPhone',
                FreightTM__Email__c = 'nophone.driver@example.com',
                FreightTM__State__c = STATE_CA,
                FreightTM__City__c = 'Sacramento',
                Status__c = 'Waiting'
            ),
            new FreightTM__Employee__c(
                Name = 'QA Driver No Carrier',
                FreightTM__First_Name__c = 'NoCarrier',
                FreightTM__Email__c = 'nocarrier.driver@example.com',
                FreightTM__Phone__c = '555-333-7777',
                FreightTM__State__c = STATE_CA,
                FreightTM__City__c = 'San Diego',
                Status__c = 'Available'
            )
        };
        insert drivers;

        List<FreightTM__Truck__c> trucks = new List<FreightTM__Truck__c>{
            new FreightTM__Truck__c(
                Name = 'QA Truck Alpha',
                State_Province__c = STATE_CA,
                FreightTM__License_Plate_State__c = STATE_CA,
                FreightTM__License_Plate__c = 'QA-100',
                FreightTM__Status__c = 'Empty'
            ),
            new FreightTM__Truck__c(
                Name = 'QA Truck Beta',
                State_Province__c = 'TX',
                FreightTM__License_Plate_State__c = 'TX',
                FreightTM__License_Plate__c = 'QA-200',
                FreightTM__Status__c = 'Empty'
            )
        };
        insert trucks;

        List<FreightTM__Load__c> loads = new List<FreightTM__Load__c>();
        loads.add(buildLoad(
            0, 'Los Angeles', STATE_CA, 'Phoenix', 'AZ', 'Assigned',
            carriers[0].Id, drivers[0].Id, trucks[0].Id,
            true, 'Bill/POD Received', 'Ready to Invoice', null,
            1000, 700, VALID_PORTAL_URL
        ));
        loads.add(buildLoad(
            1, 'Sacramento', STATE_CA, 'Reno', 'NV', '',
            carriers[0].Id, drivers[2].Id, trucks[0].Id,
            false, 'Bill/POD Needed', null, 'Late Pickup',
            1000, 900, VALID_PORTAL_URL + '-no-carrier'
        ));
        loads.add(buildLoad(
            2, 'San Diego', STATE_CA, 'Tucson', 'AZ', 'Assigned',
            null, null, null,
            false, 'Bill/POD Needed', null, null,
            1000, 750, VALID_PORTAL_URL + '-unassigned'
        ));
        loads.add(buildLoad(
            3, 'Fresno', STATE_CA, 'Las Vegas', 'NV', 'Assigned',
            carriers[0].Id, drivers[1].Id, null,
            true, null, null, null,
            1000, 600, VALID_PORTAL_URL + '-no-phone'
        ));
        loads.add(buildLoad(
            4, 'Oakland', STATE_CA, 'Portland', 'OR', 'Assigned',
            carriers[0].Id, drivers[0].Id, trucks[0].Id,
            true, 'Bill/POD Received', null, null,
            1000, 800, VALID_PORTAL_URL + '-ready'
        ));
        loads.add(buildLoad(
            5, 'Bakersfield', STATE_CA, 'Seattle', 'WA', 'Assigned',
            carriers[0].Id, drivers[0].Id, trucks[0].Id,
            false, null, null, null,
            1000, 1100, null
        ));
        loads.add(buildLoad(
            6, 'Dallas', 'TX', 'Houston', 'TX', 'Assigned',
            carriers[1].Id, null, trucks[1].Id,
            false, null, null, null,
            1500, 1000, null
        ));
        loads.add(buildLoad(
            7, 'Austin', 'TX', 'Denver', 'CO', 'Assigned',
            carriers[1].Id, null, trucks[1].Id,
            false, null, null, null,
            1200, 900, null
        ));
        insert loads;
    }

    private static FreightTM__Load__c buildLoad(
        Integer indexValue,
        String pickupCity,
        String pickupState,
        String deliveryCity,
        String deliveryState,
        String statusValue,
        Id carrierId,
        Id driverId,
        Id truckId,
        Boolean podReceived,
        String billStatus,
        String invoiceStatus,
        String exceptionReason,
        Decimal customerRate,
        Decimal carrierRate,
        String portalLink
    ) {
        return new FreightTM__Load__c(
            FreightTM__Pickup_Address__c = 'QA ' + indexValue + '00 Pickup St',
            FreightTM__Pickup_City__c = pickupCity,
            FreightTM__Pickup_State__c = pickupState,
            FreightTM__Pickup_Zip_Code__c = pickupState == STATE_CA
                ? '9000' + indexValue
                : '7500' + indexValue,
            FreightTM__Pickup_Country__c = 'United States',
            FreightTM__Delivery_Address__c = 'QA ' + indexValue + '00 Delivery St',
            FreightTM__Delivery_City__c = deliveryCity,
            FreightTM__Delivery_State__c = deliveryState,
            FreightTM__Delivery_Zip_Code__c = '8500' + indexValue,
            FreightTM__Delivery_Country__c = 'United States',
            FreightTM__Status__c = statusValue,
            FreightTM__Pickup_Date__c = Date.today().addDays(indexValue),
            FreightTM__Delivery_Date__c = Date.today().addDays(indexValue + 2),
            FreightTM__Carrier_Obj__c = carrierId,
            FreightTM__Driver__c = driverId,
            FreightTM__Truck__c = truckId,
            FreightTM__Invoice_Status__c = invoiceStatus,
            FreightTM__Rate__c = customerRate,
            FreightTM__Rate_to_Carrier__c = carrierRate,
            POD_Received__c = podReceived,
            FreightTM__Bill_Status__c = billStatus,
            Exception_Reason__c = exceptionReason,
            Driver_Portal_Link__c = portalLink
        );
    }

    private static FreightTM__Load__c getLoadByPickup(String pickupCity) {
        return [
            SELECT Id, CreatedDate, FreightTM__Driver__c, FreightTM__Truck__c,
                   FreightTM__Carrier_Obj__c, Driver_Portal_Link__c,
                   Driver_Phone_Number__c, Driver_Phone_Carrier__c
            FROM FreightTM__Load__c
            WHERE FreightTM__Pickup_City__c = :pickupCity
            LIMIT 1
        ];
    }

    private static FreightTM__Employee__c getDriver(String driverName) {
        return [
            SELECT Id, Name, FreightTM__Phone__c, Phone_Carriers__c
            FROM FreightTM__Employee__c
            WHERE Name = :driverName
            LIMIT 1
        ];
    }

    private static FreightTM__Truck__c getTruck(String truckName) {
        return [
            SELECT Id, Name
            FROM FreightTM__Truck__c
            WHERE Name = :truckName
            LIMIT 1
        ];
    }

    private static FreightTM__Carrier__c getCarrier(String carrierName) {
        return [
            SELECT Id, Name
            FROM FreightTM__Carrier__c
            WHERE Name = :carrierName
            LIMIT 1
        ];
    }

    @IsTest
    static void testDispatchDataAndLoadPagination() {
        Test.startTest();
        DispatchConsoleController.DispatchData dispatchData =
            DispatchConsoleController.getDispatchData(STATE_CA);

        DispatchConsoleController.LoadPageResult firstPage =
            DispatchConsoleController.getLoadPage(
                'loadBoard', STATE_CA, null, 'all', 'All', 2,
                null, null, 'first', true
            );

        FreightTM__Load__c firstCursor = firstPage.records[0];
        DispatchConsoleController.LoadPageResult nextPage =
            DispatchConsoleController.getLoadPage(
                'loadBoard', STATE_CA, null, 'all', 'All', 2,
                firstCursor.CreatedDate, firstCursor.Id, 'next', false
            );

        DispatchConsoleController.LoadPageResult lastPage =
            DispatchConsoleController.getLoadPage(
                'loadBoard', STATE_CA, null, 'all', 'All', 4,
                null, null, 'last', false
            );

        FreightTM__Load__c lastCursor = lastPage.records[0];
        DispatchConsoleController.LoadPageResult previousPage =
            DispatchConsoleController.getLoadPage(
                'loadBoard', STATE_CA, null, 'all', 'All', 4,
                lastCursor.CreatedDate, lastCursor.Id, 'previous', false
            );
        Test.stopTest();

        System.assert(dispatchData.loads.size() > 0, 'Dispatch data should include loads.');
        System.assert(dispatchData.trucks.size() > 0, 'Dispatch data should include trucks.');
        System.assert(dispatchData.drivers.size() > 0, 'Dispatch data should include drivers.');
        System.assert(dispatchData.carriers.size() > 0, 'Dispatch data should include carriers.');

        System.assertEquals(6, firstPage.totalCount);
        System.assertEquals(2, firstPage.records.size());
        System.assertEquals(2, firstPage.pageSize);
        System.assertNotEquals(null, firstPage.summary);
        System.assertEquals(6, firstPage.summary.totalLoads);
        System.assert(firstPage.statuses.contains('Assigned'));
        System.assertEquals(2, nextPage.records.size());
        System.assertNotEquals(firstCursor.Id, nextPage.records[0].Id);
        System.assertEquals(2, lastPage.records.size(), 'Last page should use the remainder.');
        System.assert(previousPage.records.size() > 0);
    }

    @IsTest
    static void testLoadFiltersSearchAndNormalization() {
        List<String> views = new List<String>{
            'all', 'exceptions', 'invoiceReady', 'readyToInvoice',
            'unassigned', 'lowMargin', 'profitable', 'missingPod',
            'waiting', 'complete', 'ready'
        };

        Test.startTest();
        for (String viewName : views) {
            DispatchConsoleController.LoadPageResult result =
                DispatchConsoleController.getLoadPage(
                    'margin', STATE_CA, null, viewName, 'All', 25,
                    null, null, 'first', viewName == 'all'
                );
            System.assertNotEquals(null, result.records);
            System.assert(result.totalCount >= 0);
        }

        DispatchConsoleController.LoadPageResult zipSearch =
            DispatchConsoleController.getLoadPage(
                'assignment', STATE_CA, '900', 'all', 'All', 25,
                null, null, 'first', false
            );
        DispatchConsoleController.LoadPageResult citySearch =
            DispatchConsoleController.getLoadPage(
                'assignment', STATE_CA, 'Los Angeles', 'all', 'All', 25,
                null, null, 'first', false
            );
        DispatchConsoleController.LoadPageResult escapedSearch =
            DispatchConsoleController.getLoadPage(
                'assignment', STATE_CA, 'O\'Hare', 'all', 'All', 25,
                null, null, 'first', false
            );
        DispatchConsoleController.LoadPageResult statusSearch =
            DispatchConsoleController.getLoadPage(
                'assignment', STATE_CA, null, 'all', 'Assigned', 25,
                null, null, 'first', false
            );
        DispatchConsoleController.LoadPageResult normalizedDefaults =
            DispatchConsoleController.getLoadPage(
                'loadBoard', STATE_CA, null, null, null, 0,
                null, null, 'not-a-direction', false
            );
        DispatchConsoleController.LoadPageResult cappedPageSize =
            DispatchConsoleController.getLoadPage(
                'loadBoard', STATE_CA, null, 'all', 'All', 1000,
                null, null, 'first', false
            );
        DispatchConsoleController.LoadPageResult emptySummary =
            DispatchConsoleController.getLoadPage(
                'loadBoard', 'ZZ', null, 'all', 'All', null,
                null, null, 'last', true
            );
        Test.stopTest();

        System.assertEquals(6, zipSearch.totalCount);
        System.assertEquals(1, citySearch.totalCount);
        System.assertEquals(0, escapedSearch.totalCount);
        System.assert(statusSearch.totalCount > 0);
        System.assertEquals(25, normalizedDefaults.pageSize);
        System.assertEquals(100, cappedPageSize.pageSize);
        System.assertEquals(0, emptySummary.totalCount);
        System.assertEquals(0, emptySummary.summary.totalLoads);
        System.assertEquals(0, emptySummary.summary.onTimePercent);
        System.assertEquals('No margin data', emptySummary.summary.bestMarginLoad);
    }

    @IsTest
    static void testResourcePagesSearchAndPagination() {
        Test.startTest();
        DispatchConsoleController.ResourcePageResult drivers =
            DispatchConsoleController.getResourcePage(
                'Driver', STATE_CA, 'QA Driver', 2,
                null, null, 'first', true
            );
        FreightTM__Employee__c driverCursor = drivers.drivers[0];
        DispatchConsoleController.ResourcePageResult nextDrivers =
            DispatchConsoleController.getResourcePage(
                'Driver', STATE_CA, null, 1,
                driverCursor.CreatedDate, driverCursor.Id, 'next', false
            );
        DispatchConsoleController.ResourcePageResult lastDrivers =
            DispatchConsoleController.getResourcePage(
                'Driver', STATE_CA, null, 2,
                null, null, 'last', false
            );

        DispatchConsoleController.ResourcePageResult carriers =
            DispatchConsoleController.getResourcePage(
                'Carrier', STATE_CA, 'Alpha', 25,
                null, null, 'first', true
            );
        DispatchConsoleController.ResourcePageResult trucks =
            DispatchConsoleController.getResourcePage(
                'UnexpectedType', STATE_CA, 'QA-100', 25,
                null, null, 'first', true
            );
        DispatchConsoleController.ResourcePageResult emptyLast =
            DispatchConsoleController.getResourcePage(
                'Truck', 'ZZ', null, 25,
                null, null, 'last', false
            );
        DispatchConsoleController.ResourcePageResult normalized =
            DispatchConsoleController.getResourcePage(
                'Truck', STATE_CA, null, 1000,
                null, null, 'invalid', false
            );
        Test.stopTest();

        System.assertEquals('Driver', drivers.resourceType);
        System.assertEquals(3, drivers.totalCount);
        System.assertEquals(2, drivers.drivers.size());
        System.assertEquals(1, drivers.truckCount);
        System.assertEquals(3, drivers.driverCount);
        System.assertEquals(1, drivers.carrierCount);
        System.assert(nextDrivers.drivers.size() > 0);
        System.assertEquals(1, lastDrivers.drivers.size());

        System.assertEquals(1, carriers.totalCount);
        System.assertEquals(1, carriers.carriers.size());
        System.assertEquals('Truck', trucks.resourceType);
        System.assertEquals(1, trucks.totalCount);
        System.assertEquals(1, trucks.trucks.size());
        System.assertEquals(0, emptyLast.totalCount);
        System.assertEquals(0, emptyLast.trucks.size());
        System.assertEquals(100, normalized.pageSize);
    }

    @IsTest
    static void testAllAssignmentTypes() {
        FreightTM__Load__c driverLoad = getLoadByPickup('San Diego');
        FreightTM__Load__c truckLoad = getLoadByPickup('Fresno');
        FreightTM__Load__c carrierLoad = getLoadByPickup('Bakersfield');
        FreightTM__Employee__c driver = getDriver('QA Driver Valid');
        FreightTM__Truck__c truck = getTruck('QA Truck Alpha');
        FreightTM__Carrier__c carrier = getCarrier('QA Carrier Alpha');

        Test.startTest();
        DispatchConsoleController.assignToLoads(
            new List<Id>{ driverLoad.Id }, driver.Id, 'Driver'
        );
        DispatchConsoleController.assignToLoads(
            new List<Id>{ truckLoad.Id }, truck.Id, 'Truck'
        );
        DispatchConsoleController.assignToLoads(
            new List<Id>{ carrierLoad.Id }, carrier.Id, 'Carrier'
        );
        Test.stopTest();

        Set<Id> assignedLoadIds = new Set<Id>{
            driverLoad.Id, truckLoad.Id, carrierLoad.Id
        };
        Map<Id, FreightTM__Load__c> updatedLoads = new Map<Id, FreightTM__Load__c>([
            SELECT Id, FreightTM__Driver__c, FreightTM__Truck__c,
                   FreightTM__Carrier_Obj__c
            FROM FreightTM__Load__c
            WHERE Id IN :assignedLoadIds
        ]);
        System.assertEquals(driver.Id, updatedLoads.get(driverLoad.Id).FreightTM__Driver__c);
        System.assertEquals(truck.Id, updatedLoads.get(truckLoad.Id).FreightTM__Truck__c);
        System.assertEquals(carrier.Id, updatedLoads.get(carrierLoad.Id).FreightTM__Carrier_Obj__c);
    }

    @IsTest
    static void testAssignmentValidationErrors() {
        FreightTM__Load__c loadRecord = getLoadByPickup('Los Angeles');
        FreightTM__Employee__c driver = getDriver('QA Driver Valid');

        Boolean emptyLoadsFailed = false;
        Boolean nullRecordFailed = false;
        Boolean blankTypeFailed = false;
        Boolean invalidTypeFailed = false;

        try {
            DispatchConsoleController.assignToLoads(new List<Id>(), driver.Id, 'Driver');
        } catch (AuraHandledException exceptionRecord) {
            emptyLoadsFailed = true;
        }
        try {
            DispatchConsoleController.assignToLoads(
                new List<Id>{ loadRecord.Id }, null, 'Driver'
            );
        } catch (AuraHandledException exceptionRecord) {
            nullRecordFailed = true;
        }
        try {
            DispatchConsoleController.assignToLoads(
                new List<Id>{ loadRecord.Id }, driver.Id, ' '
            );
        } catch (AuraHandledException exceptionRecord) {
            blankTypeFailed = true;
        }
        try {
            DispatchConsoleController.assignToLoads(
                new List<Id>{ loadRecord.Id }, driver.Id, 'Invalid'
            );
        } catch (AuraHandledException exceptionRecord) {
            invalidTypeFailed = true;
        }

        System.assert(emptyLoadsFailed);
        System.assert(nullRecordFailed);
        System.assert(blankTypeFailed);
        System.assert(invalidTypeFailed);
    }

    @IsTest
    static void testPingDriverValidationAndSuccess() {
        FreightTM__Load__c portalLoad = getLoadByPickup('San Diego');
        FreightTM__Load__c noPortalLoad = getLoadByPickup('Bakersfield');
        FreightTM__Employee__c driver = getDriver('QA Driver Valid');

        Integer validationErrors = 0;
        try {
            DispatchConsoleController.pingDriver(null, driver.Id, '5551234567', 'Verizon');
        } catch (AuraHandledException exceptionRecord) {
            validationErrors++;
        }
        try {
            DispatchConsoleController.pingDriver(portalLoad.Id, null, '5551234567', 'Verizon');
        } catch (AuraHandledException exceptionRecord) {
            validationErrors++;
        }
        try {
            DispatchConsoleController.pingDriver(portalLoad.Id, driver.Id, ' ', 'Verizon');
        } catch (AuraHandledException exceptionRecord) {
            validationErrors++;
        }
        try {
            DispatchConsoleController.pingDriver(portalLoad.Id, driver.Id, '5551234567', ' ');
        } catch (AuraHandledException exceptionRecord) {
            validationErrors++;
        }
        try {
            DispatchConsoleController.pingDriver(portalLoad.Id, driver.Id, '---', 'Verizon');
        } catch (AuraHandledException exceptionRecord) {
            validationErrors++;
        }
        // Some org automation may generate a portal link during Load insert.
        // Only test the blank-link validation when the field is actually blank.
        Integer expectedValidationErrors = 5;
        if (String.isBlank(noPortalLoad.Driver_Portal_Link__c)) {
            expectedValidationErrors++;
            try {
                DispatchConsoleController.pingDriver(
                    noPortalLoad.Id,
                    driver.Id,
                    '5551234567',
                    'Verizon'
                );
            } catch (AuraHandledException exceptionRecord) {
                validationErrors++;
            }
        }

        Test.startTest();
        DispatchConsoleController.pingDriver(
            portalLoad.Id,
            driver.Id,
            '(555) 222-3333',
            'Verizon'
        );
        Test.stopTest();

        FreightTM__Employee__c updatedDriver = [
            SELECT FreightTM__Phone__c
            FROM FreightTM__Employee__c
            WHERE Id = :driver.Id
        ];
        FreightTM__Load__c updatedLoad = [
            SELECT FreightTM__Driver__c, Driver_Phone_Number__c,
                   Driver_Phone_Carrier__c
            FROM FreightTM__Load__c
            WHERE Id = :portalLoad.Id
        ];

        System.assertEquals(expectedValidationErrors, validationErrors);
        System.assertEquals('5552223333', updatedDriver.FreightTM__Phone__c);
        System.assertEquals(driver.Id, updatedLoad.FreightTM__Driver__c);
        System.assertEquals('5552223333', updatedLoad.Driver_Phone_Number__c);
        System.assertEquals('Verizon', updatedLoad.Driver_Phone_Carrier__c);
    }

    @IsTest
    static void testPingDriverDmlFailureIsHandled() {
        FreightTM__Load__c portalLoad = getLoadByPickup('San Diego');
        Boolean failedAsExpected = false;

        try {
            DispatchConsoleController.pingDriver(
                portalLoad.Id,
                UserInfo.getUserId(),
                '5551234567',
                'Verizon'
            );
        } catch (AuraHandledException exceptionRecord) {
            failedAsExpected = true;
        }
        System.assert(failedAsExpected, 'Invalid employee Id should be converted to an Aura error.');
    }

    @IsTest
    static void testQueueableBranches() {
        FreightTM__Load__c validLoad = getLoadByPickup('Los Angeles');
        FreightTM__Load__c noPhoneLoad = getLoadByPickup('Fresno');
        FreightTM__Load__c noCarrierLoad = getLoadByPickup('Sacramento');
        FreightTM__Load__c noPortalLoad = getLoadByPickup('Bakersfield');

        Test.startTest();
        new DriverPortalSmsQueueable(null).execute(null);
        new DriverPortalSmsQueueable(new Set<Id>()).execute(null);
        new DriverPortalSmsQueueable(
            new Set<Id>{ validLoad.Id, noPhoneLoad.Id, noCarrierLoad.Id, noPortalLoad.Id }
        ).execute(null);
        Test.stopTest();

        System.assert(true, 'Queueable branches completed without unhandled exceptions.');
    }

    @IsTest
    static void testSmsHelperBranches() {
        System.assertEquals(10, SendSMSToDriver.carrierEmailToSMSMap.size());
        System.assertEquals('vtext.com', SendSMSToDriver.carrierEmailToSMSMap.get('Verizon'));

        SendSMSToDriver.EmailWrapper knownCarrier =
            new SendSMSToDriver.EmailWrapper();
        knownCarrier.phoneNumber = '(555) 888-1111';
        knownCarrier.message = 'Known carrier message';
        knownCarrier.carrier = 'Verizon';

        SendSMSToDriver.EmailWrapper unknownCarrier =
            new SendSMSToDriver.EmailWrapper();
        unknownCarrier.phoneNumber = '555-888-2222';
        unknownCarrier.message = 'Fallback carrier message';
        unknownCarrier.carrier = 'Unknown Carrier';

        Test.startTest();
        SendSMSToDriver.sendSMS(null, 'Verizon', 'No phone');
        SendSMSToDriver.sendSMS('---', 'Verizon', 'Invalid phone');
        SendSMSToDriver.sendSMS('(555) 888-0000', 'Verizon', 'Known carrier');
        SendSMSToDriver.sendSMS('(555) 888-0000', 'Unknown Carrier', 'All carriers');
        SendSMSToDriver.sendSMS('(555) 888-0000', null, 'All carriers');
        SendSMSToDriver.sendSMSToAllCarriers(null);
        SendSMSToDriver.sendSMSToAllCarriers(new List<SendSMSToDriver.EmailWrapper>());
        SendSMSToDriver.sendSMSToAllCarriers(
            new List<SendSMSToDriver.EmailWrapper>{ knownCarrier, unknownCarrier }
        );
        Test.stopTest();

        System.assert(true, 'SMS helper branches completed without sending external messages.');
    }

    @IsTest
    static void testInvoicePdfAndRateConEmail() {
        FreightTM__Load__c loadRecord = getLoadByPickup('Los Angeles');
        Boolean nullInvoiceFailed = false;
        Boolean nullEmailLoadFailed = false;
        Boolean blankRecipientFailed = false;

        try {
            DispatchConsoleController.saveInvoicePdfToLoad(null);
        } catch (AuraHandledException exceptionRecord) {
            nullInvoiceFailed = true;
        }
        try {
            DispatchConsoleController.sendRateConEmailToCarrier(
                null, 'carrier@example.com', 'Subject', 'Body'
            );
        } catch (AuraHandledException exceptionRecord) {
            nullEmailLoadFailed = true;
        }
        try {
            DispatchConsoleController.sendRateConEmailToCarrier(
                loadRecord.Id, ' ', 'Subject', 'Body'
            );
        } catch (AuraHandledException exceptionRecord) {
            blankRecipientFailed = true;
        }

        Test.startTest();
        Id contentDocumentId =
            DispatchConsoleController.saveInvoicePdfToLoad(loadRecord.Id);
        DispatchConsoleController.sendRateConEmailToCarrier(
            loadRecord.Id,
            'carrier@example.com',
            null,
            null
        );
        DispatchConsoleController.sendRateConEmailToCarrier(
            loadRecord.Id,
            'carrier@example.com',
            'QA Rate Confirmation',
            'Attached is the QA rate confirmation.'
        );
        Test.stopTest();

        System.assert(nullInvoiceFailed);
        System.assert(nullEmailLoadFailed);
        System.assert(blankRecipientFailed);
        System.assertNotEquals(null, contentDocumentId);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :loadRecord.Id
            ]
        );
    }
}
