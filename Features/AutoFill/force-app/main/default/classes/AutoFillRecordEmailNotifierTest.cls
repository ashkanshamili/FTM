@IsTest
private class AutoFillRecordEmailNotifierTest {

    private static void createEmailSetting(String emailAddress) {
        Id organizationId = UserInfo.getOrganizationId();
        List<EmailAddressEmailExtractor__c> existingSettings = [
            SELECT Id, SetupOwnerId, Email_Add__c
            FROM EmailAddressEmailExtractor__c
            WHERE SetupOwnerId = :organizationId
            LIMIT 1
        ];

        EmailAddressEmailExtractor__c setting =
            existingSettings.isEmpty()
            ? new EmailAddressEmailExtractor__c(
                SetupOwnerId = organizationId
            )
            : existingSettings[0];

        setting.Email_Add__c = emailAddress;

        if (setting.Id == null) {
            insert setting;
        } else {
            update setting;
        }
    }


    private static String getWebhookSourceValue() {
        Schema.DescribeFieldResult sourceField =
            FreightTM__Load__c.SObjectType.getDescribe()
                .fields.getMap().get('AutoFill_Source__c').getDescribe();

        if (!sourceField.isRestrictedPicklist()) {
            return 'Email';
        }

        String firstActiveValue;

        for (Schema.PicklistEntry entry : sourceField.getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }

            if (firstActiveValue == null) {
                firstActiveValue = entry.getValue();
            }

            String normalized = (
                String.valueOf(entry.getValue()) +
                String.valueOf(entry.getLabel())
            ).toLowerCase().replaceAll('[^a-z0-9]', '');

            if (normalized.contains('email') || normalized.contains('webhook')) {
                return entry.getValue();
            }
        }

        return firstActiveValue;
    }

    private static FreightTM__Load__c createLoad(String source) {
        FreightLoadSyncHandler.bypassForTests = true;
        Test.setMock(
            HttpCalloutMock.class,
            new AutoFillTestCalloutMock()
        );

        Account customer = new Account(
            Name = 'AutoFill Notifier Customer ' + System.now().getTime()
        );
        insert customer;

        FreightTM__Load__c loadRecord = new FreightTM__Load__c(
            FreightTM__Customer__c = customer.Id,
            FreightTM__Pickup_City__c = 'Atlanta',
            FreightTM__Delivery_City__c = 'Chicago',
            FreightTM__Pickup_Date__c = Date.today(),
            FreightTM__Delivery_Date__c = Date.today().addDays(1),
            FreightTM__Pickup_Zip_Code__c = '30301',
            FreightTM__Delivery_Zip_Code__c = '60601',
            FreightTM__Pickup_State__c = 'GA',
            FreightTM__Delivery_State__c = 'IL',
            FreightTM__Pickup_Country__c = 'United States',
            FreightTM__Delivery_Country__c = 'United States',
            FreightTM__Status__c = 'Assigned'
        );

        Map<String, Schema.SObjectField> fields =
            FreightTM__Load__c.SObjectType.getDescribe().fields.getMap();

        System.assert(
            fields.containsKey('AutoFill_Source__c'),
            'AutoFill_Source__c must exist for webhook notification tests.'
        );

        String storedSource = AutoFillRecordEmailNotifier.isWebhookSource(source)
            ? getWebhookSourceValue()
            : source;
        loadRecord.put('AutoFill_Source__c', storedSource);

        if (fields.containsKey('AutoFill_Status__c')) {
            loadRecord.put('AutoFill_Status__c', 'Draft');
        }

        AutoFillSafeDml.insertRecord(loadRecord);
        return loadRecord;
    }

    @IsTest
    static void sourceDetection_acceptsWebhookVariants() {
        System.assertEquals(
            true,
            AutoFillRecordEmailNotifier.isWebhookSource('Email')
        );
        System.assertEquals(
            true,
            AutoFillRecordEmailNotifier.isWebhookSource(
                'Email Webhook'
            )
        );
        System.assertEquals(
            true,
            AutoFillRecordEmailNotifier.isWebhookSource('webhook')
        );
        System.assertEquals(
            true,
            AutoFillRecordEmailNotifier.isWebhookSource('Email To Load')
        );
        System.assertEquals(
            false,
            AutoFillRecordEmailNotifier.isWebhookSource(
                'Manual Upload'
            )
        );
        System.assertEquals(
            false,
            AutoFillRecordEmailNotifier.isWebhookSource(null)
        );
    }

    @IsTest
    static void execute_skipsWhenRecordIdIsNull() {
        AutoFillRecordEmailNotifier notifier =
            new AutoFillRecordEmailNotifier(null);

        Test.startTest();
        notifier.execute(null);
        Test.stopTest();

        System.assertEquals(0, Limits.getEmailInvocations());
    }

    @IsTest
    static void execute_skipsWhenEmailToLoadIsNotConfigured() {
        FreightTM__Load__c loadRecord = createLoad('Webhook');

        AutoFillRecordEmailNotifier notifier =
            new AutoFillRecordEmailNotifier(loadRecord.Id);

        Test.startTest();
        notifier.execute(null);
        Test.stopTest();

        System.assertEquals(0, Limits.getEmailInvocations());
    }

    @IsTest
    static void execute_sendsConfirmationForWebhookLoad() {
        createEmailSetting('email-to-load@example.com');
        FreightTM__Load__c loadRecord = createLoad('Webhook');

        AutoFillRecordEmailNotifier notifier =
            new AutoFillRecordEmailNotifier(loadRecord.Id);

        Test.startTest();
        notifier.execute(null);
        System.assertEquals(
            1,
            Limits.getEmailInvocations(),
            'A webhook-created Load should send one confirmation email.'
        );
        Test.stopTest();
    }

    @IsTest
    static void execute_skipsManualUploadLoad() {
        createEmailSetting('email-to-load@example.com');
        FreightTM__Load__c loadRecord = createLoad('Manual Upload');

        AutoFillRecordEmailNotifier notifier =
            new AutoFillRecordEmailNotifier(loadRecord.Id);

        Test.startTest();
        notifier.execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            Limits.getEmailInvocations(),
            'A Manual Upload Load must not send the webhook confirmation.'
        );
    }

    @IsTest
    static void execute_skipsNonLoadRecord() {
        createEmailSetting('email-to-load@example.com');
        Account accountRecord = new Account(Name = 'Not a Load');
        insert accountRecord;

        AutoFillRecordEmailNotifier notifier =
            new AutoFillRecordEmailNotifier(accountRecord.Id);

        Test.startTest();
        notifier.execute(null);
        Test.stopTest();

        System.assertEquals(0, Limits.getEmailInvocations());
    }

    @IsTest
    static void notifier_canRunAsQueueableForWebhookLoad() {
        createEmailSetting('email-to-load@example.com');
        FreightTM__Load__c loadRecord = createLoad('Webhook');

        Test.startTest();
        Id jobId = System.enqueueJob(
            new AutoFillRecordEmailNotifier(loadRecord.Id)
        );
        System.assertNotEquals(null, jobId);
        Test.stopTest();

        AsyncApexJob completedJob = [
            SELECT Id, Status, JobType, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];

        System.assertEquals('Completed', completedJob.Status);
        System.assertEquals(0, completedJob.NumberOfErrors);
    }

    @IsTest
    static void emailErrorFormatterHandlesSuccessfulResult() {
        Messaging.SingleEmailMessage message =
            new Messaging.SingleEmailMessage();
        message.setToAddresses(
            new List<String>{ 'coverage@example.com' }
        );
        message.setSubject('AutoFill notifier coverage');
        message.setPlainTextBody('Coverage');
        message.setSaveAsActivity(false);

        Messaging.SendEmailResult[] results = Messaging.sendEmail(
            new List<Messaging.SingleEmailMessage>{ message }
        );

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].isSuccess());
        System.assertEquals(
            '',
            AutoFillRecordEmailNotifier.getEmailErrors(results[0])
        );
    }

    @IsTest
    static void execute_skipsDeletedLoadAndNullTextSource() {
        System.assertEquals(
            false,
            AutoFillRecordEmailNotifier.isWebhookSource('null')
        );

        FreightTM__Load__c loadRecord = createLoad('Email');
        delete loadRecord;

        Test.startTest();
        new AutoFillRecordEmailNotifier(loadRecord.Id).execute(null);
        Test.stopTest();

        System.assertEquals(0, Limits.getEmailInvocations());
    }
    @IsTest
    static void execute_usesRecordIdWhenLoadNameIsForcedBlank() {
        createEmailSetting('email-to-load@example.com');
        FreightTM__Load__c loadRecord = createLoad('Email');
        AutoFillRecordEmailNotifier.forceBlankLoadNameForTests = true;

        Test.startTest();
        new AutoFillRecordEmailNotifier(loadRecord.Id).execute(null);
        System.assertEquals(
            String.valueOf(loadRecord.Id),
            AutoFillRecordEmailNotifier.lastResolvedLoadNameForTests
        );
        Test.stopTest();
    }

    @IsTest
    static void execute_handlesEmptyEmailResult() {
        createEmailSetting('email-to-load@example.com');
        FreightTM__Load__c loadRecord = createLoad('Email');
        AutoFillRecordEmailNotifier.forceEmptyEmailResultForTests = true;

        Test.startTest();
        new AutoFillRecordEmailNotifier(loadRecord.Id).execute(null);
        System.assertEquals(0, Limits.getEmailInvocations());
        Test.stopTest();
    }

    @IsTest
    static void execute_handlesEmailException() {
        createEmailSetting('email-to-load@example.com');
        FreightTM__Load__c loadRecord = createLoad('Email');
        AutoFillRecordEmailNotifier.forceEmailExceptionForTests = true;

        Test.startTest();
        new AutoFillRecordEmailNotifier(loadRecord.Id).execute(null);
        System.assertEquals(0, Limits.getEmailInvocations());
        Test.stopTest();
    }

}