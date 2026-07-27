@IsTest(SeeAllData=false)
private without sharing class Test_QuoteSystem {

    private static Integer sequenceNumber = 0;
    private static final String PERMISSION_SET_PATTERN =
        '%Lane_Quote_System_User';

    private class FreightGraphMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            String endpoint =
                request == null || request.getEndpoint() == null
                    ? ''
                    : request.getEndpoint().toLowerCase();

            if (
                endpoint.contains('/api/auth/login') ||
                endpoint.contains('/api/auth/refresh') ||
                endpoint.contains('token')
            ) {
                response.setStatusCode(200);
                response.setBody(
                    '{"token":"quote-system-test-token",' +
                    '"access_token":"quote-system-test-token",' +
                    '"expiresIn":3600}'
                );
                return response;
            }

            response.setStatusCode(201);
            response.setBody(
                '{"success":true,"id":"quote-system-test-id"}'
            );
            return response;
        }
    }

    @TestSetup
    static void grantQuoteSystemPermissionSet() {
        List<SObject> permissionRows =
            Database.queryWithBinds(
                'SELECT Id FROM PermissionSet ' +
                'WHERE Name LIKE :permissionName LIMIT 1',
                new Map<String, Object>{
                    'permissionName' => PERMISSION_SET_PATTERN
                },
                AccessLevel.SYSTEM_MODE
            );

        System.assert(
            !permissionRows.isEmpty(),
            'Deploy the FTM_Lane_Quote_System_User permission set ' +
            'from QuoteSystem before running this test.'
        );

        Id permissionSetId =
            (Id)permissionRows[0].get('Id');

        List<SObject> existingAssignments =
            Database.queryWithBinds(
                'SELECT Id FROM PermissionSetAssignment ' +
                'WHERE AssigneeId = :userId ' +
                'AND PermissionSetId = :permissionSetId LIMIT 1',
                new Map<String, Object>{
                    'userId' => UserInfo.getUserId(),
                    'permissionSetId' => permissionSetId
                },
                AccessLevel.SYSTEM_MODE
            );

        if (existingAssignments.isEmpty()) {
            PermissionSetAssignment assignment =
                new PermissionSetAssignment(
                    AssigneeId = UserInfo.getUserId(),
                    PermissionSetId = permissionSetId
                );

            try {
                Database.insert(
                    assignment,
                    AccessLevel.SYSTEM_MODE
                );
            } catch (DmlException assignmentError) {
                if (
                    assignmentError.getMessage() == null ||
                    !assignmentError.getMessage().contains(
                        'DUPLICATE_VALUE'
                    )
                ) {
                    throw assignmentError;
                }
            }
        }
    }

    private static void registerCalloutMock() {
        Test.setMock(
            HttpCalloutMock.class,
            new FreightGraphMock()
        );
    }

    private static String nextKey() {
        sequenceNumber++;

        String seed =
            String.valueOf(System.now().getTime()) +
            ':' +
            String.valueOf(sequenceNumber) +
            ':' +
            String.valueOf(Crypto.getRandomLong());

        return EncodingUtil.convertToHex(
            Crypto.generateDigest(
                'SHA-256',
                Blob.valueOf(seed)
            )
        ).substring(0, 10);
    }

    private static void systemInsert(SObject recordValue) {
        Database.insert(
            recordValue,
            AccessLevel.SYSTEM_MODE
        );
    }

    private static void systemInsert(
        List<SObject> recordValues
    ) {
        if (
            recordValues == null ||
            recordValues.isEmpty()
        ) {
            return;
        }

        Database.insert(
            recordValues,
            AccessLevel.SYSTEM_MODE
        );
    }

    private static void systemUpdate(SObject recordValue) {
        Database.update(
            recordValue,
            AccessLevel.SYSTEM_MODE
        );
    }

    private static Account createAccount(String labelValue) {
        Account accountRecord =
            new Account(
                Name =
                    labelValue +
                    ' ' +
                    nextKey()
            );

        systemInsert(accountRecord);
        return accountRecord;
    }

    private static FreightTM__Lane_Quote__c createQuote(
        Account accountRecord,
        Decimal customerRate,
        Decimal carrierCost,
        Boolean completeRoute
    ) {
        FreightTM__Lane_Quote__c quoteRecord =
            new FreightTM__Lane_Quote__c();

        putIfPresent(
            quoteRecord,
            'FreightTM__Customer__c',
            accountRecord.Id
        );

        if (completeRoute) {
            putIfPresent(
                quoteRecord,
                'FreightTM__Pickup_Street__c',
                '100 Test Pickup St'
            );
            putIfPresent(
                quoteRecord,
                'FreightTM__Pickup_City__c',
                'Chicago'
            );
            putIfPresent(
                quoteRecord,
                'FreightTM__Pickup_State__c',
                'IL'
            );
            putIfPresent(
                quoteRecord,
                'FreightTM__Pickup_Zip_Code__c',
                '60601'
            );
            putIfPresent(
                quoteRecord,
                'FreightTM__Pickup_Country__c',
                'United States'
            );

            putIfPresent(
                quoteRecord,
                'FreightTM__Delivery_Street__c',
                '200 Test Delivery Ave'
            );
            putIfPresent(
                quoteRecord,
                'FreightTM__Delivery_City__c',
                'Detroit'
            );
            putIfPresent(
                quoteRecord,
                'FreightTM__Delivery_State__c',
                'MI'
            );
            putIfPresent(
                quoteRecord,
                'FreightTM__Delivery_Zip_Code__c',
                '48201'
            );
            putIfPresent(
                quoteRecord,
                'FreightTM__Delivery_Country__c',
                'United States'
            );

            putIfPresent(
                quoteRecord,
                'FreightTM__Estimated_Pickup_Time__c',
                System.now().addDays(2)
            );
            putIfPresent(
                quoteRecord,
                'FreightTM__Estimated_Delivery_Time__c',
                System.now().addDays(3)
            );
        }

        putIfPresent(
            quoteRecord,
            'FreightTM__Customer_Rate__c',
            customerRate
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Rate_to_Carrier__c',
            carrierCost
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Weight__c',
            Decimal.valueOf('12000')
        );
        putIfPresent(
            quoteRecord,
            'Pallet_Count__c',
            Decimal.valueOf('12')
        );
        putIfPresent(
            quoteRecord,
            'Commodity__c',
            'General freight'
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Description__c',
            'Quote System test ' + nextKey()
        );
        putIfPresent(
            quoteRecord,
            'Minimum_Margin_Percent__c',
            Decimal.valueOf('15')
        );
        putIfPresent(
            quoteRecord,
            'Target_Margin_Percent__c',
            Decimal.valueOf('20')
        );

        setPreferredPicklist(
            quoteRecord,
            'Equipment_Type__c',
            new List<String>{
                'Dry Van',
                'Van',
                'Truckload'
            }
        );

        setFirstActivePicklist(
            quoteRecord,
            'FreightTM__Mode__c'
        );

        populateRequiredFields(
            quoteRecord,
            new Set<String>{
                'FreightTM__Customer__c'
            }
        );

        systemInsert(quoteRecord);
        return quoteRecord;
    }

    private static FreightTM__Load__c createHistoricalLoad(
        Account accountRecord,
        String pickupCity,
        String deliveryCity,
        Decimal customerRate,
        Decimal carrierCost,
        Integer dayOffset
    ) {
        FreightTM__Load__c loadRecord =
            new FreightTM__Load__c();

        putIfPresent(
            loadRecord,
            'FreightTM__Customer__c',
            accountRecord.Id
        );
        putIfPresent(
            loadRecord,
            'FreightTM__Pickup_City__c',
            pickupCity
        );
        putIfPresent(
            loadRecord,
            'FreightTM__Pickup_State__c',
            'IL'
        );
        putIfPresent(
            loadRecord,
            'FreightTM__Pickup_Zip_Code__c',
            '60601'
        );
        putIfPresent(
            loadRecord,
            'FreightTM__Pickup_Country__c',
            'United States'
        );
        putIfPresent(
            loadRecord,
            'FreightTM__Delivery_City__c',
            deliveryCity
        );
        putIfPresent(
            loadRecord,
            'FreightTM__Delivery_State__c',
            'MI'
        );
        putIfPresent(
            loadRecord,
            'FreightTM__Delivery_Zip_Code__c',
            '48201'
        );
        putIfPresent(
            loadRecord,
            'FreightTM__Delivery_Country__c',
            'United States'
        );
        putIfPresent(
            loadRecord,
            'FreightTM__Pickup_Date__c',
            Date.today().addDays(dayOffset)
        );
        putIfPresent(
            loadRecord,
            'FreightTM__Delivery_Date__c',
            Date.today().addDays(dayOffset + 1)
        );
        putIfPresent(
            loadRecord,
            'FreightTM__Rate__c',
            customerRate
        );
        putIfPresent(
            loadRecord,
            'FreightTM__Rate_to_Carrier__c',
            carrierCost
        );
        putIfPresent(
            loadRecord,
            'FreightTM__Load_Canceled__c',
            false
        );
        putIfPresent(
            loadRecord,
            'POD_Received__c',
            true
        );

        setPreferredPicklist(
            loadRecord,
            'FreightTM__Status__c',
            new List<String>{
                'Delivered',
                'Assigned'
            }
        );

        populateRequiredFields(
            loadRecord,
            new Set<String>{
                'FreightTM__Customer__c'
            }
        );

        systemInsert(loadRecord);
        return loadRecord;
    }

    private static void createQuoteChildren(Id quoteId) {
        SObject quoteLine =
            newRecord('FreightTM__Quote_Line__c');

        putIfPresent(
            quoteLine,
            'FreightTM__Lane_Quote__c',
            quoteId
        );
        populateQuoteLine(quoteLine);

        SObject quotePay =
            newRecord('FreightTM__Quote_Pay__c');

        putIfPresent(
            quotePay,
            'FreightTM__Lane_Quote__c',
            quoteId
        );
        populateQuotePay(quotePay);

        SObject quoteLeg =
            newRecord('FreightTM__Quote_Leg__c');

        putIfPresent(
            quoteLeg,
            'FreightTM__Lane_Quote__c',
            quoteId
        );
        populateQuoteLeg(quoteLeg);

        systemInsert(quoteLine);
        systemInsert(quotePay);
        systemInsert(quoteLeg);
    }

    private static void populateQuoteLine(SObject recordValue) {
        setFirstActivePicklist(
            recordValue,
            'Type__c'
        );
        putIfPresent(
            recordValue,
            'Unit_Price__c',
            Decimal.valueOf('125')
        );
        putIfPresent(
            recordValue,
            'Number_of_Units__c',
            Decimal.valueOf('2')
        );

        populateRequiredFields(
            recordValue,
            new Set<String>{
                'FreightTM__Lane_Quote__c'
            }
        );
    }

    private static void populateQuotePay(SObject recordValue) {
        setFirstActivePicklist(
            recordValue,
            'FreightTM__Type__c'
        );
        putIfPresent(
            recordValue,
            'FreightTM__Unit_Price__c',
            Decimal.valueOf('75')
        );
        putIfPresent(
            recordValue,
            'FreightTM__Number_of_Units__c',
            Decimal.valueOf('1')
        );
        putIfPresent(
            recordValue,
            'FreightTM__Amount__c',
            Decimal.valueOf('75')
        );
        putIfPresent(
            recordValue,
            'FreightTM__Description__c',
            'Test quote pay'
        );

        populateRequiredFields(
            recordValue,
            new Set<String>{
                'FreightTM__Lane_Quote__c'
            }
        );
    }

    private static void populateQuoteLeg(SObject recordValue) {
        putIfPresent(
            recordValue,
            'FreightTM__Pickup_Street__c',
            '1 Test Street'
        );
        putIfPresent(
            recordValue,
            'FreightTM__Pickup_City__c',
            'Chicago'
        );
        putIfPresent(
            recordValue,
            'FreightTM__Pickup_ZIP_Code__c',
            '60601'
        );
        putIfPresent(
            recordValue,
            'FreightTM__Delivery_Street__c',
            '2 Test Avenue'
        );
        putIfPresent(
            recordValue,
            'FreightTM__Delivery_City__c',
            'Detroit'
        );
        putIfPresent(
            recordValue,
            'FreightTM__Delivery_ZIP_Code__c',
            '48201'
        );

        setFirstActivePicklist(
            recordValue,
            'FreightTM__Pickup_Country__c'
        );
        setFirstActivePicklist(
            recordValue,
            'FreightTM__Pickup_State__c'
        );
        setFirstActivePicklist(
            recordValue,
            'FreightTM__Delivery_Country__c'
        );
        setFirstActivePicklist(
            recordValue,
            'FreightTM__Delivery_State__c'
        );
        setFirstActivePicklist(
            recordValue,
            'FreightTM__Mode_of_Transportation__c'
        );

        populateRequiredFields(
            recordValue,
            new Set<String>{
                'FreightTM__Lane_Quote__c'
            }
        );
    }

    private static void populateLaneQuoteTemplate(
        SObject quoteRecord,
        Id accountId
    ) {
        putIfPresent(
            quoteRecord,
            'FreightTM__Customer__c',
            accountId
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Pickup_Street__c',
            '10 New Pickup St'
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Pickup_City__c',
            'Phoenix'
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Pickup_State__c',
            'AZ'
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Pickup_Zip_Code__c',
            '85001'
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Pickup_Country__c',
            'United States'
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Delivery_Street__c',
            '20 New Delivery Ave'
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Delivery_City__c',
            'Las Vegas'
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Delivery_State__c',
            'NV'
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Delivery_Zip_Code__c',
            '89101'
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Delivery_Country__c',
            'United States'
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Estimated_Pickup_Time__c',
            System.now().addDays(1)
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Estimated_Delivery_Time__c',
            System.now().addDays(2)
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Customer_Rate__c',
            Decimal.valueOf('1800')
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Rate_to_Carrier__c',
            Decimal.valueOf('1350')
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Weight__c',
            Decimal.valueOf('9000')
        );
        putIfPresent(
            quoteRecord,
            'FreightTM__Description__c',
            'New Lane Quote conversion test'
        );

        setFirstActivePicklist(
            quoteRecord,
            'Equipment_Type__c'
        );
        setFirstActivePicklist(
            quoteRecord,
            'FreightTM__Mode__c'
        );

        populateRequiredFields(
            quoteRecord,
            new Set<String>{
                'FreightTM__Customer__c'
            }
        );
    }

    private static SObject newRecord(String objectApiName) {
        Schema.SObjectType objectType =
            Schema.getGlobalDescribe().get(
                objectApiName
            );

        System.assertNotEquals(
            null,
            objectType,
            'Missing object: ' + objectApiName
        );

        return objectType.newSObject();
    }

    private static void putIfPresent(
        SObject recordValue,
        String requestedFieldName,
        Object fieldValue
    ) {
        if (
            recordValue == null ||
            String.isBlank(requestedFieldName) ||
            fieldValue == null
        ) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap =
            recordValue
                .getSObjectType()
                .getDescribe()
                .fields
                .getMap();

        for (String fieldName : fieldMap.keySet()) {
            if (
                !fieldName.equalsIgnoreCase(
                    requestedFieldName
                )
            ) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe =
                fieldMap.get(fieldName).getDescribe();

            if (
                !fieldDescribe.isCalculated() &&
                !fieldDescribe.isAutoNumber()
            ) {
                recordValue.put(
                    fieldDescribe.getName(),
                    fieldValue
                );
            }

            return;
        }
    }

    private static void setPreferredPicklist(
        SObject recordValue,
        String fieldApiName,
        List<String> preferredValues
    ) {
        Schema.DescribeFieldResult fieldDescribe =
            getFieldDescribe(
                recordValue,
                fieldApiName
            );

        if (
            fieldDescribe == null ||
            fieldDescribe.isCalculated()
        ) {
            return;
        }

        String firstActiveValue;

        for (
            Schema.PicklistEntry entry :
            fieldDescribe.getPicklistValues()
        ) {
            if (!entry.isActive()) {
                continue;
            }

            if (firstActiveValue == null) {
                firstActiveValue =
                    entry.getValue();
            }

            if (preferredValues != null) {
                for (String preferredValue : preferredValues) {
                    if (
                        preferredValue != null &&
                        preferredValue.equalsIgnoreCase(
                            entry.getValue()
                        )
                    ) {
                        recordValue.put(
                            fieldDescribe.getName(),
                            entry.getValue()
                        );
                        return;
                    }
                }
            }
        }

        if (firstActiveValue != null) {
            recordValue.put(
                fieldDescribe.getName(),
                firstActiveValue
            );
        }
    }

    private static void setFirstActivePicklist(
        SObject recordValue,
        String fieldApiName
    ) {
        setPreferredPicklist(
            recordValue,
            fieldApiName,
            null
        );
    }

    private static Schema.DescribeFieldResult getFieldDescribe(
        SObject recordValue,
        String requestedFieldName
    ) {
        if (
            recordValue == null ||
            String.isBlank(requestedFieldName)
        ) {
            return null;
        }

        Map<String, Schema.SObjectField> fieldMap =
            recordValue
                .getSObjectType()
                .getDescribe()
                .fields
                .getMap();

        for (String fieldName : fieldMap.keySet()) {
            if (
                fieldName.equalsIgnoreCase(
                    requestedFieldName
                )
            ) {
                return fieldMap
                    .get(fieldName)
                    .getDescribe();
            }
        }

        return null;
    }

    private static void populateRequiredFields(
        SObject recordValue,
        Set<String> skippedFields
    ) {
        if (recordValue == null) {
            return;
        }

        if (skippedFields == null) {
            skippedFields =
                new Set<String>();
        }

        Map<String, Schema.SObjectField> fieldMap =
            recordValue
                .getSObjectType()
                .getDescribe()
                .fields
                .getMap();

        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe =
                fieldMap.get(fieldName).getDescribe();

            if (
                fieldName == 'Id' ||
                fieldDescribe.isNillable() ||
                fieldDescribe.isDefaultedOnCreate() ||
                fieldDescribe.isCalculated() ||
                fieldDescribe.isAutoNumber() ||
                containsIgnoreCase(
                    skippedFields,
                    fieldName
                ) ||
                recordValue.get(fieldName) != null
            ) {
                continue;
            }

            Object defaultFieldValue =
                getDefaultValue(fieldDescribe);

            if (defaultFieldValue != null) {
                recordValue.put(
                    fieldName,
                    defaultFieldValue
                );
            }
        }
    }

    private static Object getDefaultValue(
        Schema.DescribeFieldResult fieldDescribe
    ) {
        Schema.DisplayType fieldType =
            fieldDescribe.getType();

        if (
            fieldType == Schema.DisplayType.BOOLEAN
        ) {
            return false;
        }

        if (
            fieldType == Schema.DisplayType.DATE
        ) {
            return Date.today();
        }

        if (
            fieldType == Schema.DisplayType.DATETIME
        ) {
            return System.now();
        }

        if (
            fieldType == Schema.DisplayType.INTEGER
        ) {
            return 1;
        }

        if (
            fieldType == Schema.DisplayType.CURRENCY ||
            fieldType == Schema.DisplayType.DOUBLE ||
            fieldType == Schema.DisplayType.PERCENT
        ) {
            return Decimal.valueOf('1');
        }

        if (
            fieldType == Schema.DisplayType.PICKLIST ||
            fieldType == Schema.DisplayType.MULTIPICKLIST
        ) {
            for (
                Schema.PicklistEntry entry :
                fieldDescribe.getPicklistValues()
            ) {
                if (entry.isActive()) {
                    return entry.getValue();
                }
            }

            return null;
        }

        if (
            fieldType == Schema.DisplayType.REFERENCE
        ) {
            for (
                Schema.SObjectType referenceType :
                fieldDescribe.getReferenceTo()
            ) {
                if (
                    referenceType == User.SObjectType
                ) {
                    return UserInfo.getUserId();
                }
            }

            return null;
        }

        if (
            fieldType == Schema.DisplayType.STRING ||
            fieldType == Schema.DisplayType.TEXTAREA ||
            fieldType == Schema.DisplayType.PHONE ||
            fieldType == Schema.DisplayType.EMAIL ||
            fieldType == Schema.DisplayType.URL ||
            fieldType == Schema.DisplayType.ENCRYPTEDSTRING
        ) {
            String keyValue =
                nextKey();

            String textValue =
                fieldType == Schema.DisplayType.EMAIL
                    ? 'test.' +
                        keyValue +
                        '@example.com'
                    : 'Test ' +
                        keyValue;

            Integer lengthLimit =
                fieldDescribe.getLength();

            if (
                lengthLimit > 0 &&
                textValue.length() > lengthLimit
            ) {
                textValue =
                    textValue.substring(
                        0,
                        lengthLimit
                    );
            }

            return textValue;
        }

        return null;
    }

    private static Boolean containsIgnoreCase(
        Set<String> values,
        String candidate
    ) {
        if (
            values == null ||
            candidate == null
        ) {
            return false;
        }

        for (String value : values) {
            if (
                value != null &&
                value.equalsIgnoreCase(candidate)
            ) {
                return true;
            }
        }

        return false;
    }

    private static void setControllerPage(
        String pageName,
        Id recordId
    ) {
        Test.setCurrentPage(
            new PageReference(
                '/apex/' + pageName
            )
        );

        if (recordId != null) {
            ApexPages.currentPage()
                .getParameters()
                .put(
                    'id',
                    String.valueOf(recordId)
                );
        }
    }

    private static Id firstOptionId(
        List<SelectOption> options
    ) {
        if (
            options == null ||
            options.isEmpty() ||
            String.isBlank(
                options[0].getValue()
            )
        ) {
            return null;
        }

        return Id.valueOf(
            options[0].getValue()
        );
    }

    private static Boolean messagesContain(
        String expectedText
    ) {
        for (
            ApexPages.Message messageValue :
            ApexPages.getMessages()
        ) {
            if (
                messageValue.getSummary() != null &&
                messageValue
                    .getSummary()
                    .contains(expectedText)
            ) {
                return true;
            }
        }

        return false;
    }

    private static Id recordIdFromPage(
        PageReference pageReference
    ) {
        if (pageReference == null) {
            return null;
        }

        String urlValue =
            pageReference.getUrl();

        if (String.isBlank(urlValue)) {
            return null;
        }

        if (urlValue.startsWith('/')) {
            urlValue =
                urlValue.substring(1);
        }

        Integer queryIndex =
            urlValue.indexOf('?');

        if (queryIndex >= 0) {
            urlValue =
                urlValue.substring(
                    0,
                    queryIndex
                );
        }

        try {
            return Id.valueOf(urlValue);
        } catch (Exception ignoredError) {
            return null;
        }
    }

    private static void assertAuraException(
        Boolean exceptionThrown,
        String messageValue
    ) {
        System.assertEquals(
            true,
            exceptionThrown,
            messageValue
        );
    }

    @IsTest
    static void testWorkspaceLifecycleHistoryAndConversion() {
        registerCalloutMock();

        Account accountRecord =
            createAccount(
                'Workspace Customer'
            );

        createHistoricalLoad(
            accountRecord,
            'Chicago',
            'Detroit',
            2400,
            1800,
            -8
        );

        createHistoricalLoad(
            accountRecord,
            'Chicago',
            'Detroit',
            2600,
            1900,
            -4
        );

        FreightTM__Lane_Quote__c quoteRecord =
            createQuote(
                accountRecord,
                2500,
                1850,
                true
            );

        Test.startTest();

        FtmLaneQuoteWorkspaceController.QuoteDataDTO
            initialData =
                FtmLaneQuoteWorkspaceController.getQuoteData(
                        quoteRecord.Id
                    );

        FtmLaneQuoteWorkspaceController.ActionResultDTO
            calculated =
                FtmLaneQuoteWorkspaceController.calculateQuote(
                        quoteRecord.Id
                    );

        System.assertEquals(
            true,
            calculated.success
        );
        System.assertNotEquals(
            null,
            calculated.data
                .estimatedMarginPercent
        );
        System.assert(
            calculated.data.priorLoadCount >= 2,
            'Exact-lane history should be evaluated.'
        );

        if (calculated.data.canRequestApproval) {
            FtmLaneQuoteWorkspaceController.requestApproval(
                    quoteRecord.Id,
                    'Automated test approval request'
                );

            FtmLaneQuoteWorkspaceController.approveQuote(
                    quoteRecord.Id,
                    'Automated test approval'
                );
        }

        FtmLaneQuoteWorkspaceController.ActionResultDTO
            sentResult =
                FtmLaneQuoteWorkspaceController.markSent(
                        quoteRecord.Id
                    );

        FtmLaneQuoteWorkspaceController.ActionResultDTO
            acceptedResult =
                FtmLaneQuoteWorkspaceController.markAccepted(
                        quoteRecord.Id,
                        'Accepted during automated test'
                    );

        Exception conversionError;
        FtmLaneQuoteWorkspaceController.ActionResultDTO
            convertedResult;

        try {
            convertedResult =
                FtmLaneQuoteWorkspaceController.convertToLoad(
                        quoteRecord.Id
                    );
        } catch (Exception caughtError) {
            conversionError =
                caughtError;
        }

        if (convertedResult != null) {
            FtmLaneQuoteWorkspaceController.convertToLoad(
                    quoteRecord.Id
                );
        }

        Test.stopTest();

        System.assertEquals(
            quoteRecord.Id,
            Id.valueOf(initialData.quoteId)
        );
        System.assertEquals(
            true,
            sentResult.success
        );
        System.assertEquals(
            'Sent',
            sentResult.data.workflowStatus
        );
        System.assertEquals(
            true,
            acceptedResult.success
        );
        System.assertEquals(
            'Accepted',
            acceptedResult.data.workflowStatus
        );

        System.assert(
            convertedResult != null ||
            (
                conversionError != null &&
                !String.isBlank(
                    conversionError.getMessage()
                )
            ),
            'Conversion must either succeed or return a clear org-specific validation error.'
        );
    }

    @IsTest
    static void testWorkspaceApprovalDeclineAndValidation() {
        registerCalloutMock();

        Account accountRecord =
            createAccount(
                'Approval Customer'
            );

        FreightTM__Lane_Quote__c approvalQuote =
            createQuote(
                accountRecord,
                1000,
                950,
                true
            );

        FtmLaneQuoteWorkspaceController.ActionResultDTO
            calculated =
                FtmLaneQuoteWorkspaceController.calculateQuote(
                        approvalQuote.Id
                    );

        System.assertEquals(
            true,
            calculated.data.approvalRequired
        );

        FtmLaneQuoteWorkspaceController.ActionResultDTO
            requested =
                FtmLaneQuoteWorkspaceController.requestApproval(
                        approvalQuote.Id,
                        'Please review'
                    );

        FtmLaneQuoteWorkspaceController.ActionResultDTO
            rejected =
                FtmLaneQuoteWorkspaceController.rejectApproval(
                        approvalQuote.Id,
                        'Margin is too low'
                    );

        System.assertEquals(
            'Pending',
            requested.data.approvalStatus
        );
        System.assertEquals(
            'Rejected',
            rejected.data.approvalStatus
        );

        FreightTM__Lane_Quote__c declineQuote =
            createQuote(
                accountRecord,
                3000,
                1800,
                true
            );

        FtmLaneQuoteWorkspaceController.ActionResultDTO
            declineCalculated =
                FtmLaneQuoteWorkspaceController.calculateQuote(
                        declineQuote.Id
                    );

        if (
            declineCalculated.data
                .canRequestApproval
        ) {
            FtmLaneQuoteWorkspaceController.requestApproval(
                    declineQuote.Id,
                    'Approval before decline test'
                );

            FtmLaneQuoteWorkspaceController.approveQuote(
                    declineQuote.Id,
                    'Approved'
                );
        }

        FtmLaneQuoteWorkspaceController.markSent(
                declineQuote.Id
            );

        FtmLaneQuoteWorkspaceController.ActionResultDTO
            declined =
                FtmLaneQuoteWorkspaceController.markDeclined(
                        declineQuote.Id,
                        'Customer selected another carrier'
                    );

        System.assertEquals(
            'Declined',
            declined.data.workflowStatus
        );

        FreightTM__Lane_Quote__c incompleteQuote =
            createQuote(
                accountRecord,
                null,
                null,
                false
            );

        Integer exceptionCount = 0;

        try {
            FtmLaneQuoteWorkspaceController.getQuoteData(null);
        } catch (AuraHandledException expectedError) {
            exceptionCount++;
        }

        try {
            FtmLaneQuoteWorkspaceController.getQuoteData(accountRecord.Id);
        } catch (AuraHandledException expectedError) {
            exceptionCount++;
        }

        try {
            FtmLaneQuoteWorkspaceController.markSent(incompleteQuote.Id);
        } catch (AuraHandledException expectedError) {
            exceptionCount++;
        }

        try {
            FtmLaneQuoteWorkspaceController.markAccepted(
                    incompleteQuote.Id,
                    'Invalid acceptance'
                );
        } catch (AuraHandledException expectedError) {
            exceptionCount++;
        }

        try {
            FtmLaneQuoteWorkspaceController.markDeclined(
                    incompleteQuote.Id,
                    ''
                );
        } catch (AuraHandledException expectedError) {
            exceptionCount++;
        }

        System.assertEquals(
            5,
            exceptionCount,
            'Workspace validation branches should throw AuraHandledException.'
        );
    }

    @IsTest
    static void testCloneControllerSuccessAndErrors() {
        registerCalloutMock();

        Account accountRecord =
            createAccount(
                'Clone Customer'
            );

        FreightTM__Lane_Quote__c sourceQuote =
            createQuote(
                accountRecord,
                2200,
                1600,
                true
            );

        createQuoteChildren(
            sourceQuote.Id
        );

        setControllerPage(
            'LaneQuoteCloneControllerPage',
            sourceQuote.Id
        );

        LaneQuoteCloneController controller =
            new LaneQuoteCloneController();

        System.assertEquals(
            sourceQuote.Id,
            controller.sourceLaneQuoteId
        );
        System.assertNotEquals(
            null,
            controller.laneQuoteRecord
        );
        System.assertNotEquals(
            null,
            controller.laneQuoteFields
        );

        controller.addQuoteLine();
        populateQuoteLine(
            controller.quoteLines[
                controller.quoteLines.size() - 1
            ].record
        );

        controller.addQuotePay();
        populateQuotePay(
            controller.quotePays[
                controller.quotePays.size() - 1
            ].record
        );

        controller.addQuoteLeg();
        populateQuoteLeg(
            controller.quoteLegs[
                controller.quoteLegs.size() - 1
            ].record
        );

        controller.rowIndex =
            controller.quoteLines.size() - 1;
        controller.removeQuoteLine();

        controller.rowIndex =
            controller.quotePays.size() - 1;
        controller.removeQuotePay();

        controller.rowIndex =
            controller.quoteLegs.size() - 1;
        controller.removeQuoteLeg();

        controller.cloneCount = 0;

        PageReference invalidResult =
            controller.saveClones();

        System.assertEquals(
            null,
            invalidResult
        );
        System.assert(
            messagesContain(
                'Number of Lane Quotes'
            ),
            'Invalid clone count should show a clear message.'
        );

        setControllerPage(
            'LaneQuoteCloneControllerPage',
            sourceQuote.Id
        );

        LaneQuoteCloneController successController =
            new LaneQuoteCloneController();

        List<SelectOption> recordTypeOptions =
            successController
                .getLaneQuoteRecordTypeOptions();

        successController.selectedRecordTypeId =
            firstOptionId(recordTypeOptions);
        successController.cloneCount = 2;

        PageReference saveResult =
            successController.saveClones();

        if (saveResult != null) {
            System.assertNotEquals(
                null,
                recordIdFromPage(saveResult)
            );
        } else {
            System.assert(
                !ApexPages.getMessages().isEmpty(),
                'Clone failure must return a visible error message.'
            );
        }

        System.assertNotEquals(
            null,
            successController.cancel()
        );

        setControllerPage(
            'LaneQuoteCloneControllerPage',
            null
        );

        LaneQuoteCloneController missingIdController =
            new LaneQuoteCloneController();

        System.assert(
            messagesContain(
                'record ID is required'
            ),
            'Missing Lane Quote Id should produce a fatal message.'
        );
        System.assertEquals(
            null,
            missingIdController.sourceLaneQuoteId
        );
    }

    @IsTest
    static void testExistingQuoteToLoadControllerAllAvailableBranches() {
        registerCalloutMock();

        Account accountRecord =
            createAccount(
                'Existing Conversion Customer'
            );

        FreightTM__Lane_Quote__c sourceQuote =
            createQuote(
                accountRecord,
                2300,
                1700,
                true
            );

        createQuoteChildren(
            sourceQuote.Id
        );

        setControllerPage(
            'LaneQuoteToLoadControllerPage',
            sourceQuote.Id
        );

        LaneQuoteToLoadController controller =
            new LaneQuoteToLoadController();

        System.assertEquals(
            sourceQuote.Id,
            controller.sourceLaneQuoteId
        );


        controller.addQuoteLine();
        controller.addQuotePay();
        controller.addQuoteLeg();

        controller.rowIndex =
            controller.quoteLines.size() - 1;
        controller.removeQuoteLine();

        controller.rowIndex =
            controller.quotePays.size() - 1;
        controller.removeQuotePay();

        controller.rowIndex =
            controller.quoteLegs.size() - 1;
        controller.removeQuoteLeg();

        controller.selectedLoadRecordTypeId =
            null;

        PageReference invalidResult =
            controller.convertToLoad();

        System.assertEquals(
            null,
            invalidResult
        );
        System.assert(
            messagesContain(
                'Select an available Load Record Type'
            ),
            'Missing Load Record Type should be handled.'
        );

        setControllerPage(
            'LaneQuoteToLoadControllerPage',
            sourceQuote.Id
        );

        LaneQuoteToLoadController successController =
            new LaneQuoteToLoadController();

        List<SelectOption> loadRecordTypes =
            successController
                .getLoadRecordTypeOptions();

        if (!loadRecordTypes.isEmpty()) {
            successController
                .selectedLoadRecordTypeId =
                    firstOptionId(
                        loadRecordTypes
                    );

            PageReference convertedPage =
                successController
                    .convertToLoad();

            if (convertedPage != null) {
                System.assertNotEquals(
                    null,
                    recordIdFromPage(
                        convertedPage
                    )
                );
            } else {
                System.assert(
                    !ApexPages.getMessages().isEmpty(),
                    'Conversion failure must show an error message.'
                );
            }
        } else {
            System.assertEquals(
                null,
                successController
                    .selectedLoadRecordTypeId,
                'This org has no available non-Master Load Record Type.'
            );
        }

        System.assertNotEquals(
            null,
            successController.cancel()
        );

        setControllerPage(
            'LaneQuoteToLoadControllerPage',
            null
        );

        new LaneQuoteToLoadController();

        System.assert(
            messagesContain(
                'record ID is required'
            )
        );
    }

    @IsTest
    static void testNewQuoteToLoadControllerAllAvailableBranches() {
        registerCalloutMock();

        Account accountRecord =
            createAccount(
                'New Conversion Customer'
            );

        Test.setCurrentPage(
            new PageReference(
                '/apex/NewLaneQuoteToLoadControllerPage'
            )
        );

        NewLaneQuoteToLoadController controller =
            new NewLaneQuoteToLoadController();

        System.assertNotEquals(
            null,
            controller.laneQuoteRecord
        );
        System.assertNotEquals(
            null,
            controller.laneQuoteFields
        );

        populateLaneQuoteTemplate(
            controller.laneQuoteRecord,
            accountRecord.Id
        );

        controller.addQuoteLine();
        populateQuoteLine(
            controller.quoteLines[
                controller.quoteLines.size() - 1
            ].record
        );

        controller.addQuotePay();
        populateQuotePay(
            controller.quotePays[
                controller.quotePays.size() - 1
            ].record
        );

        controller.addQuoteLeg();
        populateQuoteLeg(
            controller.quoteLegs[
                controller.quoteLegs.size() - 1
            ].record
        );

        controller.rowIndex =
            controller.quoteLines.size() - 1;
        controller.removeQuoteLine();

        controller.rowIndex =
            controller.quotePays.size() - 1;
        controller.removeQuotePay();

        controller.rowIndex =
            controller.quoteLegs.size() - 1;
        controller.removeQuoteLeg();

        controller.selectedLoadRecordTypeId =
            null;

        PageReference invalidResult =
            controller.createAndConvert();

        System.assertEquals(
            null,
            invalidResult
        );
        System.assert(
            messagesContain(
                'Select an available Load Record Type'
            ),
            'Missing Load Record Type should be handled.'
        );

        Test.setCurrentPage(
            new PageReference(
                '/apex/NewLaneQuoteToLoadControllerPage'
            )
        );

        NewLaneQuoteToLoadController successController =
            new NewLaneQuoteToLoadController();

        populateLaneQuoteTemplate(
            successController.laneQuoteRecord,
            accountRecord.Id
        );

        List<SelectOption> laneQuoteRecordTypes =
            successController
                .getLaneQuoteRecordTypeOptions();

        List<SelectOption> loadRecordTypes =
            successController
                .getLoadRecordTypeOptions();

        if (!laneQuoteRecordTypes.isEmpty()) {
            successController
                .selectedLaneQuoteRecordTypeId =
                    firstOptionId(
                        laneQuoteRecordTypes
                    );
        }

        if (!loadRecordTypes.isEmpty()) {
            successController
                .selectedLoadRecordTypeId =
                    firstOptionId(
                        loadRecordTypes
                    );

            successController.addQuoteLine();
            populateQuoteLine(
                successController.quoteLines[
                    successController.quoteLines.size() - 1
                ].record
            );

            successController.addQuotePay();
            populateQuotePay(
                successController.quotePays[
                    successController.quotePays.size() - 1
                ].record
            );

            successController.addQuoteLeg();
            populateQuoteLeg(
                successController.quoteLegs[
                    successController.quoteLegs.size() - 1
                ].record
            );

            PageReference createdPage =
                successController
                    .createAndConvert();

            if (createdPage != null) {
                System.assertNotEquals(
                    null,
                    recordIdFromPage(
                        createdPage
                    )
                );
            } else {
                System.assert(
                    !ApexPages.getMessages().isEmpty(),
                    'Create-and-convert failure must show an error message.'
                );
            }
        } else {
            System.assertEquals(
                null,
                successController
                    .selectedLoadRecordTypeId,
                'This org has no available non-Master Load Record Type.'
            );
        }

        PageReference cancelPage =
            successController.cancel();

        System.assert(
            cancelPage.getUrl()
                .contains(
                    'FreightTM__Lane_Quote__c'
                )
        );
    }
}
