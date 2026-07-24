@IsTest
private class CustomerPortalTokenServiceTest {
    @IsTest
    static void generatesAndValidatesPortalLinks() {
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Token Link');
        Contact contactRec = CustomerPortalTestDataFactory.createContact(accountRec.Id, 'tokenlink');

        Test.startTest();
        CustomerPortalTokenService.LinkResult result = CustomerPortalTokenService.generateLink(
            accountRec.Id,
            contactRec.Id,
            '  https://example.com/CustomerPortal///  ',
            5
        );
        Test.stopTest();

        System.assertNotEquals(null, result.sessionId);
        System.assertNotEquals(null, result.rawToken);
        System.assert(result.url.startsWith('https://example.com/CustomerPortal?t='));
        System.assertEquals(false, result.url.contains('CustomerPortal/?t='));

        Customer_Portal_Session__c sessionRec = CustomerPortalTokenService.validateToken(result.rawToken);
        System.assertEquals(accountRec.Id, sessionRec.Account__c);
        System.assertEquals(contactRec.Id, sessionRec.Contact__c);
        System.assertEquals(true, sessionRec.Active__c);
        System.assertEquals(CustomerPortalTokenService.hashToken(result.rawToken), sessionRec.Token_Hash__c);

        CustomerPortalTokenService.LinkResult defaultDays = CustomerPortalTokenService.generateLink(
            accountRec.Id,
            null,
            'https://example.com/CustomerPortal/',
            0
        );
        Customer_Portal_Session__c defaultSession = [
            SELECT Expires_At__c
            FROM Customer_Portal_Session__c
            WHERE Id = :defaultDays.sessionId
        ];
        System.assert(defaultSession.Expires_At__c > System.now().addDays(29));
    }

    @IsTest
    static void rejectsInvalidLinkGenerationInputs() {
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Token Input');

        try {
            CustomerPortalTokenService.generateLink(null, null, 'https://example.com', 1);
            System.assert(false, 'Expected Account Id validation.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }

        try {
            CustomerPortalTokenService.generateLink(accountRec.Id, null, '   ', 1);
            System.assert(false, 'Expected base URL validation.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }
    }

    @IsTest
    static void rejectsBlankUnknownInactiveExpiredAndUnownedTokens() {
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Token Validation');

        try {
            CustomerPortalTokenService.validateToken(null);
            System.assert(false, 'Expected blank token validation.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }

        try {
            CustomerPortalTokenService.validateToken('unknown-token');
            System.assert(false, 'Expected unknown token validation.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }

        String inactive = CustomerPortalTestDataFactory.createSession(
            accountRec.Id, null, false, System.now().addDays(1), 'inactive'
        );
        try {
            CustomerPortalTokenService.validateToken(inactive);
            System.assert(false, 'Expected inactive token validation.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }

        String expired = CustomerPortalTestDataFactory.createSession(
            accountRec.Id, null, true, System.now().addMinutes(-5), 'expired'
        );
        try {
            CustomerPortalTokenService.validateToken(expired);
            System.assert(false, 'Expected expired token validation.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }

        String noAccountToken = 'no-account-token';
        insert new Customer_Portal_Session__c(
            Token_Hash__c = CustomerPortalTokenService.hashToken(noAccountToken),
            Active__c = true,
            Expires_At__c = System.now().addDays(1)
        );
        try {
            CustomerPortalTokenService.validateToken(noAccountToken);
            System.assert(false, 'Expected missing Account validation.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }
    }
}