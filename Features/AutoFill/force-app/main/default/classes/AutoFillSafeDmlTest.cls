@IsTest
private class AutoFillSafeDmlTest {

    private static FreightTM__Load__c buildLoad(String autoFillSource) {
        FreightTM__Load__c loadRecord = new FreightTM__Load__c(
            FreightTM__Pickup_Zip_Code__c = '30301',
            FreightTM__Delivery_Zip_Code__c = '60601',
            FreightTM__Pickup_State__c = 'GA',
            FreightTM__Delivery_State__c = 'IL',
            FreightTM__Pickup_Country__c = 'United States',
            FreightTM__Delivery_Country__c = 'United States',
            FreightTM__Required_Trailer__c = 'Van',
            FreightTM__Status__c = 'Assigned'
        );
        loadRecord.put('AutoFill_Source__c', autoFillSource);
        return loadRecord;
    }

    private static String repeatValue(String value, Integer count) {
        String result = '';
        for (Integer index = 0; index < count; index++) {
            result += value;
        }
        return result;
    }

    private static Schema.DescribeFieldResult sourceDescribe() {
        return FreightTM__Load__c.SObjectType
            .getDescribe()
            .fields
            .getMap()
            .get('AutoFill_Source__c')
            .getDescribe();
    }

    private static String firstActiveValue(
        Schema.DescribeFieldResult fieldDescribe
    ) {
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    @IsTest
    static void insertRecord_insertsValidRecord() {
        Account accountRecord = new Account(
            Name = 'AutoFill Safe DML Account'
        );

        Test.startTest();
        AutoFillSafeDml.insertRecord(accountRecord);
        Test.stopTest();

        System.assertNotEquals(null, accountRecord.Id);
    }

    @IsTest
    static void insertRecord_skipsOversizedOptionalTextField() {
        Account accountRecord = new Account(
            Name = 'AutoFill Oversized Field Account',
            Phone = repeatValue('1', 80)
        );

        Test.startTest();
        AutoFillSafeDml.insertRecord(accountRecord);
        Test.stopTest();

        Account storedAccount = [
            SELECT Id, Phone
            FROM Account
            WHERE Id = :accountRecord.Id
        ];

        System.assertNotEquals(null, storedAccount.Id);
        System.assertEquals(null, storedAccount.Phone);
    }

    @IsTest
    static void correctStringTooLongFields_clearsAndHandlesOnlyOnce() {
        Account accountRecord = new Account(
            Name = 'AutoFill Direct DML Error Account',
            Phone = repeatValue('2', 80)
        );
        DmlException capturedError;

        try {
            insert accountRecord;
        } catch (DmlException expectedException) {
            capturedError = expectedException;
        }

        System.assertNotEquals(null, capturedError);

        Set<String> handledValues = new Set<String>();
        Boolean firstCorrection =
            AutoFillSafeDml.correctStringTooLongFields(
                accountRecord,
                capturedError,
                handledValues
            );
        Boolean secondCorrection =
            AutoFillSafeDml.correctStringTooLongFields(
                accountRecord,
                capturedError,
                handledValues
            );

        System.assertEquals(true, firstCorrection);
        System.assertEquals(null, accountRecord.Phone);
        System.assertEquals(false, secondCorrection);
    }

    @IsTest
    static void insertRecord_rejectsNullRecord() {
        Boolean thrown = false;

        try {
            AutoFillSafeDml.insertRecord(null);
        } catch (AutoFillSafeDml.SafeDmlException expectedException) {
            thrown = true;
            System.assert(
                expectedException.getMessage().contains(
                    'Record was not supplied'
                )
            );
        }

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void insertRecord_rethrowsNonPicklistDmlError() {
        Boolean thrown = false;

        try {
            AutoFillSafeDml.insertRecord(new Contact());
        } catch (DmlException expectedException) {
            thrown = true;
            System.assert(
                expectedException.getMessage().contains('LastName')
            );
        }

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void insertRecord_clearsInvalidOptionalPicklistAndRetries() {
        FreightLoadSyncHandler.bypassForTests = true;
        Test.setMock(
            HttpCalloutMock.class,
            new AutoFillTestCalloutMock()
        );

        FreightTM__Load__c loadRecord = buildLoad('X');

        Test.startTest();
        AutoFillSafeDml.insertRecord(loadRecord);
        Test.stopTest();

        System.assertNotEquals(null, loadRecord.Id);

        Id createdLoadId = loadRecord.Id;
        SObject storedLoad = Database.query(
            'SELECT Id, AutoFill_Source__c FROM FreightTM__Load__c ' +
            'WHERE Id = :createdLoadId'
        );
        System.assertNotEquals('X', storedLoad.get('AutoFill_Source__c'));
    }

    @IsTest
    static void correctInvalidRestrictedPicklist_handlesOnlyOnce() {
        FreightLoadSyncHandler.bypassForTests = true;
        FreightTM__Load__c loadRecord = buildLoad('X');
        DmlException capturedError;

        try {
            insert loadRecord;
        } catch (DmlException expectedException) {
            capturedError = expectedException;
        }

        System.assertNotEquals(null, capturedError);

        Set<String> handledValues = new Set<String>();

        Boolean firstCorrection =
            AutoFillSafeDml.correctInvalidRestrictedPicklists(
                loadRecord,
                capturedError,
                handledValues
            );

        Boolean secondCorrection =
            AutoFillSafeDml.correctInvalidRestrictedPicklists(
                loadRecord,
                capturedError,
                handledValues
            );

        System.assertEquals(true, firstCorrection);
        System.assertEquals(null, loadRecord.get('AutoFill_Source__c'));
        System.assertEquals(false, secondCorrection);
    }

    @IsTest
    static void helperMethods_coverNullAndValueBranches() {
        Schema.DescribeFieldResult restrictedDescribe = sourceDescribe();

        System.assertEquals(
            false,
            AutoFillSafeDml.clearOversizedOptionalTextFields(null)
        );
        System.assertEquals(
            true,
            AutoFillSafeDml.isOptionalOnCreate(
                Account.Phone.getDescribe()
            )
        );
        System.assertEquals(
            false,
            AutoFillSafeDml.isOptionalOnCreate(null)
        );
        System.assertEquals(
            new Set<String>{ 'Phone', 'Website' },
            AutoFillSafeDml.extractDmlFieldNames(
                'data value too large: value: [Phone, Website]'
            )
        );
        System.assertEquals(
            new Set<String>(),
            AutoFillSafeDml.extractDmlFieldNames('No field list')
        );

        System.assertEquals(
            true,
            AutoFillSafeDml.isRestrictedPicklist(restrictedDescribe)
        );
        System.assertEquals(
            false,
            AutoFillSafeDml.isRestrictedPicklist(
                Account.Name.getDescribe()
            )
        );
        System.assertEquals(
            false,
            AutoFillSafeDml.isRestrictedPicklist(null)
        );

        String activeValue = firstActiveValue(restrictedDescribe);
        System.assertNotEquals(null, activeValue);

        System.assertEquals(
            activeValue,
            AutoFillSafeDml.findActivePicklistValue(
                restrictedDescribe,
                activeValue
            )
        );
        System.assertEquals(
            null,
            AutoFillSafeDml.findActivePicklistValue(
                restrictedDescribe,
                '__NOT_ACTIVE__'
            )
        );
        System.assertEquals(
            null,
            AutoFillSafeDml.findActivePicklistValue(null, activeValue)
        );

        System.assertEquals(
            'status|not started',
            AutoFillSafeDml.buildHandledKey(
                'Status',
                ' Not Started '
            )
        );
        System.assertEquals(
            'status|<null>',
            AutoFillSafeDml.buildHandledKey('Status', null)
        );

        System.assertEquals(
            'INVALID_VALUE',
            AutoFillSafeDml.extractRejectedPicklistValue(
                'Status: bad value for restricted picklist field: ' +
                'INVALID_VALUE: [Status]'
            )
        );
        System.assertEquals(
            null,
            AutoFillSafeDml.extractRejectedPicklistValue(
                'A different DML message'
            )
        );
        System.assertEquals(
            null,
            AutoFillSafeDml.extractRejectedPicklistValue(null)
        );

        System.assertEquals(
            true,
            AutoFillSafeDml.isLoadStatusField(
                new FreightTM__Load__c(),
                'FreightTM__Status__c'
            )
        );
        System.assertEquals(
            false,
            AutoFillSafeDml.isLoadStatusField(
                new Account(),
                'FreightTM__Status__c'
            )
        );
        System.assertEquals(
            false,
            AutoFillSafeDml.isLoadStatusField(null, 'Status')
        );
    }

    @IsTest
    static void helperMethods_coverRequiredAndNonMatchingDmlBranches() {
        Account requiredName = new Account(
            Name = repeatValue('N', 300)
        );

        System.assertEquals(
            false,
            AutoFillSafeDml.clearOversizedOptionalTextFields(requiredName)
        );
        System.assertEquals(300, requiredName.Name.length());
        System.assertEquals(
            false,
            AutoFillSafeDml.correctStringTooLongFields(
                null,
                null,
                null
            )
        );
        System.assertEquals(
            new Set<String>(),
            AutoFillSafeDml.extractDmlFieldNames(null)
        );
        System.assertEquals(
            new Set<String>(),
            AutoFillSafeDml.extractDmlFieldNames('value: [Phone')
        );

        DmlException requiredFieldError;
        Contact missingRequiredName = new Contact();
        try {
            insert missingRequiredName;
        } catch (DmlException expected) {
            requiredFieldError = expected;
        }

        System.assertNotEquals(null, requiredFieldError);
        System.assertEquals(
            false,
            AutoFillSafeDml.correctStringTooLongFields(
                new Contact(),
                requiredFieldError,
                new Set<String>()
            )
        );
        System.assertEquals(
            false,
            AutoFillSafeDml.correctInvalidRestrictedPicklists(
                new Contact(),
                requiredFieldError,
                new Set<String>()
            )
        );
        System.assertEquals(
            false,
            AutoFillSafeDml.correctInvalidRestrictedPicklists(
                null,
                null,
                new Set<String>()
            )
        );
    }

    @IsTest
    static void invalidLoadStatus_usesFallbackOrClearsValue() {
        FreightLoadSyncHandler.bypassForTests = true;
        Test.setMock(
            HttpCalloutMock.class,
            new AutoFillTestCalloutMock()
        );

        Schema.DescribeFieldResult statusDescribe =
            FreightTM__Load__c.SObjectType.getDescribe()
                .fields.getMap().get('FreightTM__Status__c').getDescribe();

        if (!statusDescribe.isRestrictedPicklist()) {
            System.assertEquals(
                false,
                AutoFillSafeDml.isRestrictedPicklist(statusDescribe)
            );
            return;
        }

        FreightTM__Load__c loadRecord = buildLoad(
            firstActiveValue(sourceDescribe())
        );
        loadRecord.put('FreightTM__Status__c', '__INVALID_STATUS__');
        DmlException capturedError;

        try {
            insert loadRecord;
        } catch (DmlException expected) {
            capturedError = expected;
        }

        System.assertNotEquals(null, capturedError);
        Set<String> handledValues = new Set<String>();
        Boolean corrected =
            AutoFillSafeDml.correctInvalidRestrictedPicklists(
                loadRecord,
                capturedError,
                handledValues
            );

        System.assertEquals(true, corrected);
        System.assertNotEquals(
            '__INVALID_STATUS__',
            loadRecord.get('FreightTM__Status__c')
        );

    }

}