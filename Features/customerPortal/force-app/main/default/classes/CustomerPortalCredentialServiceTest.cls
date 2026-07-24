@IsTest
private class CustomerPortalCredentialServiceTest {
    @IsTest
    static void setsNormalizesHashesAndDeactivatesLogin() {
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Credential Success');

        Test.startTest();
        CustomerPortalCredentialService.setAccountLogin(
            accountRec.Id,
            '  PORTAL.USER@EXAMPLE.COM  ',
            'SecurePass123'
        );
        Test.stopTest();

        Account saved = [
            SELECT Customer_Portal_Username__c,
                   Customer_Portal_Active__c,
                   Customer_Portal_Password_Hash__c,
                   Customer_Portal_Password_Salt__c,
                   Customer_Portal_Password_Set_At__c
            FROM Account
            WHERE Id = :accountRec.Id
        ];
        System.assertEquals('portal.user@example.com', saved.Customer_Portal_Username__c);
        System.assertEquals(true, saved.Customer_Portal_Active__c);
        System.assertNotEquals(null, saved.Customer_Portal_Password_Hash__c);
        System.assertNotEquals(null, saved.Customer_Portal_Password_Salt__c);
        System.assertNotEquals(null, saved.Customer_Portal_Password_Set_At__c);
        System.assertEquals(
            saved.Customer_Portal_Password_Hash__c,
            CustomerPortalCredentialService.hashPassword(saved.Customer_Portal_Password_Salt__c, 'SecurePass123')
        );

        CustomerPortalCredentialService.deactivateAccountLogin(accountRec.Id);
        saved = [SELECT Customer_Portal_Active__c FROM Account WHERE Id = :accountRec.Id];
        System.assertEquals(false, saved.Customer_Portal_Active__c);
    }

    @IsTest
    static void appliesFieldsAndHandlesEmptyInputs() {
        CustomerPortalCredentialService.applyAccountLoginFields(null);
        CustomerPortalCredentialService.applyAccountLoginFields(new List<Account>());

        Account usernameOnly = new Account(
            Name = 'Username Only',
            Customer_Portal_Username__c = '  Mixed.Case.User  '
        );
        Account noPortalFields = new Account(Name = 'No Portal Fields');
        List<Account> records = new List<Account>{ usernameOnly, noPortalFields };

        CustomerPortalCredentialService.applyAccountLoginFields(records);
        System.assertEquals('mixed.case.user', usernameOnly.Customer_Portal_Username__c);
        System.assertEquals(null, usernameOnly.Customer_Portal_Password_Hash__c);

        Account withPassword = new Account(
            Name = 'With Password',
            Customer_Portal_Username__c = ' Test.User ',
            Customer_Portal_New_Password__c = 'Password123'
        );
        CustomerPortalCredentialService.applyAccountLoginFields(new List<Account>{ withPassword });
        System.assertEquals('test.user', withPassword.Customer_Portal_Username__c);
        System.assertEquals(true, withPassword.Customer_Portal_Active__c);
        System.assertNotEquals(null, withPassword.Customer_Portal_Password_Salt__c);
        System.assertNotEquals(null, withPassword.Customer_Portal_Password_Hash__c);
    }

    @IsTest
    static void validatesRequiredFieldsAndPasswordLength() {
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Credential Validation');

        try {
            CustomerPortalCredentialService.setAccountLogin(null, 'user', 'Password123');
            System.assert(false, 'Expected missing Account Id exception.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }

        try {
            CustomerPortalCredentialService.deactivateAccountLogin(null);
            System.assert(false, 'Expected missing Account Id exception.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }

        try {
            CustomerPortalCredentialService.setAccountLogin(accountRec.Id, null, 'Password123');
            System.assert(false, 'Expected missing username exception.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }

        try {
            CustomerPortalCredentialService.setAccountLogin(accountRec.Id, 'user', null);
            System.assert(false, 'Expected missing password exception.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }

        try {
            CustomerPortalCredentialService.setAccountLogin(accountRec.Id, 'user', 'short');
            System.assert(false, 'Expected short password exception.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }

        System.assertEquals(null, CustomerPortalCredentialService.normalizeUsername('   '));
        System.assertEquals('portaluser', CustomerPortalCredentialService.normalizeUsername(' PortalUser '));
        System.assertEquals(null, CustomerPortalCredentialService.hashPassword(null, 'Password123'));
        System.assertEquals(null, CustomerPortalCredentialService.hashPassword('salt', null));
        System.assertNotEquals(null, CustomerPortalCredentialService.hashPassword('salt', 'Password123'));
    }
}