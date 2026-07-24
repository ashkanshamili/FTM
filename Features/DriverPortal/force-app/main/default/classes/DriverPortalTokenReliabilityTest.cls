@IsTest
private class DriverPortalTokenReliabilityTest {
    private static FreightTM__Employee__c createDriver() {
        FreightTM__Employee__c driver =
            new FreightTM__Employee__c(
                Name = 'Token Reliability Driver',
                FreightTM__Email__c =
                    'token-driver@example.com',
                FreightTM__Phone__c = '5551234567'
            );
        insert driver;
        return driver;
    }

    private static FreightTM__Load__c createLoad() {
        FreightTM__Employee__c driver = createDriver();

        FreightTM__Load__c loadRecord =
            new FreightTM__Load__c(
                FreightTM__Status__c = 'Assigned',
                FreightTM__Driver__c = driver.Id
            );
        insert loadRecord;
        return loadRecord;
    }

    private static String rawToken(String urlValue) {
        System.assertNotEquals(null, urlValue);
        System.assert(urlValue.contains('?t='));
        return urlValue.substringAfter('?t=');
    }

    @IsTest
    static void idBoundTokenMatchesPersistedHash() {
        FreightTM__Load__c loadRecord = createLoad();

        Test.startTest();
        DriverLoadPortalTokenService.LinkResult result =
            DriverLoadPortalTokenService.generateLink(
                loadRecord.Id,
                'https://example.my.site.com/DriverPortal'
            );
        Test.stopTest();

        String token = rawToken(result.url);

        System.assert(
            token.startsWith(String.valueOf(loadRecord.Id) + '.'),
            'V2.1 tokens must carry the Load Id.'
        );

        FreightTM__Load__c persisted = [
            SELECT Driver_Portal_Token_Hash__c,
                   Driver_Portal_Link__c
            FROM FreightTM__Load__c
            WHERE Id = :loadRecord.Id
        ];

        System.assertEquals(
            DriverLoadPortalTokenService.hashToken(token),
            persisted.Driver_Portal_Token_Hash__c,
            'The URL token and persisted hash must match exactly.'
        );
        System.assertEquals(
            persisted.Driver_Portal_Link__c,
            result.url,
            'The service must return the final persisted URL.'
        );

        FreightTM__Load__c validated =
            DriverLoadPortalTokenService.validateToken(token);

        System.assertEquals(loadRecord.Id, validated.Id);
    }

    @IsTest
    static void tamperedTokenIsRejected() {
        FreightTM__Load__c loadRecord = createLoad();

        DriverLoadPortalTokenService.LinkResult result =
            DriverLoadPortalTokenService.generateLink(
                loadRecord.Id,
                'https://example.my.site.com/DriverPortal'
            );

        String token = rawToken(result.url);
        String tampered = token + 'x';
        Boolean rejected = false;

        Test.startTest();
        try {
            DriverLoadPortalTokenService.validateToken(tampered);
        } catch (AuraHandledException errorValue) {
            rejected =
                errorValue.getMessage().contains(
                    'Invalid portal link.'
                );
        }
        Test.stopTest();

        System.assertEquals(true, rejected);
    }

    @IsTest
    static void legacyTokenStillWorks() {
        FreightTM__Load__c loadRecord = createLoad();
        String legacyToken = 'legacy-token-123';

        update new FreightTM__Load__c(
            Id = loadRecord.Id,
            Driver_Portal_Token_Hash__c =
                DriverLoadPortalTokenService.hashToken(
                    legacyToken
                ),
            Driver_Portal_Active__c = true,
            Driver_Portal_Expires_At__c =
                System.now().addDays(1)
        );

        Test.startTest();
        FreightTM__Load__c validated =
            DriverLoadPortalTokenService.validateToken(
                legacyToken
            );
        Test.stopTest();

        System.assertEquals(loadRecord.Id, validated.Id);
    }
}
