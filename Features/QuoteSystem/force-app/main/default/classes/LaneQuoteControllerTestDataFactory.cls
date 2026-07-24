@IsTest
public class LaneQuoteControllerTestDataFactory {
    public class FreightGraphSyncMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            String endpoint = request == null ? null : request.getEndpoint();
            if (endpoint != null &&
                (endpoint.endsWith('/api/auth/login') || endpoint.endsWith('/api/auth/refresh'))) {
                response.setStatusCode(200);
                response.setBody('{"token":"lane-quote-test-token","expiresIn":3600}');
                return response;
            }

            response.setStatusCode(201);
            response.setBody('{}');
            return response;
        }
    }

    public static void registerCalloutMock() {
        Test.setMock(HttpCalloutMock.class, new FreightGraphSyncMock());
    }

    public static Account createAccount(String name) {
        Account accountRec = new Account(Name = name);
        insert accountRec;
        return accountRec;
    }

    public static Id firstAvailableNonMasterRecordType(String objectApiName) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        System.assertNotEquals(null, objectType, 'Missing object: ' + objectApiName);

        if (!hasField(objectType, 'RecordTypeId')) {
            return null;
        }

        for (Schema.RecordTypeInfo info : objectType.getDescribe().getRecordTypeInfos()) {
            if (info.isAvailable() && info.getRecordTypeId() != null && !info.isMaster()) {
                return info.getRecordTypeId();
            }
        }

        return null;
    }

    public static Boolean hasNonMasterRecordTypes(String objectApiName) {
        return firstAvailableNonMasterRecordType(objectApiName) != null;
    }

    public static FreightTM__Lane_Quote__c createLaneQuote(Account accountRec, String suffix) {
        FreightTM__Lane_Quote__c quoteRec = new FreightTM__Lane_Quote__c(
            FreightTM__Customer__c = accountRec.Id,
            FreightTM__Pickup_City__c = 'Chicago',
            FreightTM__Pickup_State__c = 'IL',
            FreightTM__Pickup_Zip_Code__c = '60601',
            FreightTM__Delivery_City__c = 'Detroit',
            FreightTM__Delivery_State__c = 'MI',
            FreightTM__Delivery_Zip_Code__c = '48201',
            FreightTM__Estimated_Pickup_Time__c = System.now().addDays(2),
            FreightTM__Estimated_Delivery_Time__c = System.now().addDays(3),
            FreightTM__Customer_Rate__c = 2500,
            FreightTM__Rate_to_Carrier__c = 1900,
            FreightTM__Weight__c = 12000,
            FreightTM__Description__c = 'Lane Quote controller test ' + suffix
        );

        putIfCreateable(
            quoteRec,
            'RecordTypeId',
            firstAvailableNonMasterRecordType('FreightTM__Lane_Quote__c')
        );
        setFirstActivePicklist(quoteRec, 'Equipment_Type__c');
        setFirstActivePicklist(quoteRec, 'FreightTM__Mode__c');
        setCommonPicklist(
            quoteRec,
            'FreightTM__Status__c',
            'FreightTM__Load__c',
            'FreightTM__Status__c'
        );
        setCommonPicklist(
            quoteRec,
            'FreightTM__Priority__c',
            'FreightTM__Load__c',
            'FreightTM__Priority__c'
        );
        populateRequiredFields(quoteRec, new Set<String>());
        insert quoteRec;
        return quoteRec;
    }

    public static void setControllerPage(String pageName, Id recordId) {
        Test.setCurrentPage(new PageReference('/apex/' + pageName));
        if (recordId != null) {
            ApexPages.currentPage().getParameters().put('id', String.valueOf(recordId));
        }
    }

    public static Id recordIdFrom(PageReference pageReference) {
        System.assertNotEquals(null, pageReference, 'Expected a redirect PageReference.');
        String url = pageReference.getUrl();
        System.assert(!String.isBlank(url), 'Expected a redirect URL.');
        if (url.startsWith('/')) url = url.substring(1);
        Integer queryIndex = url.indexOf('?');
        if (queryIndex >= 0) url = url.substring(0, queryIndex);
        return Id.valueOf(url);
    }

    public static void createQuoteChildren(Id quoteId) {
        SObject quoteLine = newRecord('FreightTM__Quote_Line__c');
        putIfCreateable(quoteLine, 'FreightTM__Lane_Quote__c', quoteId);
        populateQuoteLine(quoteLine);
        populateRequiredFields(quoteLine, new Set<String>{'FreightTM__Lane_Quote__c'});
        insert quoteLine;

        SObject quotePay = newRecord('FreightTM__Quote_Pay__c');
        putIfCreateable(quotePay, 'FreightTM__Lane_Quote__c', quoteId);
        populateQuotePay(quotePay);
        populateRequiredFields(quotePay, new Set<String>{'FreightTM__Lane_Quote__c'});
        insert quotePay;

        SObject quoteLeg = newRecord('FreightTM__Quote_Leg__c');
        putIfCreateable(quoteLeg, 'FreightTM__Lane_Quote__c', quoteId);
        populateQuoteLeg(quoteLeg);
        populateRequiredFields(quoteLeg, new Set<String>{'FreightTM__Lane_Quote__c'});
        insert quoteLeg;
    }

    public static void populateLaneQuoteTemplate(SObject quoteRec, Id accountId) {
        putIfCreateable(quoteRec, 'FreightTM__Customer__c', accountId);
        putIfCreateable(quoteRec, 'FreightTM__Pickup_City__c', 'Phoenix');
        putIfCreateable(quoteRec, 'FreightTM__Pickup_State__c', 'AZ');
        putIfCreateable(quoteRec, 'FreightTM__Pickup_Zip_Code__c', '85001');
        putIfCreateable(quoteRec, 'FreightTM__Delivery_City__c', 'Las Vegas');
        putIfCreateable(quoteRec, 'FreightTM__Delivery_State__c', 'NV');
        putIfCreateable(quoteRec, 'FreightTM__Delivery_Zip_Code__c', '89101');
        putIfCreateable(quoteRec, 'FreightTM__Estimated_Pickup_Time__c', System.now().addDays(1));
        putIfCreateable(quoteRec, 'FreightTM__Estimated_Delivery_Time__c', System.now().addDays(2));
        putIfCreateable(quoteRec, 'FreightTM__Customer_Rate__c', Decimal.valueOf('1800'));
        putIfCreateable(quoteRec, 'FreightTM__Rate_to_Carrier__c', Decimal.valueOf('1350'));
        putIfCreateable(quoteRec, 'FreightTM__Weight__c', Decimal.valueOf('9000'));
        putIfCreateable(quoteRec, 'FreightTM__Description__c', 'New Lane Quote conversion test');
        setFirstActivePicklist(quoteRec, 'Equipment_Type__c');
        setFirstActivePicklist(quoteRec, 'FreightTM__Mode__c');
        setCommonPicklist(
            quoteRec,
            'FreightTM__Status__c',
            'FreightTM__Load__c',
            'FreightTM__Status__c'
        );
        setCommonPicklist(
            quoteRec,
            'FreightTM__Priority__c',
            'FreightTM__Load__c',
            'FreightTM__Priority__c'
        );
        populateRequiredFields(quoteRec, new Set<String>());
    }

    public static void populateQuoteLine(SObject record) {
        setCommonPicklist(
            record,
            'Type__c',
            'FreightTM__Line_Item__c',
            'FreightTM__Type__c'
        );
        putIfCreateable(record, 'Unit_Price__c', Decimal.valueOf('125'));
        putIfCreateable(record, 'Number_of_Units__c', Decimal.valueOf('2'));
        populateRequiredFields(record, new Set<String>{'FreightTM__Lane_Quote__c'});
    }

    public static void populateQuotePay(SObject record) {
        setCommonPicklist(
            record,
            'FreightTM__Type__c',
            'FreightTM__Pay_Item__c',
            'FreightTM__Type__c'
        );
        putIfCreateable(record, 'FreightTM__Unit_Price__c', Decimal.valueOf('75'));
        putIfCreateable(record, 'FreightTM__Number_of_Units__c', Decimal.valueOf('1'));
        putIfCreateable(record, 'FreightTM__Description__c', 'Test pay item');
        populateRequiredFields(record, new Set<String>{'FreightTM__Lane_Quote__c'});
    }

    public static void populateQuoteLeg(SObject record) {
        putIfCreateable(record, 'FreightTM__Pickup_Street__c', '1 Test Street');
        putIfCreateable(record, 'FreightTM__Pickup_City__c', 'Chicago');
        putIfCreateable(record, 'FreightTM__Pickup_ZIP_Code__c', '60601');
        putIfCreateable(record, 'FreightTM__Delivery_Street__c', '2 Test Avenue');
        putIfCreateable(record, 'FreightTM__Delivery_City__c', 'Detroit');
        putIfCreateable(record, 'FreightTM__Delivery_ZIP_Code__c', '48201');
        setCommonPicklist(
            record,
            'FreightTM__Pickup_Country__c',
            'FreightTM__Leg__c',
            'FreightTM__Pickup_Country__c'
        );
        setCommonPicklist(
            record,
            'FreightTM__Pickup_State__c',
            'FreightTM__Leg__c',
            'FreightTM__Pickup_State__c'
        );
        setCommonPicklist(
            record,
            'FreightTM__Delivery_Country__c',
            'FreightTM__Leg__c',
            'FreightTM__Delivery_Country__c'
        );
        setCommonPicklist(
            record,
            'FreightTM__Delivery_State__c',
            'FreightTM__Leg__c',
            'FreightTM__Delivery_State__c'
        );
        setCommonPicklist(
            record,
            'FreightTM__Mode_of_Transportation__c',
            'FreightTM__Leg__c',
            'FreightTM__Transportation_Mode__c'
        );
        populateRequiredFields(record, new Set<String>{'FreightTM__Lane_Quote__c'});
    }

    public static Integer countRecords(String objectApiName, String whereClause) {
        return Database.countQuery(
            'SELECT COUNT() FROM ' + objectApiName +
            (String.isBlank(whereClause) ? '' : ' WHERE ' + whereClause)
        );
    }

    public static Boolean messagesContain(String expectedText) {
        for (ApexPages.Message message : ApexPages.getMessages()) {
            if (message.getSummary() != null && message.getSummary().contains(expectedText)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean hasField(
        Schema.SObjectType objectType,
        String requestedFieldName
    ) {
        if (objectType == null || String.isBlank(requestedFieldName)) {
            return false;
        }

        for (
            String fieldName :
            objectType.getDescribe().fields.getMap().keySet()
        ) {
            if (fieldName.equalsIgnoreCase(requestedFieldName)) {
                return true;
            }
        }

        return false;
    }

    public static SObject newRecord(String objectApiName) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        System.assertNotEquals(null, objectType, 'Missing object: ' + objectApiName);
        return objectType.newSObject();
    }

    /*
     * Test data setup runs in system mode. Do not gate explicit test values on
     * the running user's field-level security, because managed-package fields
     * can report isCreateable() differently across subscriber orgs.
     */
    public static void putIfCreateable(SObject record, String fieldApiName, Object value) {
        if (record == null || String.isBlank(fieldApiName) || value == null) return;
        Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
        for (String candidate : fields.keySet()) {
            if (!candidate.equalsIgnoreCase(fieldApiName)) continue;
            Schema.DescribeFieldResult fieldDescribe = fields.get(candidate).getDescribe();
            if (!fieldDescribe.isCalculated() && !fieldDescribe.isAutoNumber()) {
                record.put(fieldDescribe.getName(), value);
            }
            return;
        }
    }

    public static Id firstOptionId(List<SelectOption> options) {
        if (options == null || options.isEmpty() || String.isBlank(options[0].getValue())) {
            return null;
        }
        return Id.valueOf(options[0].getValue());
    }

    public static String allPageMessages() {
        List<String> messages = new List<String>();
        for (ApexPages.Message message : ApexPages.getMessages()) {
            messages.add(message.getSeverity() + ': ' + message.getSummary());
        }
        return String.join(messages, ' | ');
    }

    public static void setFirstActivePicklist(SObject record, String fieldApiName) {
        Schema.DescribeFieldResult describeResult = fieldDescribe(record, fieldApiName);
        if (describeResult == null || describeResult.isCalculated()) return;
        for (Schema.PicklistEntry entry : describeResult.getPicklistValues()) {
            if (entry.isActive()) {
                record.put(describeResult.getName(), entry.getValue());
                return;
            }
        }
    }

    public static void setCommonPicklist(
        SObject sourceRecord,
        String sourceField,
        String destinationObject,
        String destinationField
    ) {
        Schema.DescribeFieldResult sourceDescribe = fieldDescribe(sourceRecord, sourceField);
        Schema.SObjectType destinationType = Schema.getGlobalDescribe().get(destinationObject);
        if (sourceDescribe == null || destinationType == null || sourceDescribe.isCalculated()) return;

        Schema.DescribeFieldResult destinationDescribe;
        for (String fieldName : destinationType.getDescribe().fields.getMap().keySet()) {
            if (fieldName.equalsIgnoreCase(destinationField)) {
                destinationDescribe = destinationType.getDescribe().fields.getMap().get(fieldName).getDescribe();
                break;
            }
        }
        if (destinationDescribe == null) return;

        Set<String> destinationValues = new Set<String>();
        for (Schema.PicklistEntry entry : destinationDescribe.getPicklistValues()) {
            if (entry.isActive()) destinationValues.add(entry.getValue());
        }
        for (Schema.PicklistEntry entry : sourceDescribe.getPicklistValues()) {
            if (entry.isActive() && destinationValues.contains(entry.getValue())) {
                sourceRecord.put(sourceDescribe.getName(), entry.getValue());
                return;
            }
        }
    }

    public static void populateRequiredFields(SObject record, Set<String> skippedFields) {
        if (record == null) return;
        if (skippedFields == null) skippedFields = new Set<String>();

        Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
        for (String fieldName : fields.keySet()) {
            Schema.DescribeFieldResult d = fields.get(fieldName).getDescribe();
            if (!d.isCreateable() || d.isNillable() || d.isDefaultedOnCreate() || d.isCalculated()) continue;
            if (fieldName == 'Id' || containsIgnoreCase(skippedFields, fieldName)) continue;
            if (record.get(fieldName) != null) continue;

            Object value = defaultValue(d);
            if (value != null) record.put(fieldName, value);
        }
    }

    private static Object defaultValue(Schema.DescribeFieldResult d) {
        Schema.DisplayType fieldType = d.getType();
        if (fieldType == Schema.DisplayType.BOOLEAN) return false;
        if (fieldType == Schema.DisplayType.DATE) return Date.today();
        if (fieldType == Schema.DisplayType.DATETIME) return System.now();
        if (fieldType == Schema.DisplayType.INTEGER) return 1;
        if (fieldType == Schema.DisplayType.CURRENCY ||
            fieldType == Schema.DisplayType.DOUBLE ||
            fieldType == Schema.DisplayType.PERCENT) return Decimal.valueOf('1');
        if (fieldType == Schema.DisplayType.PICKLIST || fieldType == Schema.DisplayType.MULTIPICKLIST) {
            for (Schema.PicklistEntry entry : d.getPicklistValues()) {
                if (entry.isActive()) return entry.getValue();
            }
            return null;
        }
        if (fieldType == Schema.DisplayType.REFERENCE) {
            for (Schema.SObjectType referenceType : d.getReferenceTo()) {
                if (referenceType == User.SObjectType) return UserInfo.getUserId();
            }
            return null;
        }
        if (fieldType == Schema.DisplayType.STRING ||
            fieldType == Schema.DisplayType.TEXTAREA ||
            fieldType == Schema.DisplayType.PHONE ||
            fieldType == Schema.DisplayType.EMAIL ||
            fieldType == Schema.DisplayType.URL ||
            fieldType == Schema.DisplayType.ENCRYPTEDSTRING) {
            String value = d.getType() == Schema.DisplayType.EMAIL ? 'test@example.com' : 'Test';
            Integer lengthLimit = d.getLength();
            if (lengthLimit > 0 && value.length() > lengthLimit) value = value.substring(0, lengthLimit);
            return value;
        }
        return null;
    }

    private static Schema.DescribeFieldResult fieldDescribe(SObject record, String requestedName) {
        if (record == null || String.isBlank(requestedName)) return null;
        Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
        for (String fieldName : fields.keySet()) {
            if (fieldName.equalsIgnoreCase(requestedName)) return fields.get(fieldName).getDescribe();
        }
        return null;
    }

    private static Boolean containsIgnoreCase(Set<String> values, String candidate) {
        for (String value : values) {
            if (value != null && value.equalsIgnoreCase(candidate)) return true;
        }
        return false;
    }
}
