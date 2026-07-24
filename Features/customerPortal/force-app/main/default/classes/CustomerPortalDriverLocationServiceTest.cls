@IsTest
private class CustomerPortalDriverLocationServiceTest {
    @IsTest
    static void appliesAndNormalizesDriverLocations() {
        CustomerPortalTestDataFactory.registerFreightGraphCalloutMock();
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Driver Apply');
        FreightTM__Load__c loadRec = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Assigned', 1500, 'DRIVER-APPLY'
        );

        CustomerPortalDriverLocationService.applyLocation(
            loadRec.Id,
            29.7604,
            -95.3698,
            CustomerPortalTestDataFactory.longText(300),
            -10
        );
        FreightTM__Load__c saved = [
            SELECT Driver_Current_Latitude__c,
                   Driver_Current_Longitude__c,
                   Driver_Current_Location_Text__c,
                   Driver_Last_GPS_Update__c,
                   Route_Progress_Percent__c,
                   Customer_Visible_Tracking__c,
                   Tracking_Map_Enabled__c
            FROM FreightTM__Load__c
            WHERE Id = :loadRec.Id
        ];
        System.assertEquals(29.7604, saved.Driver_Current_Latitude__c);
        System.assertEquals(-95.3698, saved.Driver_Current_Longitude__c);
        System.assertEquals(255, saved.Driver_Current_Location_Text__c.length());
        System.assertEquals(0, saved.Route_Progress_Percent__c);
        System.assertEquals(true, saved.Customer_Visible_Tracking__c);
        System.assertEquals(true, saved.Tracking_Map_Enabled__c);
        System.assertNotEquals(null, saved.Driver_Last_GPS_Update__c);

        CustomerPortalDriverLocationService.applyLocation(loadRec.Id, 30, -96, null, 150);
        saved = [
            SELECT Driver_Current_Location_Text__c, Route_Progress_Percent__c
            FROM FreightTM__Load__c
            WHERE Id = :loadRec.Id
        ];
        System.assertEquals(null, saved.Driver_Current_Location_Text__c);
        System.assertEquals(100, saved.Route_Progress_Percent__c);

        CustomerPortalDriverLocationService.applyLocation(loadRec.Id, 31, -97, 'Dallas', null);
        saved = [SELECT Route_Progress_Percent__c FROM FreightTM__Load__c WHERE Id = :loadRec.Id];
        System.assertEquals(null, saved.Route_Progress_Percent__c);
    }

    @IsTest
    static void updatesLocationWithValidDriverPortalToken() {
        CustomerPortalTestDataFactory.registerFreightGraphCalloutMock();
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Driver Token');
        FreightTM__Load__c loadRec = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Assigned', 1800, 'DRIVER-TOKEN'
        );
        String rawToken = 'driver-portal-raw-token';
        update new FreightTM__Load__c(
            Id = loadRec.Id,
            Driver_Portal_Active__c = true,
            Driver_Portal_Expires_At__c = System.now().addDays(1),
            Driver_Portal_Token_Hash__c = CustomerPortalTokenService.hashToken(rawToken)
        );

        Test.startTest();
        CustomerPortalDriverLocationService.LocationUpdateResult result =
            CustomerPortalDriverLocationService.updateDriverLocation(
                rawToken,
                String.valueOf(loadRec.Id),
                33.4484,
                -112.0740,
                'Phoenix, AZ',
                45.678
            );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('Driver location updated.', result.message);
        System.assertEquals(loadRec.Id, result.loadId);
        System.assertNotEquals(null, result.updatedAt);

        FreightTM__Load__c saved = [
            SELECT Driver_Current_Location_Text__c, Route_Progress_Percent__c
            FROM FreightTM__Load__c
            WHERE Id = :loadRec.Id
        ];
        System.assertEquals('Phoenix, AZ', saved.Driver_Current_Location_Text__c);
        System.assertEquals(45.68, saved.Route_Progress_Percent__c);
    }

    @IsTest
    static void validatesDriverLocationInputsAndAccess() {
        CustomerPortalTestDataFactory.registerFreightGraphCalloutMock();
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Driver Validation');
        FreightTM__Load__c inactiveLoad = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Assigned', 1000, 'DRIVER-INACTIVE'
        );
        FreightTM__Load__c expiredLoad = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Assigned', 1100, 'DRIVER-EXPIRED'
        );
        FreightTM__Load__c tokenLoad = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Assigned', 1200, 'DRIVER-BAD-TOKEN'
        );
        String validToken = 'valid-driver-token';
        update new FreightTM__Load__c(
            Id = expiredLoad.Id,
            Driver_Portal_Active__c = true,
            Driver_Portal_Expires_At__c = System.now().addMinutes(-1),
            Driver_Portal_Token_Hash__c = CustomerPortalTokenService.hashToken(validToken)
        );
        update new FreightTM__Load__c(
            Id = tokenLoad.Id,
            Driver_Portal_Active__c = true,
            Driver_Portal_Expires_At__c = System.now().addDays(1),
            Driver_Portal_Token_Hash__c = CustomerPortalTokenService.hashToken(validToken)
        );

        assertUpdateFails(null, 'bad-token', 1, 1);
        assertUpdateFails('not-an-id', 'bad-token', 1, 1);
        assertUpdateFails(String.valueOf(tokenLoad.Id), null, 1, 1);
        assertUpdateFails(String.valueOf(tokenLoad.Id), validToken, null, 1);
        assertUpdateFails(String.valueOf(tokenLoad.Id), validToken, 91, 1);
        assertUpdateFails(String.valueOf(tokenLoad.Id), validToken, -91, 1);
        assertUpdateFails(String.valueOf(tokenLoad.Id), validToken, 1, 181);
        assertUpdateFails(String.valueOf(tokenLoad.Id), validToken, 1, -181);
        assertUpdateFails(String.valueOf(inactiveLoad.Id), validToken, 1, 1);
        assertUpdateFails(String.valueOf(expiredLoad.Id), validToken, 1, 1);
        assertUpdateFails(String.valueOf(tokenLoad.Id), 'incorrect-token', 1, 1);
    }

    private static void assertUpdateFails(
        String loadId,
        String token,
        Decimal latitude,
        Decimal longitude
    ) {
        try {
            CustomerPortalDriverLocationService.updateDriverLocation(
                token, loadId, latitude, longitude, 'Test', 50
            );
            System.assert(false, 'Expected driver location validation to fail.');
        } catch (Exception expected) {
            System.assert(true);
        }
    }
}