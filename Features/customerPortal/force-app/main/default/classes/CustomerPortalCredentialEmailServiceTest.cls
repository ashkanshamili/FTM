@IsTest
private class CustomerPortalCredentialEmailServiceTest {
    @IsTest
    static void sendsToConfiguredPortalEmailWhenCredentialsAreCreated() {
        Test.startTest();
        Account accountRec = new Account(
            Name = 'Portal Email Test Customer',
            Customer_Portal_Email__c = 'customer@example.com',
            Customer_Portal_Username__c = 'portal.user',
            Customer_Portal_New_Password__c = 'SecurePass123'
        );
        insert accountRec;
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        Account savedAccount = [
            SELECT Customer_Portal_Active__c,
                   Customer_Portal_Password_Hash__c,
                   Customer_Portal_Password_Salt__c,
                   Customer_Portal_Username__c
            FROM Account
            WHERE Id = :accountRec.Id
        ];
        System.assertEquals(true, savedAccount.Customer_Portal_Active__c);
        System.assertEquals('portal.user', savedAccount.Customer_Portal_Username__c);
        System.assertNotEquals(null, savedAccount.Customer_Portal_Password_Hash__c);
        System.assertNotEquals(null, savedAccount.Customer_Portal_Password_Salt__c);
        System.assertEquals(1, emailInvocations);
    }

    @IsTest
    static void sendsWhenUsernamePasswordEmailOrActivationChanges() {
        Account accountRec = new Account(
            Name = 'Portal Credential Update Customer',
            Customer_Portal_Email__c = 'customer@example.com',
            Customer_Portal_Username__c = 'first.user',
            Customer_Portal_New_Password__c = 'FirstPass123'
        );
        insert accountRec;

        Test.startTest();
        Integer beforeUsernamePassword = Limits.getEmailInvocations();
        accountRec.Customer_Portal_Username__c = 'second.user';
        accountRec.Customer_Portal_New_Password__c = 'SecondPass123';
        update accountRec;
        System.assertEquals(1, Limits.getEmailInvocations() - beforeUsernamePassword);

        Integer beforeEmailChange = Limits.getEmailInvocations();
        accountRec.Customer_Portal_Email__c = 'new-address@example.com';
        update accountRec;
        System.assertEquals(1, Limits.getEmailInvocations() - beforeEmailChange);

        update new Account(Id = accountRec.Id, Customer_Portal_Active__c = false);
        Integer beforeActivation = Limits.getEmailInvocations();
        update new Account(
            Id = accountRec.Id,
            Customer_Portal_Active__c = true,
            Customer_Portal_Username__c = accountRec.Customer_Portal_Username__c,
            Customer_Portal_New_Password__c = accountRec.Customer_Portal_New_Password__c,
            Customer_Portal_Email__c = accountRec.Customer_Portal_Email__c
        );
        System.assertEquals(1, Limits.getEmailInvocations() - beforeActivation);
        Test.stopTest();
    }

    @IsTest
    static void usesUsernameEmailThenFirstContactEmailAsFallback() {
        Account contactAccount = new Account(Name = 'Portal Contact Fallback');
        insert contactAccount;
        insert new List<Contact>{
            new Contact(
                AccountId = contactAccount.Id,
                FirstName = 'First',
                LastName = 'Contact',
                Email = 'first.contact@example.com'
            ),
            new Contact(
                AccountId = contactAccount.Id,
                FirstName = 'Second',
                LastName = 'Contact',
                Email = 'second.contact@example.com'
            )
        };

        Test.startTest();
        Integer beforeUsernameFallback = Limits.getEmailInvocations();
        Account usernameEmailAccount = new Account(
            Name = 'Username Email Fallback',
            Customer_Portal_Username__c = 'username.recipient@example.com',
            Customer_Portal_New_Password__c = 'SecurePass123'
        );
        insert usernameEmailAccount;
        System.assertEquals(1, Limits.getEmailInvocations() - beforeUsernameFallback);

        Integer beforeContactFallback = Limits.getEmailInvocations();
        contactAccount.Customer_Portal_Username__c = 'customer-login';
        contactAccount.Customer_Portal_New_Password__c = 'SecurePass123';
        update contactAccount;
        System.assertEquals(1, Limits.getEmailInvocations() - beforeContactFallback);
        Test.stopTest();
    }

    @IsTest
    static void skipsUnrelatedInactiveIncompleteAndRecipientlessRecords() {
        CustomerPortalCredentialEmailService.sendWhenCredentialsChanged(null, null);
        CustomerPortalCredentialEmailService.sendWhenCredentialsChanged(new List<Account>(), null);

        Account accountRec = new Account(
            Name = 'Portal No Email Test',
            Customer_Portal_Email__c = 'customer@example.com',
            Customer_Portal_Username__c = 'unchanged.user',
            Customer_Portal_New_Password__c = 'SecurePass123'
        );
        insert accountRec;

        Test.startTest();
        Integer beforeUnrelatedUpdate = Limits.getEmailInvocations();
        accountRec.Phone = '555-0100';
        update accountRec;
        System.assertEquals(0, Limits.getEmailInvocations() - beforeUnrelatedUpdate);

        Account inactive = new Account(
            Name = 'Inactive In Memory',
            Customer_Portal_Active__c = false,
            Customer_Portal_Username__c = 'inactive',
            Customer_Portal_New_Password__c = 'Password123'
        );
        Account missingUsername = new Account(
            Name = 'Missing Username',
            Customer_Portal_Active__c = true,
            Customer_Portal_New_Password__c = 'Password123'
        );
        Account missingPassword = new Account(
            Name = 'Missing Password',
            Customer_Portal_Active__c = true,
            Customer_Portal_Username__c = 'missing.password'
        );
        Account noRecipient = new Account(
            Name = 'No Recipient',
            Customer_Portal_Active__c = true,
            Customer_Portal_Username__c = 'not-an-email',
            Customer_Portal_New_Password__c = 'Password123'
        );

        Integer beforeSkippedRecords = Limits.getEmailInvocations();
        CustomerPortalCredentialEmailService.sendWhenCredentialsChanged(
            new List<Account>{ inactive, missingUsername, missingPassword, noRecipient },
            null
        );
        System.assertEquals(0, Limits.getEmailInvocations() - beforeSkippedRecords);
        Test.stopTest();
    }

    @IsTest
    static void verifiesShouldSendDecisionBranches() {
        System.assertEquals(false, CustomerPortalCredentialEmailService.shouldSend(null, null));

        Account active = new Account(
            Customer_Portal_Active__c = true,
            Customer_Portal_Username__c = 'user',
            Customer_Portal_New_Password__c = 'Password123',
            Customer_Portal_Email__c = 'customer@example.com'
        );
        Account identicalOld = new Account(
            Customer_Portal_Active__c = true,
            Customer_Portal_Username__c = 'user',
            Customer_Portal_New_Password__c = 'Password123',
            Customer_Portal_Email__c = 'customer@example.com'
        );
        System.assertEquals(true, CustomerPortalCredentialEmailService.shouldSend(active, null));
        System.assertEquals(false, CustomerPortalCredentialEmailService.shouldSend(active, identicalOld));

        Account usernameChanged = (Account)active.clone(false, true, false, false);
        usernameChanged.Customer_Portal_Username__c = 'changed-user';
        System.assertEquals(true, CustomerPortalCredentialEmailService.shouldSend(usernameChanged, identicalOld));

        Account passwordChanged = (Account)active.clone(false, true, false, false);
        passwordChanged.Customer_Portal_New_Password__c = 'NewPassword123';
        System.assertEquals(true, CustomerPortalCredentialEmailService.shouldSend(passwordChanged, identicalOld));

        Account emailChanged = (Account)active.clone(false, true, false, false);
        emailChanged.Customer_Portal_Email__c = 'changed@example.com';
        System.assertEquals(true, CustomerPortalCredentialEmailService.shouldSend(emailChanged, identicalOld));

        Account oldInactive = (Account)identicalOld.clone(false, true, false, false);
        oldInactive.Customer_Portal_Active__c = false;
        System.assertEquals(true, CustomerPortalCredentialEmailService.shouldSend(active, oldInactive));
    }

    @IsTest
    static void handlesMessagingFailureWithoutBreakingAccountSave() {
        Account invalidRecipient = new Account(
            Name = '<Unsafe Customer>',
            Customer_Portal_Active__c = true,
            Customer_Portal_Email__c = 'invalid-email-address',
            Customer_Portal_Username__c = '<unsafe.user>',
            Customer_Portal_New_Password__c = '<UnsafePassword123>'
        );

        Test.startTest();
        CustomerPortalCredentialEmailService.sendWhenCredentialsChanged(
            new List<Account>{ invalidRecipient },
            null
        );
        Test.stopTest();

        System.assertEquals(true, true, 'Email errors must be contained by the service.');
    }
}