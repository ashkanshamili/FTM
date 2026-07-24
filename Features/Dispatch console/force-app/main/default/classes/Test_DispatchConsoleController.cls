@IsTest
private class Test_DispatchConsoleController {
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody(
                '{"access_token":"test-access-token",' +
                '"token_type":"Bearer","expires_in":3600}'
            );
            return response;
        }
    }

    @TestSetup
    static void setupData() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        FreightTM__Carrier__c carrier = new FreightTM__Carrier__c(
            Name = 'Test Carrier',
            FreightTM__Email__c = 'carrier@example.com',
            FreightTM__Phone__c = '555-111-2222',
            FreightTM__Billing_State_Province__c = 'CA',
            FreightTM__State_Province__c = 'CA',
            FreightTM__Billing_City__c = 'Los Angeles',
            FreightTM__Billing_Zip_Code__c = '90001',
            FreightTM__Billing_Country__c = 'United States'
        );
        insert carrier;

        FreightTM__Employee__c driver = new FreightTM__Employee__c(
            Name = 'Driver Test',
            FreightTM__First_Name__c = 'John',
            FreightTM__Email__c = 'driver@example.com',
            FreightTM__Phone__c = '555-333-4444',
            FreightTM__State__c = 'CA',
            FreightTM__City__c = 'Los Angeles',
            Status__c = 'Available'
        );
        insert driver;

        FreightTM__Truck__c truck = new FreightTM__Truck__c(
            Name = 'Truck Test',
            State_Province__c = 'CA',
            FreightTM__License_Plate_State__c = 'CA',
            FreightTM__License_Plate__c = 'TEST123',
            FreightTM__Status__c = 'Empty'
        );
        insert truck;

        List<FreightTM__Load__c> loads = new List<FreightTM__Load__c>();
        for (Integer indexValue = 0; indexValue < 3; indexValue++) {
            loads.add(new FreightTM__Load__c(
                FreightTM__Pickup_Address__c = indexValue + '00 Pickup St',
                FreightTM__Pickup_City__c = 'Los Angeles',
                FreightTM__Pickup_State__c = 'CA',
                FreightTM__Pickup_Zip_Code__c = '9000' + indexValue,
                FreightTM__Pickup_Country__c = 'United States',
                FreightTM__Delivery_Address__c = indexValue + '00 Delivery St',
                FreightTM__Delivery_City__c = 'Phoenix',
                FreightTM__Delivery_State__c = 'AZ',
                FreightTM__Delivery_Zip_Code__c = '8500' + indexValue,
                FreightTM__Delivery_Country__c = 'United States',
                FreightTM__Status__c = indexValue == 1 ? 'On Hold' : 'Assigned',
                FreightTM__Pickup_Date__c = Date.today().addDays(indexValue),
                FreightTM__Delivery_Date__c = Date.today().addDays(indexValue + 2),
                FreightTM__Carrier_Obj__c = indexValue == 2 ? null : carrier.Id,
                FreightTM__Invoice_Status__c = indexValue == 0 ? 'Ready to Invoice' : null,
                FreightTM__Rate__c = 1000,
                FreightTM__Rate_to_Carrier__c = indexValue == 1 ? 900 : 750,
                POD_Received__c = indexValue == 0,
                FreightTM__Bill_Status__c = indexValue == 0
                    ? 'Bill/POD Received'
                    : 'Bill/POD Needed',
                Exception_Reason__c = indexValue == 1 ? 'Late pickup' : null
            ));
        }
        insert loads;
    }

    @IsTest
    static void testLoadPageFirstAndNext() {
        Test.startTest();
        DispatchConsoleController.LoadPageResult firstPage =
            DispatchConsoleController.getLoadPage(
                'loadBoard', 'CA', '', 'all', 'All', 1,
                null, null, 'first', true
            );
        FreightTM__Load__c cursor = firstPage.records[0];
        DispatchConsoleController.LoadPageResult nextPage =
            DispatchConsoleController.getLoadPage(
                'loadBoard', 'CA', '', 'all', 'All', 1,
                cursor.CreatedDate, cursor.Id, 'next', false
            );
        Test.stopTest();

        System.assertEquals(3, firstPage.totalCount);
        System.assertEquals(1, firstPage.records.size());
        System.assertNotEquals(null, firstPage.summary);
        System.assertEquals(3, firstPage.summary.totalLoads);

        System.assertEquals(1, nextPage.records.size());
        System.assertNotEquals(cursor.Id, nextPage.records[0].Id);
        System.assertEquals(null, nextPage.summary);
    }


    @IsTest
    static void testLastPageUsesRemainderAndPreviousWorks() {
        Test.startTest();
        DispatchConsoleController.LoadPageResult lastPage =
            DispatchConsoleController.getLoadPage(
                'loadBoard', 'CA', '', 'all', 'All', 2,
                null, null, 'last', false
            );
        FreightTM__Load__c cursor = lastPage.records[0];
        DispatchConsoleController.LoadPageResult previousPage =
            DispatchConsoleController.getLoadPage(
                'loadBoard', 'CA', '', 'all', 'All', 2,
                cursor.CreatedDate, cursor.Id, 'previous', false
            );
        Test.stopTest();

        System.assertEquals(3, lastPage.totalCount);
        System.assertEquals(1, lastPage.records.size(),
            'The last page should contain only the remainder.');
        System.assertEquals(2, previousPage.records.size());
    }

    @IsTest
    static void testLoadFilters() {
        Test.startTest();
        DispatchConsoleController.LoadPageResult exceptions =
            DispatchConsoleController.getLoadPage(
                'loadBoard', 'CA', '', 'exceptions', 'All', 25,
                null, null, 'first', false
            );
        DispatchConsoleController.LoadPageResult zipSearch =
            DispatchConsoleController.getLoadPage(
                'assignment', 'CA', '900', 'all', 'All', 25,
                null, null, 'first', false
            );
        DispatchConsoleController.LoadPageResult lowMargin =
            DispatchConsoleController.getLoadPage(
                'margin', 'CA', '', 'lowMargin', 'All', 25,
                null, null, 'first', false
            );
        Test.stopTest();

        System.assertEquals(1, exceptions.totalCount);
        System.assertEquals(3, zipSearch.totalCount);
        System.assertEquals(1, lowMargin.totalCount);
    }

    @IsTest
    static void testResourcePages() {
        Test.startTest();
        DispatchConsoleController.ResourcePageResult trucks =
            DispatchConsoleController.getResourcePage(
                'Truck', 'CA', '', 25, null, null, 'first', true
            );
        DispatchConsoleController.ResourcePageResult drivers =
            DispatchConsoleController.getResourcePage(
                'Driver', 'CA', '', 25, null, null, 'first', true
            );
        DispatchConsoleController.ResourcePageResult carriers =
            DispatchConsoleController.getResourcePage(
                'Carrier', 'CA', '', 25, null, null, 'first', true
            );
        Test.stopTest();

        System.assertEquals(1, trucks.totalCount);
        System.assertEquals(1, trucks.trucks.size());
        System.assertEquals(1, drivers.totalCount);
        System.assertEquals(1, drivers.drivers.size());
        System.assertEquals(1, carriers.totalCount);
        System.assertEquals(1, carriers.carriers.size());
        System.assertEquals(1, carriers.truckCount);
        System.assertEquals(1, carriers.driverCount);
        System.assertEquals(1, carriers.carrierCount);
    }

    @IsTest
    static void testAssignToLoads() {
        FreightTM__Load__c loadRecord = [
            SELECT Id FROM FreightTM__Load__c LIMIT 1
        ];
        FreightTM__Employee__c driver = [
            SELECT Id FROM FreightTM__Employee__c LIMIT 1
        ];

        Test.startTest();
        DispatchConsoleController.assignToLoads(
            new List<Id>{ loadRecord.Id }, driver.Id, 'Driver'
        );
        Test.stopTest();

        FreightTM__Load__c updatedLoad = [
            SELECT FreightTM__Driver__c
            FROM FreightTM__Load__c
            WHERE Id = :loadRecord.Id
        ];
        System.assertEquals(driver.Id, updatedLoad.FreightTM__Driver__c);
    }

    @IsTest
    static void testAssignmentValidation() {
        Boolean errorThrown = false;
        try {
            DispatchConsoleController.assignToLoads(
                new List<Id>(), UserInfo.getUserId(), 'Driver'
            );
        } catch (AuraHandledException exceptionRecord) {
            errorThrown = true;
        }
        System.assertEquals(true, errorThrown);
    }

    @IsTest
    static void testBackwardCompatibleDispatchData() {
        Test.startTest();
        DispatchConsoleController.DispatchData result =
            DispatchConsoleController.getDispatchData('CA');
        Test.stopTest();

        System.assert(result.loads.size() > 0);
        System.assert(result.trucks.size() > 0);
        System.assert(result.drivers.size() > 0);
        System.assert(result.carriers.size() > 0);
        System.assert(result.loads.size() <= 25);
    }

    @IsTest
    static void testInvoicePdfAndRateConEmail() {
        FreightTM__Load__c loadRecord = [
            SELECT Id
            FROM FreightTM__Load__c
            LIMIT 1
        ];

        Test.startTest();
        Id contentDocumentId =
            DispatchConsoleController.saveInvoicePdfToLoad(loadRecord.Id);

        DispatchConsoleController.sendRateConEmailToCarrier(
            loadRecord.Id,
            'carrier@example.com',
            'Test Rate Confirmation',
            'Please find the document attached.'
        );
        Test.stopTest();

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