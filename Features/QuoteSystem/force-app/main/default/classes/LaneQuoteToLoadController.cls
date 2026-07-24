public without sharing class LaneQuoteToLoadController {

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

    /*
     * Parent fields.
     */
    private static final String QUOTE_CHILD_PARENT_FIELD =
        'FreightTM__Lane_Quote__c';

    private static final String LOAD_CHILD_PARENT_FIELD =
        'FreightTM__Load__c';

    private static final Integer MAX_CHILD_ROWS = 200;

    public Id sourceLaneQuoteId { get; private set; }
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

            /*
             * Formula fields.
             */
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
            QUOTE_CHILD_PARENT_FIELD
        };

    /*
     * Two-column ordering:
     * left field, right field, left field, right field.
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

    public LaneQuoteToLoadController() {
        rowIndex = 0;

        quoteLines = new List<ChildRow>();
        quotePays = new List<ChildRow>();
        quoteLegs = new List<ChildRow>();

        String recordId =
            ApexPages.currentPage()
                .getParameters()
                .get('id');

        if (String.isBlank(recordId)) {
            ApexPages.addMessage(
                new ApexPages.Message(
                    ApexPages.Severity.FATAL,
                    'A Lane Quote record ID is required.'
                )
            );
            return;
        }

        try {
            sourceLaneQuoteId = Id.valueOf(recordId);

            initializeMetadata();
            initializeLoadRecordType();
            loadExistingData();

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
            true,
            false
        );

        validateObjectAccess(
            QUOTE_LINE_OBJECT,
            true,
            false
        );

        validateObjectAccess(
            QUOTE_PAY_OBJECT,
            true,
            false
        );

        validateObjectAccess(
            QUOTE_LEG_OBJECT,
            true,
            false
        );

        validateObjectAccess(
            LOAD_OBJECT,
            false,
            true
        );

        validateObjectAccess(
            LINE_ITEM_OBJECT,
            false,
            true
        );

        validateObjectAccess(
            PAY_ITEM_OBJECT,
            false,
            true
        );

        validateObjectAccess(
            LEG_OBJECT,
            false,
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

    private void initializeLoadRecordType() {
        for (
            Schema.RecordTypeInfo recordTypeInfo :
            getObjectType(LOAD_OBJECT)
                .getDescribe()
                .getRecordTypeInfos()
        ) {
            if (
                recordTypeInfo.isAvailable() &&
                recordTypeInfo.getRecordTypeId() != null &&
                !recordTypeInfo.isMaster()
            ) {
                selectedLoadRecordTypeId =
                    recordTypeInfo.getRecordTypeId();

                return;
            }
        }

        throw new LaneQuoteConversionException(
            'No available non-Master Load Record Type was found.'
        );
    }

    public List<SelectOption> getLoadRecordTypeOptions() {
        List<RecordTypeOptionWrapper> wrappers =
            new List<RecordTypeOptionWrapper>();

        for (
            Schema.RecordTypeInfo recordTypeInfo :
            getObjectType(LOAD_OBJECT)
                .getDescribe()
                .getRecordTypeInfos()
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

    private void loadExistingData() {
        laneQuoteRecord =
            querySourceLaneQuote().clone(
                true,
                true,
                false,
                false
            );

        quoteLines = queryChildRecords(
            QUOTE_LINE_OBJECT,
            quoteLineFields
        );

        quotePays = queryChildRecords(
            QUOTE_PAY_OBJECT,
            quotePayFields
        );

        quoteLegs = queryChildRecords(
            QUOTE_LEG_OBJECT,
            quoteLegFields
        );
    }

    private SObject querySourceLaneQuote() {
        List<String> selectedFields =
            getFieldNames(laneQuoteFields);

        if (
            !containsFieldIgnoreCase(
                selectedFields,
                'Id'
            )
        ) {
            selectedFields.add('Id');
        }

        selectedFields =
            removeDuplicateFields(selectedFields);

        String soql =
            'SELECT ' +
            String.join(selectedFields, ', ') +
            ' FROM ' +
            LANE_QUOTE_OBJECT +
            ' WHERE Id = :sourceLaneQuoteId' +
            ' LIMIT 1';

        List<SObject> records =
            Database.query(soql);

        if (records.isEmpty()) {
            throw new LaneQuoteConversionException(
                'The Lane Quote was not found or is not accessible.'
            );
        }

        return records[0];
    }

    private List<ChildRow> queryChildRecords(
        String objectApiName,
        List<FieldWrapper> fields
    ) {
        List<String> selectedFields =
            getFieldNames(fields);

        if (
            !containsFieldIgnoreCase(
                selectedFields,
                'Id'
            )
        ) {
            selectedFields.add('Id');
        }

        selectedFields =
            removeDuplicateFields(selectedFields);

        String soql =
            'SELECT ' +
            String.join(selectedFields, ', ') +
            ' FROM ' +
            objectApiName +
            ' WHERE ' +
            QUOTE_CHILD_PARENT_FIELD +
            ' = :sourceLaneQuoteId' +
            ' ORDER BY CreatedDate';

        List<ChildRow> rows =
            new List<ChildRow>();

        for (
            SObject queriedRecord :
            Database.query(soql)
        ) {
            rows.add(
                new ChildRow(
                    queriedRecord.clone(
                        false,
                        true,
                        false,
                        false
                    )
                )
            );
        }

        return rows;
    }

    public PageReference convertToLoad() {
        Savepoint savePoint =
            Database.setSavepoint();

        try {
            validateConversion();

            SObject newLoad =
                getObjectType(LOAD_OBJECT)
                    .newSObject();

            mapLaneQuoteToLoad(
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
                    new List<SObject>{ newLoad }
                );

            if (sanitizedLoads.isEmpty()) {
                throw new LaneQuoteConversionException(
                    'The Load could not be created.'
                );
            }

            newLoad = sanitizedLoads[0];

            insert newLoad;

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

    private static void mapLaneQuoteToLoad(
        SObject laneQuote,
        SObject load
    ) {
        /*
         * Link the Load back to its source Lane Quote.
         */
        putFieldIgnoreCase(
            load,
            'FreightTM__Lane_Quote__c',
            laneQuote.get('Id')
        );

        putFieldIgnoreCase(
            load,
            'FreightTM__Quote__c',
            true
        );

        /*
         * Customer and carrier.
         */
        copyField(
            laneQuote,
            'FreightTM__Customer__c',
            load,
            'FreightTM__Customer__c'
        );

        /*
         * Lane Quote Carrier points to Carrier.
         * Load Carrier_Obj points to Carrier.
         */
        copyField(
            laneQuote,
            'FreightTM__Carrier__c',
            load,
            'FreightTM__Carrier_Obj__c'
        );

        /*
         * Rates.
         */
        copyField(
            laneQuote,
            'FreightTM__Customer_Rate__c',
            load,
            'FreightTM__Rate__c'
        );

        copyField(
            laneQuote,
            'FreightTM__Rate_to_Carrier__c',
            load,
            'FreightTM__Rate_to_Carrier__c'
        );

        /*
         * Pickup.
         */
        copyField(
            laneQuote,
            'FreightTM__Pickup_Facility__c',
            load,
            'FreightTM__PickupFacility__c'
        );

        copyField(
            laneQuote,
            'FreightTM__Pickup_Street__c',
            load,
            'FreightTM__Pickup_Address__c'
        );

        copyField(
            laneQuote,
            'FreightTM__Pickup_City__c',
            load,
            'FreightTM__Pickup_City__c'
        );

        copyPicklistField(
            laneQuote,
            'FreightTM__Pickup_Country__c',
            load,
            'FreightTM__Pickup_Country__c'
        );

        copyPicklistField(
            laneQuote,
            'FreightTM__Pickup_State__c',
            load,
            'FreightTM__Pickup_State__c'
        );

        copyField(
            laneQuote,
            'FreightTM__Pickup_Zip_Code__c',
            load,
            'FreightTM__Pickup_Zip_Code__c'
        );

        copyField(
            laneQuote,
            'FreightTM__Estimated_Pickup_Time__c',
            load,
            'FreightTM__Pickup_Arrival__c'
        );

        /*
         * Delivery.
         */
        copyField(
            laneQuote,
            'FreightTM__Delivery_Facility__c',
            load,
            'FreightTM__DeliveryFacility__c'
        );

        copyField(
            laneQuote,
            'FreightTM__Delivery_Street__c',
            load,
            'FreightTM__Delivery_Address__c'
        );

        copyField(
            laneQuote,
            'FreightTM__Delivery_City__c',
            load,
            'FreightTM__Delivery_City__c'
        );

        copyPicklistField(
            laneQuote,
            'FreightTM__Delivery_Country__c',
            load,
            'FreightTM__Delivery_Country__c'
        );

        copyPicklistField(
            laneQuote,
            'FreightTM__Delivery_State__c',
            load,
            'FreightTM__Delivery_State__c'
        );

        copyField(
            laneQuote,
            'FreightTM__Delivery_Zip_Code__c',
            load,
            'FreightTM__Delivery_Zip_Code__c'
        );

        copyField(
            laneQuote,
            'FreightTM__Estimated_Delivery_Time__c',
            load,
            'FreightTM__Delivery_Arrival__c'
        );

        /*
         * Other compatible fields.
         */
        copyPicklistField(
            laneQuote,
            'FreightTM__Priority__c',
            load,
            'FreightTM__Priority__c'
        );

        copyPicklistField(
            laneQuote,
            'FreightTM__Status__c',
            load,
            'FreightTM__Status__c'
        );

        copyField(
            laneQuote,
            'FreightTM__Weight__c',
            load,
            'FreightTM__Weight__c'
        );

        copyField(
            laneQuote,
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

        for (ChildRow sourceRow : sourceRows) {
            SObject lineItem =
                getObjectType(
                    LINE_ITEM_OBJECT
                ).newSObject();

            putFieldIgnoreCase(
                lineItem,
                LOAD_CHILD_PARENT_FIELD,
                loadId
            );

            copyPicklistField(
                sourceRow.record,
                'Type__c',
                lineItem,
                'FreightTM__Type__c'
            );

            copyField(
                sourceRow.record,
                'Unit_Price__c',
                lineItem,
                'FreightTM__Unit_Price__c'
            );

            copyField(
                sourceRow.record,
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

        for (ChildRow sourceRow : sourceRows) {
            SObject payItem =
                getObjectType(
                    PAY_ITEM_OBJECT
                ).newSObject();

            putFieldIgnoreCase(
                payItem,
                LOAD_CHILD_PARENT_FIELD,
                loadId
            );

            copyPicklistField(
                sourceRow.record,
                'FreightTM__Type__c',
                payItem,
                'FreightTM__Type__c'
            );

            copyField(
                sourceRow.record,
                'FreightTM__Unit_Price__c',
                payItem,
                'FreightTM__Unit_Price__c'
            );

            copyField(
                sourceRow.record,
                'FreightTM__Number_of_Units__c',
                payItem,
                'FreightTM__Number_of_Units__c'
            );

            copyField(
                sourceRow.record,
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

        for (ChildRow sourceRow : sourceRows) {
            SObject leg =
                getObjectType(
                    LEG_OBJECT
                ).newSObject();

            putFieldIgnoreCase(
                leg,
                LOAD_CHILD_PARENT_FIELD,
                loadId
            );

            copyField(
                sourceRow.record,
                'FreightTM__Carrier__c',
                leg,
                'FreightTM__Carrier__c'
            );

            copyField(
                sourceRow.record,
                'FreightTM__Pickup_Facility__c',
                leg,
                'FreightTM__Pickup_Facility__c'
            );

            copyField(
                sourceRow.record,
                'FreightTM__Pickup_Street__c',
                leg,
                'FreightTM__Pickup_Street__c'
            );

            copyField(
                sourceRow.record,
                'FreightTM__Pickup_City__c',
                leg,
                'FreightTM__Pickup_City__c'
            );

            copyPicklistField(
                sourceRow.record,
                'FreightTM__Pickup_Country__c',
                leg,
                'FreightTM__Pickup_Country__c'
            );

            copyPicklistField(
                sourceRow.record,
                'FreightTM__Pickup_State__c',
                leg,
                'FreightTM__Pickup_State__c'
            );

            copyField(
                sourceRow.record,
                'FreightTM__Pickup_ZIP_Code__c',
                leg,
                'FreightTM__Pickup_ZIP_Code__c'
            );

            copyField(
                sourceRow.record,
                'FreightTM__Delivery_Facility__c',
                leg,
                'FreightTM__Delivery_Facility__c'
            );

            copyField(
                sourceRow.record,
                'FreightTM__Delivery_Street__c',
                leg,
                'FreightTM__Delivery_Street__c'
            );

            copyField(
                sourceRow.record,
                'FreightTM__Delivery_City__c',
                leg,
                'FreightTM__Delivery_City__c'
            );

            copyPicklistField(
                sourceRow.record,
                'FreightTM__Delivery_Country__c',
                leg,
                'FreightTM__Delivery_Country__c'
            );

            copyPicklistField(
                sourceRow.record,
                'FreightTM__Delivery_State__c',
                leg,
                'FreightTM__Delivery_State__c'
            );

            copyField(
                sourceRow.record,
                'FreightTM__Delivery_ZIP_Code__c',
                leg,
                'FreightTM__Delivery_ZIP_Code__c'
            );

            copyPicklistField(
                sourceRow.record,
                'FreightTM__Mode_of_Transportation__c',
                leg,
                'FreightTM__Transportation_Mode__c'
            );

            destination.add(leg);
        }

        return destination;
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

    private void validateConversion() {
        if (
            selectedLoadRecordTypeId == null ||
            !userCanUseLoadRecordType(
                selectedLoadRecordTypeId
            )
        ) {
            throw new LaneQuoteConversionException(
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

    private static Boolean userCanUseLoadRecordType(
        Id recordTypeId
    ) {
        if (recordTypeId == null) {
            return false;
        }

        Map<Id, Schema.RecordTypeInfo> recordTypes =
            getObjectType(LOAD_OBJECT)
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
        if (rows.size() >= MAX_CHILD_ROWS) {
            throw new LaneQuoteConversionException(
                'The maximum number of child records has been reached.'
            );
        }

        rows.add(
            new ChildRow(
                getObjectType(
                    objectApiName
                ).newSObject()
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
            throw new LaneQuoteConversionException(
                sectionName +
                ' cannot contain more than ' +
                MAX_CHILD_ROWS +
                ' records.'
            );
        }
    }

    public PageReference cancel() {
        PageReference sourcePage =
            new PageReference(
                '/' + sourceLaneQuoteId
            );

        sourcePage.setRedirect(true);
        return sourcePage;
    }

    /*
     * Dynamic field metadata.
     */
    private static List<FieldWrapper> getEditableFields(
        String objectApiName,
        Set<String> excludedFields,
        List<String> configuredOrder
    ) {
        Schema.SObjectType objectType =
            getObjectType(objectApiName);

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
            Schema.DescribeFieldResult fieldDescribe =
                fieldMap
                    .get(mapFieldName)
                    .getDescribe();

            String fieldName =
                fieldDescribe.getName();

            if (
                normalizedExcluded.contains(
                    fieldName.toLowerCase()
                )
            ) {
                continue;
            }

            Schema.DisplayType fieldType =
                fieldDescribe.getType();

            if (
                !fieldDescribe.isAccessible() ||
                !fieldDescribe.isCreateable() ||
                fieldDescribe.isCalculated() ||
                fieldDescribe.isAutoNumber() ||
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
                    fieldDescribe.getLabel(),
                    fieldDescribe.isNillable()
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

        for (String configuredField : configuredOrder) {
            String normalized =
                configuredField.toLowerCase();

            if (fieldsByName.containsKey(normalized)) {
                ordered.add(
                    fieldsByName.get(normalized)
                );

                used.add(normalized);
            }
        }

        List<FieldWrapper> remaining =
            new List<FieldWrapper>();

        for (String normalized : fieldsByName.keySet()) {
            if (!used.contains(normalized)) {
                remaining.add(
                    fieldsByName.get(normalized)
                );
            }
        }

        remaining.sort();
        ordered.addAll(remaining);

        return ordered;
    }

    private static List<String> getFieldNames(
        List<FieldWrapper> fields
    ) {
        List<String> names =
            new List<String>();

        for (FieldWrapper field : fields) {
            names.add(field.apiName);
        }

        return removeDuplicateFields(names);
    }

    private static Set<String> normalizeFieldSet(
        Set<String> fieldNames
    ) {
        Set<String> normalized =
            new Set<String>();

        for (String fieldName : fieldNames) {
            normalized.add(
                fieldName.toLowerCase()
            );
        }

        return normalized;
    }

    private static List<String> removeDuplicateFields(
        List<String> fields
    ) {
        List<String> unique =
            new List<String>();

        Set<String> used =
            new Set<String>();

        for (String fieldName : fields) {
            String normalized =
                fieldName.toLowerCase();

            if (!used.contains(normalized)) {
                used.add(normalized);
                unique.add(fieldName);
            }
        }

        return unique;
    }

    private static Boolean containsFieldIgnoreCase(
        List<String> fields,
        String targetField
    ) {
        for (String fieldName : fields) {
            if (
                fieldName.equalsIgnoreCase(
                    targetField
                )
            ) {
                return true;
            }
        }

        return false;
    }

    /*
     * Field-copy helpers.
     */
    private static void copyField(
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

        putFieldIgnoreCase(
            destination,
            destinationField,
            value
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

        String textValue =
            String.valueOf(value);

        if (
            destinationPicklistContains(
                destination,
                destinationField,
                textValue
            )
        ) {
            putFieldIgnoreCase(
                destination,
                destinationField,
                textValue
            );
        }
    }

    private static Boolean destinationPicklistContains(
        SObject destination,
        String requestedField,
        String requestedValue
    ) {
        Schema.DescribeFieldResult fieldDescribe =
            getFieldDescribe(
                destination.getSObjectType(),
                requestedField
            );

        if (fieldDescribe == null) {
            return false;
        }

        if (
            fieldDescribe.getType() !=
                Schema.DisplayType.PICKLIST &&
            fieldDescribe.getType() !=
                Schema.DisplayType.MULTIPICKLIST
        ) {
            return true;
        }

        for (
            Schema.PicklistEntry entry :
            fieldDescribe.getPicklistValues()
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
        String requestedField
    ) {
        Schema.DescribeFieldResult fieldDescribe =
            getFieldDescribe(
                record.getSObjectType(),
                requestedField
            );

        if (fieldDescribe == null) {
            return null;
        }

        return record.get(
            fieldDescribe.getName()
        );
    }

    private static void putFieldIgnoreCase(
        SObject record,
        String requestedField,
        Object value
    ) {
        Schema.DescribeFieldResult fieldDescribe =
            getFieldDescribe(
                record.getSObjectType(),
                requestedField
            );

        if (
            fieldDescribe != null &&
            fieldDescribe.isCreateable()
        ) {
            record.put(
                fieldDescribe.getName(),
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

        for (String mapFieldName : fieldMap.keySet()) {
            if (
                mapFieldName.equalsIgnoreCase(
                    requestedField
                )
            ) {
                return fieldMap
                    .get(mapFieldName)
                    .getDescribe();
            }
        }

        return null;
    }

    private static void insertRecords(
        List<SObject> records
    ) {
        if (records == null || records.isEmpty()) {
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
        Boolean requireRead,
        Boolean requireCreate
    ) {
        Schema.SObjectType objectType =
            getObjectType(objectApiName);

        if (objectType == null) {
            throw new LaneQuoteConversionException(
                'Object does not exist: ' +
                objectApiName
            );
        }

        Schema.DescribeSObjectResult objectDescribe =
            objectType.getDescribe();

        if (
            requireRead &&
            !objectDescribe.isAccessible()
        ) {
            throw new LaneQuoteConversionException(
                'You do not have read access to ' +
                objectDescribe.getLabelPlural() +
                '.'
            );
        }

        if (
            requireCreate &&
            !objectDescribe.isCreateable()
        ) {
            throw new LaneQuoteConversionException(
                'You do not have create access to ' +
                objectDescribe.getLabelPlural() +
                '.'
            );
        }
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

    public class LaneQuoteConversionException
        extends Exception {
    }
}