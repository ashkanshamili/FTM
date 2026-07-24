public without sharing class NewLaneQuoteToLoadController {

    /*
     * Source objects.
     */
    private static final String LANE_QUOTE_OBJECT =
        'FreightTM__Lane_Quote__c';

    private static final String QUOTE_LINE_OBJECT =
        'FreightTM__Quote_Line__c';

    private static final String QUOTE_PAY_OBJECT =
        'FreightTM__Quote_Pay__c';

    private static final String QUOTE_LEG_OBJECT =
        'FreightTM__Quote_Leg__c';

    /*
     * Destination objects.
     */
    private static final String LOAD_OBJECT =
        'FreightTM__Load__c';

    private static final String LINE_ITEM_OBJECT =
        'FreightTM__Line_Item__c';

    private static final String PAY_ITEM_OBJECT =
        'FreightTM__Pay_Item__c';

    private static final String LEG_OBJECT =
        'FreightTM__Leg__c';

    private static final String QUOTE_PARENT_FIELD =
        'FreightTM__Lane_Quote__c';

    private static final String LOAD_PARENT_FIELD =
        'FreightTM__Load__c';

    private static final Integer MAX_CHILD_ROWS = 200;

    public Id selectedLaneQuoteRecordTypeId { get; set; }
    public Id selectedLoadRecordTypeId { get; set; }
    public Integer rowIndex { get; set; }

    public SObject laneQuoteRecord { get; set; }

    public List<FieldWrapper> laneQuoteFields {
        get;
        private set;
    }

    public List<FieldWrapper> quoteLineFields {
        get;
        private set;
    }

    public List<FieldWrapper> quotePayFields {
        get;
        private set;
    }

    public List<FieldWrapper> quoteLegFields {
        get;
        private set;
    }

    public List<ChildRow> quoteLines { get; set; }
    public List<ChildRow> quotePays { get; set; }
    public List<ChildRow> quoteLegs { get; set; }

    private static final Set<String> EXCLUDED_LANE_QUOTE_FIELDS =
        new Set<String>{
            'Id',
            'Name',
            'OwnerId',
            'RecordTypeId',
            'CreatedById',
            'CreatedDate',
            'LastModifiedById',
            'LastModifiedDate',
            'SystemModstamp',
            'IsDeleted',
            'LastActivityDate',
            'LastViewedDate',
            'LastReferencedDate',

            // Formula fields.
            'FreightTM__Pickup_3_Zip__c',
            'FreightTM__Delivery_3_Zip__c',
            'FreightTM__Lane_3_Zips__c'
        };

    private static final Set<String> EXCLUDED_CHILD_FIELDS =
        new Set<String>{
            'Id',
            'Name',
            'OwnerId',
            'RecordTypeId',
            'CreatedById',
            'CreatedDate',
            'LastModifiedById',
            'LastModifiedDate',
            'SystemModstamp',
            'IsDeleted',
            'LastActivityDate',
            'LastViewedDate',
            'LastReferencedDate',
            QUOTE_PARENT_FIELD
        };

    /*
     * Visualforce renders left field, right field.
     */
    private static final List<String> LANE_QUOTE_FIELD_ORDER =
        new List<String>{
            'FreightTM__Pickup_Facility__c',
            'FreightTM__Delivery_Facility__c',

            'FreightTM__Pickup_Street__c',
            'FreightTM__Delivery_Street__c',

            'FreightTM__Pickup_City__c',
            'FreightTM__Delivery_City__c',

            'FreightTM__Pickup_State__c',
            'FreightTM__Delivery_State__c',

            'FreightTM__Pickup_Country__c',
            'FreightTM__Delivery_Country__c',

            'FreightTM__Pickup_Zip_Code__c',
            'FreightTM__Delivery_Zip_Code__c',

            'FreightTM__Estimated_Pickup_Time__c',
            'FreightTM__Estimated_Delivery_Time__c',

            'FreightTM__Customer__c',
            'FreightTM__Carrier__c',

            'FreightTM__Customer_Rate__c',
            'FreightTM__Rate_to_Carrier__c',

            'FreightTM__Contract__c',
            'FreightTM__Order__c',

            'FreightTM__Mode__c',
            'FreightTM__Status__c',

            'FreightTM__Priority__c',
            'FreightTM__Weight__c',

            'FreightTM__Description__c'
        };

    private static final List<String> QUOTE_LINE_FIELD_ORDER =
        new List<String>{
            'Type__c',
            'Unit_Price__c',
            'Number_of_Units__c'
        };

    private static final List<String> QUOTE_PAY_FIELD_ORDER =
        new List<String>{
            'FreightTM__Type__c',
            'FreightTM__Unit_Price__c',

            'FreightTM__Number_of_Units__c',
            'FreightTM__Description__c'
        };

    private static final List<String> QUOTE_LEG_FIELD_ORDER =
        new List<String>{
            'FreightTM__Pickup_Facility__c',
            'FreightTM__Delivery_Facility__c',

            'FreightTM__Pickup_Street__c',
            'FreightTM__Delivery_Street__c',

            'FreightTM__Pickup_City__c',
            'FreightTM__Delivery_City__c',

            'FreightTM__Pickup_State__c',
            'FreightTM__Delivery_State__c',

            'FreightTM__Pickup_Country__c',
            'FreightTM__Delivery_Country__c',

            'FreightTM__Pickup_ZIP_Code__c',
            'FreightTM__Delivery_ZIP_Code__c',

            'FreightTM__Mode_of_Transportation__c',
            'FreightTM__Carrier__c'
        };

    public NewLaneQuoteToLoadController() {
        rowIndex = 0;

        quoteLines = new List<ChildRow>();
        quotePays = new List<ChildRow>();
        quoteLegs = new List<ChildRow>();

        try {
            initializeMetadata();

            laneQuoteRecord =
                getObjectType(LANE_QUOTE_OBJECT)
                    .newSObject();

            selectedLaneQuoteRecordTypeId =
                getFirstAvailableRecordTypeId(
                    LANE_QUOTE_OBJECT
                );

            selectedLoadRecordTypeId =
                getFirstAvailableRecordTypeId(
                    LOAD_OBJECT
                );

        } catch (Exception ex) {
            ApexPages.addMessage(
                new ApexPages.Message(
                    ApexPages.Severity.FATAL,
                    getErrorMessage(ex)
                )
            );
        }
    }

    private void initializeMetadata() {
        validateObjectAccess(
            LANE_QUOTE_OBJECT,
            true
        );

        validateObjectAccess(
            QUOTE_LINE_OBJECT,
            true
        );

        validateObjectAccess(
            QUOTE_PAY_OBJECT,
            true
        );

        validateObjectAccess(
            QUOTE_LEG_OBJECT,
            true
        );

        validateObjectAccess(
            LOAD_OBJECT,
            true
        );

        validateObjectAccess(
            LINE_ITEM_OBJECT,
            true
        );

        validateObjectAccess(
            PAY_ITEM_OBJECT,
            true
        );

        validateObjectAccess(
            LEG_OBJECT,
            true
        );

        laneQuoteFields = getEditableFields(
            LANE_QUOTE_OBJECT,
            EXCLUDED_LANE_QUOTE_FIELDS,
            LANE_QUOTE_FIELD_ORDER
        );

        quoteLineFields = getEditableFields(
            QUOTE_LINE_OBJECT,
            EXCLUDED_CHILD_FIELDS,
            QUOTE_LINE_FIELD_ORDER
        );

        quotePayFields = getEditableFields(
            QUOTE_PAY_OBJECT,
            EXCLUDED_CHILD_FIELDS,
            QUOTE_PAY_FIELD_ORDER
        );

        quoteLegFields = getEditableFields(
            QUOTE_LEG_OBJECT,
            EXCLUDED_CHILD_FIELDS,
            QUOTE_LEG_FIELD_ORDER
        );
    }

    /*
     * Record Type options exclude Master.
     */
    public List<SelectOption> getLaneQuoteRecordTypeOptions() {
        return getRecordTypeOptions(
            LANE_QUOTE_OBJECT
        );
    }

    public List<SelectOption> getLoadRecordTypeOptions() {
        return getRecordTypeOptions(
            LOAD_OBJECT
        );
    }

    public Boolean getHasLaneQuoteRecordTypes() {
        return !getLaneQuoteRecordTypeOptions().isEmpty();
    }

    private static List<SelectOption> getRecordTypeOptions(
        String objectApiName
    ) {
        List<RecordTypeOptionWrapper> wrappers =
            new List<RecordTypeOptionWrapper>();

        Schema.SObjectType objectType =
            getObjectType(objectApiName);

        if (
            objectType == null ||
            !objectHasField(objectType, 'RecordTypeId')
        ) {
            return new List<SelectOption>();
        }

        for (
            Schema.RecordTypeInfo recordTypeInfo :
            objectType.getDescribe().getRecordTypeInfos()
        ) {
            if (
                recordTypeInfo.isAvailable() &&
                recordTypeInfo.getRecordTypeId() != null &&
                !recordTypeInfo.isMaster()
            ) {
                wrappers.add(
                    new RecordTypeOptionWrapper(
                        recordTypeInfo.getRecordTypeId(),
                        recordTypeInfo.getName()
                    )
                );
            }
        }

        wrappers.sort();

        List<SelectOption> options =
            new List<SelectOption>();

        for (
            RecordTypeOptionWrapper wrapper :
            wrappers
        ) {
            options.add(
                new SelectOption(
                    String.valueOf(wrapper.recordTypeId),
                    wrapper.label
                )
            );
        }

        return options;
    }

    private static Id getFirstAvailableRecordTypeId(
        String objectApiName
    ) {
        Schema.SObjectType objectType =
            getObjectType(objectApiName);

        if (
            objectType == null ||
            !objectHasField(objectType, 'RecordTypeId')
        ) {
            return null;
        }

        for (
            Schema.RecordTypeInfo recordTypeInfo :
            objectType.getDescribe().getRecordTypeInfos()
        ) {
            if (
                recordTypeInfo.isAvailable() &&
                recordTypeInfo.getRecordTypeId() != null &&
                !recordTypeInfo.isMaster()
            ) {
                return recordTypeInfo.getRecordTypeId();
            }
        }

        return null;
    }

    /*
     * Creates the Lane Quote, its children, the Load,
     * and the converted Load children in one transaction.
     */
    public PageReference createAndConvert() {
        Savepoint savePoint =
            Database.setSavepoint();

        try {
            validateRequest();

            /*
             * 1. Insert Lane Quote.
             */
            putFieldIgnoreCase(
                laneQuoteRecord,
                'RecordTypeId',
                selectedLaneQuoteRecordTypeId
            );

            List<SObject> sanitizedLaneQuotes =
                sanitizeForCreate(
                    new List<SObject>{
                        laneQuoteRecord
                    }
                );

            if (sanitizedLaneQuotes.isEmpty()) {
                throw new ConversionException(
                    'The Lane Quote could not be created.'
                );
            }

            SObject newLaneQuote =
                sanitizedLaneQuotes[0];

            insert newLaneQuote;

            /*
             * 2. Insert Lane Quote children.
             */
            List<SObject> newQuoteLines =
                cloneQuoteChildren(
                    quoteLines,
                    QUOTE_LINE_OBJECT,
                    newLaneQuote.Id
                );

            List<SObject> newQuotePays =
                cloneQuoteChildren(
                    quotePays,
                    QUOTE_PAY_OBJECT,
                    newLaneQuote.Id
                );

            List<SObject> newQuoteLegs =
                cloneQuoteChildren(
                    quoteLegs,
                    QUOTE_LEG_OBJECT,
                    newLaneQuote.Id
                );

            insertRecords(newQuoteLines);
            insertRecords(newQuotePays);
            insertRecords(newQuoteLegs);

            /*
             * 3. Create Load.
             */
            SObject newLoad =
                getObjectType(LOAD_OBJECT)
                    .newSObject();

            mapLaneQuoteToLoad(
                newLaneQuote,
                laneQuoteRecord,
                newLoad
            );

            putFieldIgnoreCase(
                newLoad,
                'RecordTypeId',
                selectedLoadRecordTypeId
            );

            resetLoadFields(newLoad);

            List<SObject> sanitizedLoads =
                sanitizeForCreate(
                    new List<SObject>{
                        newLoad
                    }
                );

            if (sanitizedLoads.isEmpty()) {
                throw new ConversionException(
                    'The Load could not be created.'
                );
            }

            newLoad = sanitizedLoads[0];

            insert newLoad;

            /*
             * 4. Convert Quote children to Load children.
             */
            List<SObject> lineItems =
                convertQuoteLines(
                    quoteLines,
                    newLoad.Id
                );

            List<SObject> payItems =
                convertQuotePays(
                    quotePays,
                    newLoad.Id
                );

            List<SObject> legs =
                convertQuoteLegs(
                    quoteLegs,
                    newLoad.Id
                );

            insertRecords(lineItems);
            insertRecords(payItems);
            insertRecords(legs);

            PageReference loadPage =
                new PageReference(
                    '/' + newLoad.Id
                );

            loadPage.setRedirect(true);
            return loadPage;

        } catch (Exception ex) {
            Database.rollback(savePoint);

            ApexPages.addMessage(
                new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    getErrorMessage(ex)
                )
            );

            return null;
        }
    }

    private static List<SObject> cloneQuoteChildren(
        List<ChildRow> sourceRows,
        String objectApiName,
        Id laneQuoteId
    ) {
        List<SObject> records =
            new List<SObject>();

        if (sourceRows == null) {
            return records;
        }

        for (ChildRow row : sourceRows) {
            if (
                row == null ||
                row.record == null
            ) {
                continue;
            }

            SObject clonedRecord =
                row.record.clone(
                    false,
                    true,
                    false,
                    false
                );

            putFieldIgnoreCase(
                clonedRecord,
                QUOTE_PARENT_FIELD,
                laneQuoteId
            );

            records.add(clonedRecord);
        }

        return records;
    }

    private static void mapLaneQuoteToLoad(
        SObject insertedLaneQuote,
        SObject editedLaneQuote,
        SObject load
    ) {
        /*
         * Source Lane Quote relationship.
         */
        putFieldIgnoreCase(
            load,
            'FreightTM__Lane_Quote__c',
            insertedLaneQuote.Id
        );

        putFieldIgnoreCase(
            load,
            'FreightTM__Quote__c',
            true
        );

        /*
         * Customer and Carrier.
         */
        copyField(
            editedLaneQuote,
            'FreightTM__Customer__c',
            load,
            'FreightTM__Customer__c'
        );

        copyField(
            editedLaneQuote,
            'FreightTM__Carrier__c',
            load,
            'FreightTM__Carrier_Obj__c'
        );

        /*
         * Rates.
         */
        copyField(
            editedLaneQuote,
            'FreightTM__Customer_Rate__c',
            load,
            'FreightTM__Rate__c'
        );

        copyField(
            editedLaneQuote,
            'FreightTM__Rate_to_Carrier__c',
            load,
            'FreightTM__Rate_to_Carrier__c'
        );

        /*
         * Pickup.
         */
        copyField(
            editedLaneQuote,
            'FreightTM__Pickup_Facility__c',
            load,
            'FreightTM__PickupFacility__c'
        );

        copyField(
            editedLaneQuote,
            'FreightTM__Pickup_Street__c',
            load,
            'FreightTM__Pickup_Address__c'
        );

        copyField(
            editedLaneQuote,
            'FreightTM__Pickup_City__c',
            load,
            'FreightTM__Pickup_City__c'
        );

        copyPicklistField(
            editedLaneQuote,
            'FreightTM__Pickup_Country__c',
            load,
            'FreightTM__Pickup_Country__c'
        );

        copyPicklistField(
            editedLaneQuote,
            'FreightTM__Pickup_State__c',
            load,
            'FreightTM__Pickup_State__c'
        );

        copyField(
            editedLaneQuote,
            'FreightTM__Pickup_Zip_Code__c',
            load,
            'FreightTM__Pickup_Zip_Code__c'
        );

        copyField(
            editedLaneQuote,
            'FreightTM__Estimated_Pickup_Time__c',
            load,
            'FreightTM__Pickup_Arrival__c'
        );

        /*
         * Delivery.
         */
        copyField(
            editedLaneQuote,
            'FreightTM__Delivery_Facility__c',
            load,
            'FreightTM__DeliveryFacility__c'
        );

        copyField(
            editedLaneQuote,
            'FreightTM__Delivery_Street__c',
            load,
            'FreightTM__Delivery_Address__c'
        );

        copyField(
            editedLaneQuote,
            'FreightTM__Delivery_City__c',
            load,
            'FreightTM__Delivery_City__c'
        );

        copyPicklistField(
            editedLaneQuote,
            'FreightTM__Delivery_Country__c',
            load,
            'FreightTM__Delivery_Country__c'
        );

        copyPicklistField(
            editedLaneQuote,
            'FreightTM__Delivery_State__c',
            load,
            'FreightTM__Delivery_State__c'
        );

        copyField(
            editedLaneQuote,
            'FreightTM__Delivery_Zip_Code__c',
            load,
            'FreightTM__Delivery_Zip_Code__c'
        );

        copyField(
            editedLaneQuote,
            'FreightTM__Estimated_Delivery_Time__c',
            load,
            'FreightTM__Delivery_Arrival__c'
        );

        /*
         * Other fields.
         */
        copyPicklistField(
            editedLaneQuote,
            'FreightTM__Priority__c',
            load,
            'FreightTM__Priority__c'
        );

        copyPicklistField(
            editedLaneQuote,
            'FreightTM__Status__c',
            load,
            'FreightTM__Status__c'
        );

        copyField(
            editedLaneQuote,
            'FreightTM__Weight__c',
            load,
            'FreightTM__Weight__c'
        );

        copyField(
            editedLaneQuote,
            'FreightTM__Description__c',
            load,
            'FreightTM__Remarks__c'
        );
    }

    private static List<SObject> convertQuoteLines(
        List<ChildRow> sourceRows,
        Id loadId
    ) {
        List<SObject> destination =
            new List<SObject>();

        if (sourceRows == null) {
            return destination;
        }

        for (ChildRow row : sourceRows) {
            SObject lineItem =
                getObjectType(
                    LINE_ITEM_OBJECT
                ).newSObject();

            putFieldIgnoreCase(
                lineItem,
                LOAD_PARENT_FIELD,
                loadId
            );

            copyPicklistField(
                row.record,
                'Type__c',
                lineItem,
                'FreightTM__Type__c'
            );

            copyField(
                row.record,
                'Unit_Price__c',
                lineItem,
                'FreightTM__Unit_Price__c'
            );

            copyField(
                row.record,
                'Number_of_Units__c',
                lineItem,
                'FreightTM__Number_of_Units__c'
            );

            destination.add(lineItem);
        }

        return destination;
    }

    private static List<SObject> convertQuotePays(
        List<ChildRow> sourceRows,
        Id loadId
    ) {
        List<SObject> destination =
            new List<SObject>();

        if (sourceRows == null) {
            return destination;
        }

        for (ChildRow row : sourceRows) {
            SObject payItem =
                getObjectType(
                    PAY_ITEM_OBJECT
                ).newSObject();

            putFieldIgnoreCase(
                payItem,
                LOAD_PARENT_FIELD,
                loadId
            );

            copyPicklistField(
                row.record,
                'FreightTM__Type__c',
                payItem,
                'FreightTM__Type__c'
            );

            copyField(
                row.record,
                'FreightTM__Unit_Price__c',
                payItem,
                'FreightTM__Unit_Price__c'
            );

            copyField(
                row.record,
                'FreightTM__Number_of_Units__c',
                payItem,
                'FreightTM__Number_of_Units__c'
            );

            copyField(
                row.record,
                'FreightTM__Description__c',
                payItem,
                'FreightTM__Description__c'
            );

            destination.add(payItem);
        }

        return destination;
    }

    private static List<SObject> convertQuoteLegs(
        List<ChildRow> sourceRows,
        Id loadId
    ) {
        List<SObject> destination =
            new List<SObject>();

        if (sourceRows == null) {
            return destination;
        }

        for (ChildRow row : sourceRows) {
            SObject leg =
                getObjectType(
                    LEG_OBJECT
                ).newSObject();

            putFieldIgnoreCase(
                leg,
                LOAD_PARENT_FIELD,
                loadId
            );

            copyField(
                row.record,
                'FreightTM__Carrier__c',
                leg,
                'FreightTM__Carrier__c'
            );

            copyField(
                row.record,
                'FreightTM__Pickup_Facility__c',
                leg,
                'FreightTM__Pickup_Facility__c'
            );

            copyField(
                row.record,
                'FreightTM__Pickup_Street__c',
                leg,
                'FreightTM__Pickup_Street__c'
            );

            copyField(
                row.record,
                'FreightTM__Pickup_City__c',
                leg,
                'FreightTM__Pickup_City__c'
            );

            copyPicklistField(
                row.record,
                'FreightTM__Pickup_Country__c',
                leg,
                'FreightTM__Pickup_Country__c'
            );

            copyPicklistField(
                row.record,
                'FreightTM__Pickup_State__c',
                leg,
                'FreightTM__Pickup_State__c'
            );

            copyField(
                row.record,
                'FreightTM__Pickup_ZIP_Code__c',
                leg,
                'FreightTM__Pickup_ZIP_Code__c'
            );

            copyField(
                row.record,
                'FreightTM__Delivery_Facility__c',
                leg,
                'FreightTM__Delivery_Facility__c'
            );

            copyField(
                row.record,
                'FreightTM__Delivery_Street__c',
                leg,
                'FreightTM__Delivery_Street__c'
            );

            copyField(
                row.record,
                'FreightTM__Delivery_City__c',
                leg,
                'FreightTM__Delivery_City__c'
            );

            copyPicklistField(
                row.record,
                'FreightTM__Delivery_Country__c',
                leg,
                'FreightTM__Delivery_Country__c'
            );

            copyPicklistField(
                row.record,
                'FreightTM__Delivery_State__c',
                leg,
                'FreightTM__Delivery_State__c'
            );

            copyField(
                row.record,
                'FreightTM__Delivery_ZIP_Code__c',
                leg,
                'FreightTM__Delivery_ZIP_Code__c'
            );

            copyPicklistField(
                row.record,
                'FreightTM__Mode_of_Transportation__c',
                leg,
                'FreightTM__Transportation_Mode__c'
            );

            destination.add(leg);
        }

        return destination;
    }

    private void validateRequest() {
        if (
            getHasLaneQuoteRecordTypes() &&
            !userCanUseRecordType(
                LANE_QUOTE_OBJECT,
                selectedLaneQuoteRecordTypeId
            )
        ) {
            throw new ConversionException(
                'Select an available Lane Quote Record Type.'
            );
        }

        if (
            !userCanUseRecordType(
                LOAD_OBJECT,
                selectedLoadRecordTypeId
            )
        ) {
            throw new ConversionException(
                'Select an available Load Record Type.'
            );
        }

        validateChildCount(
            'Quote Lines',
            quoteLines
        );

        validateChildCount(
            'Quote Pays',
            quotePays
        );

        validateChildCount(
            'Quote Legs',
            quoteLegs
        );
    }

    private static Boolean userCanUseRecordType(
        String objectApiName,
        Id recordTypeId
    ) {
        if (recordTypeId == null) {
            return false;
        }

        Schema.SObjectType objectType =
            getObjectType(objectApiName);

        if (objectType == null) {
            return false;
        }

        Map<Id, Schema.RecordTypeInfo> recordTypes =
            objectType
                .getDescribe()
                .getRecordTypeInfosById();

        if (!recordTypes.containsKey(recordTypeId)) {
            return false;
        }

        Schema.RecordTypeInfo recordTypeInfo =
            recordTypes.get(recordTypeId);

        return recordTypeInfo.isAvailable() &&
            !recordTypeInfo.isMaster();
    }

    private static void resetLoadFields(
        SObject load
    ) {
        putFieldIgnoreCase(
            load,
            'FreightTM__Distance__c',
            null
        );

        putFieldIgnoreCase(
            load,
            'FreightTM__Deadhead__c',
            null
        );

        putFieldIgnoreCase(
            load,
            'Exception_Reason__c',
            null
        );

        putFieldIgnoreCase(
            load,
            'FreightTM__Driver_Remarks__c',
            null
        );

        putFieldIgnoreCase(
            load,
            'Driver_Portal_Token_Hash__c',
            null
        );

        putFieldIgnoreCase(
            load,
            'Driver_Portal_Expires_At__c',
            null
        );

        putFieldIgnoreCase(
            load,
            'Driver_Portal_Link__c',
            null
        );

        putFieldIgnoreCase(
            load,
            'Driver_Portal_Last_Opened__c',
            null
        );

        putFieldIgnoreCase(
            load,
            'Driver_Portal_Last_Device__c',
            null
        );

        putFieldIgnoreCase(
            load,
            'Driver_Portal_Active__c',
            false
        );

        putFieldIgnoreCase(
            load,
            'At_Shipping_Signature__c',
            false
        );

        putFieldIgnoreCase(
            load,
            'In_Transit_to_Delivery_Signature__c',
            false
        );

        putFieldIgnoreCase(
            load,
            'At_Receiving_Signature__c',
            false
        );

        putFieldIgnoreCase(
            load,
            'Delivered_Signature__c',
            false
        );
    }

    /*
     * Add and remove child rows.
     */
    public void addQuoteLine() {
        addChildRow(
            quoteLines,
            QUOTE_LINE_OBJECT
        );

        putFieldIgnoreCase(
            quoteLines[quoteLines.size() - 1].record,
            'Number_of_Units__c',
            Decimal.valueOf('1.00')
        );
    }

    public void addQuotePay() {
        addChildRow(
            quotePays,
            QUOTE_PAY_OBJECT
        );

        putFieldIgnoreCase(
            quotePays[quotePays.size() - 1].record,
            'FreightTM__Number_of_Units__c',
            Decimal.valueOf('1.00')
        );
    }

    public void addQuoteLeg() {
        addChildRow(
            quoteLegs,
            QUOTE_LEG_OBJECT
        );
    }

    public void removeQuoteLine() {
        removeChildRow(quoteLines);
    }

    public void removeQuotePay() {
        removeChildRow(quotePays);
    }

    public void removeQuoteLeg() {
        removeChildRow(quoteLegs);
    }

    private static void addChildRow(
        List<ChildRow> rows,
        String objectApiName
    ) {
        if (
            rows == null ||
            rows.size() >= MAX_CHILD_ROWS
        ) {
            throw new ConversionException(
                'The maximum number of child records has been reached.'
            );
        }

        Schema.SObjectType objectType =
            getObjectType(objectApiName);

        if (objectType == null) {
            throw new ConversionException(
                'Object does not exist: ' +
                objectApiName
            );
        }

        rows.add(
            new ChildRow(
                objectType.newSObject()
            )
        );
    }

    private void removeChildRow(
        List<ChildRow> rows
    ) {
        if (
            rows == null ||
            rowIndex == null ||
            rowIndex < 0 ||
            rowIndex >= rows.size()
        ) {
            return;
        }

        rows.remove(rowIndex);
    }

    private static void validateChildCount(
        String sectionName,
        List<ChildRow> rows
    ) {
        if (
            rows != null &&
            rows.size() > MAX_CHILD_ROWS
        ) {
            throw new ConversionException(
                sectionName +
                ' cannot contain more than ' +
                MAX_CHILD_ROWS +
                ' records.'
            );
        }
    }

    public PageReference cancel() {
        PageReference listPage =
            new PageReference(
                '/lightning/o/' +
                LANE_QUOTE_OBJECT +
                '/list'
            );

        listPage.setRedirect(true);
        return listPage;
    }

    /*
     * Dynamic editable fields.
     */
    private static List<FieldWrapper> getEditableFields(
        String objectApiName,
        Set<String> excludedFields,
        List<String> configuredOrder
    ) {
        Schema.SObjectType objectType =
            getObjectType(objectApiName);

        if (objectType == null) {
            throw new ConversionException(
                'Object does not exist: ' +
                objectApiName
            );
        }

        Map<String, Schema.SObjectField> fieldMap =
            objectType
                .getDescribe()
                .fields
                .getMap();

        Set<String> normalizedExcluded =
            normalizeFieldSet(excludedFields);

        Map<String, FieldWrapper> fieldsByName =
            new Map<String, FieldWrapper>();

        for (String mapFieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult describe =
                fieldMap
                    .get(mapFieldName)
                    .getDescribe();

            String fieldName =
                describe.getName();

            if (
                normalizedExcluded.contains(
                    fieldName.toLowerCase()
                )
            ) {
                continue;
            }

            Schema.DisplayType fieldType =
                describe.getType();

            if (
                !describe.isAccessible() ||
                !describe.isCreateable() ||
                describe.isCalculated() ||
                describe.isAutoNumber() ||
                fieldType == Schema.DisplayType.BASE64 ||
                fieldType == Schema.DisplayType.ADDRESS ||
                fieldType == Schema.DisplayType.LOCATION ||
                fieldType == Schema.DisplayType.ENCRYPTEDSTRING
            ) {
                continue;
            }

            fieldsByName.put(
                fieldName.toLowerCase(),
                new FieldWrapper(
                    fieldName,
                    describe.getLabel(),
                    describe.isNillable()
                )
            );
        }

        return orderFields(
            fieldsByName,
            configuredOrder
        );
    }

    private static List<FieldWrapper> orderFields(
        Map<String, FieldWrapper> fieldsByName,
        List<String> configuredOrder
    ) {
        List<FieldWrapper> ordered =
            new List<FieldWrapper>();

        Set<String> used =
            new Set<String>();

        if (configuredOrder != null) {
            for (String configuredField : configuredOrder) {
                String normalized =
                    configuredField.toLowerCase();

                if (
                    fieldsByName.containsKey(normalized) &&
                    !used.contains(normalized)
                ) {
                    ordered.add(
                        fieldsByName.get(normalized)
                    );

                    used.add(normalized);
                }
            }
        }

        List<FieldWrapper> remaining =
            new List<FieldWrapper>();

        for (String fieldName : fieldsByName.keySet()) {
            if (!used.contains(fieldName)) {
                remaining.add(
                    fieldsByName.get(fieldName)
                );
            }
        }

        remaining.sort();
        ordered.addAll(remaining);

        return ordered;
    }

    /*
     * Field-copy and security helpers.
     */
    private static void copyField(
        SObject source,
        String sourceField,
        SObject destination,
        String destinationField
    ) {
        putFieldIgnoreCase(
            destination,
            destinationField,
            getFieldValueIgnoreCase(
                source,
                sourceField
            )
        );
    }

    private static void copyPicklistField(
        SObject source,
        String sourceField,
        SObject destination,
        String destinationField
    ) {
        Object value =
            getFieldValueIgnoreCase(
                source,
                sourceField
            );

        if (value == null) {
            return;
        }

        String stringValue =
            String.valueOf(value);

        if (
            destinationPicklistContains(
                destination,
                destinationField,
                stringValue
            )
        ) {
            putFieldIgnoreCase(
                destination,
                destinationField,
                stringValue
            );
        }
    }

    private static Boolean destinationPicklistContains(
        SObject destination,
        String fieldName,
        String requestedValue
    ) {
        Schema.DescribeFieldResult describe =
            getFieldDescribe(
                destination.getSObjectType(),
                fieldName
            );

        if (describe == null) {
            return false;
        }

        if (
            describe.getType() !=
                Schema.DisplayType.PICKLIST &&
            describe.getType() !=
                Schema.DisplayType.MULTIPICKLIST
        ) {
            return true;
        }

        for (
            Schema.PicklistEntry entry :
            describe.getPicklistValues()
        ) {
            if (
                entry.isActive() &&
                entry.getValue() == requestedValue
            ) {
                return true;
            }
        }

        return false;
    }

    private static Object getFieldValueIgnoreCase(
        SObject record,
        String fieldName
    ) {
        Schema.DescribeFieldResult describe =
            getFieldDescribe(
                record.getSObjectType(),
                fieldName
            );

        if (describe == null) {
            return null;
        }

        return record.get(
            describe.getName()
        );
    }

    private static void putFieldIgnoreCase(
        SObject record,
        String fieldName,
        Object value
    ) {
        Schema.DescribeFieldResult describe =
            getFieldDescribe(
                record.getSObjectType(),
                fieldName
            );

        if (
            describe != null &&
            describe.isCreateable()
        ) {
            record.put(
                describe.getName(),
                value
            );
        }
    }

    private static Schema.DescribeFieldResult getFieldDescribe(
        Schema.SObjectType objectType,
        String requestedField
    ) {
        Map<String, Schema.SObjectField> fieldMap =
            objectType
                .getDescribe()
                .fields
                .getMap();

        for (String fieldName : fieldMap.keySet()) {
            if (
                fieldName.equalsIgnoreCase(
                    requestedField
                )
            ) {
                return fieldMap
                    .get(fieldName)
                    .getDescribe();
            }
        }

        return null;
    }

    private static void insertRecords(
        List<SObject> records
    ) {
        if (
            records == null ||
            records.isEmpty()
        ) {
            return;
        }

        List<SObject> sanitized =
            sanitizeForCreate(records);

        if (!sanitized.isEmpty()) {
            insert sanitized;
        }
    }

    private static List<SObject> sanitizeForCreate(
        List<SObject> records
    ) {
        SObjectAccessDecision decision =
            Security.stripInaccessible(
                AccessType.CREATABLE,
                records
            );

        return decision.getRecords();
    }

    private static void validateObjectAccess(
        String objectApiName,
        Boolean requireCreate
    ) {
        Schema.SObjectType objectType =
            getObjectType(objectApiName);

        if (objectType == null) {
            throw new ConversionException(
                'Object does not exist: ' +
                objectApiName
            );
        }

        Schema.DescribeSObjectResult describe =
            objectType.getDescribe();

        if (
            requireCreate &&
            !describe.isCreateable()
        ) {
            throw new ConversionException(
                'You do not have create access to ' +
                describe.getLabelPlural() +
                '.'
            );
        }
    }


    private static Boolean objectHasField(
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

    private static Schema.SObjectType getObjectType(
        String requestedObject
    ) {
        if (String.isBlank(requestedObject)) {
            return null;
        }

        Map<String, Schema.SObjectType> globalDescribe =
            Schema.getGlobalDescribe();

        for (String objectName : globalDescribe.keySet()) {
            if (
                objectName.equalsIgnoreCase(
                    requestedObject
                )
            ) {
                return globalDescribe.get(objectName);
            }
        }

        return null;
    }

    private static Set<String> normalizeFieldSet(
        Set<String> fieldNames
    ) {
        Set<String> normalized =
            new Set<String>();

        if (fieldNames == null) {
            return normalized;
        }

        for (String fieldName : fieldNames) {
            if (!String.isBlank(fieldName)) {
                normalized.add(
                    fieldName.toLowerCase()
                );
            }
        }

        return normalized;
    }

    private static String getErrorMessage(
        Exception ex
    ) {
        if (ex instanceof DmlException) {
            DmlException dmlException =
                (DmlException)ex;

            if (dmlException.getNumDml() > 0) {
                return dmlException.getDmlMessage(0);
            }
        }

        return ex.getMessage();
    }

    public class FieldWrapper
        implements Comparable {

        public String apiName { get; set; }
        public String label { get; set; }
        public Boolean required { get; set; }

        public FieldWrapper(
            String apiName,
            String label,
            Boolean nillable
        ) {
            this.apiName = apiName;
            this.label = label;
            this.required = !nillable;
        }

        public Integer compareTo(Object otherObject) {
            FieldWrapper otherField =
                (FieldWrapper)otherObject;

            return label
                .toLowerCase()
                .compareTo(
                    otherField.label.toLowerCase()
                );
        }
    }

    public class RecordTypeOptionWrapper
        implements Comparable {

        public Id recordTypeId { get; set; }
        public String label { get; set; }

        public RecordTypeOptionWrapper(
            Id recordTypeId,
            String label
        ) {
            this.recordTypeId = recordTypeId;
            this.label = label;
        }

        public Integer compareTo(Object otherObject) {
            RecordTypeOptionWrapper otherOption =
                (RecordTypeOptionWrapper)otherObject;

            return label
                .toLowerCase()
                .compareTo(
                    otherOption.label.toLowerCase()
                );
        }
    }

    public class ChildRow {
        public SObject record { get; set; }

        public ChildRow(SObject record) {
            this.record = record;
        }
    }

    public class ConversionException
        extends Exception {
    }
}