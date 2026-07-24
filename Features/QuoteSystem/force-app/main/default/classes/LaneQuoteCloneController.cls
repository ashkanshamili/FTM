public without sharing class LaneQuoteCloneController {

    private static final String LANE_QUOTE_OBJECT =
        'FreightTM__Lane_Quote__c';

    private static final String QUOTE_LINE_OBJECT =
        'FreightTM__Quote_Line__c';

    private static final String QUOTE_PAY_OBJECT =
        'FreightTM__Quote_Pay__c';

    private static final String QUOTE_LEG_OBJECT =
        'FreightTM__Quote_Leg__c';

    /*
     * Parent Lane Quote field on all three child objects.
     */
    private static final String CHILD_PARENT_FIELD =
        'FreightTM__Lane_Quote__c';

    private static final Integer MAX_CLONES = 25;
    private static final Integer MAX_CHILD_ROWS = 200;

    public Id sourceLaneQuoteId { get; private set; }
    public Integer cloneCount { get; set; }
    public Id selectedRecordTypeId { get; set; }
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

    /*
     * Record type is rendered separately.
     *
     * Formula fields, roll-ups, auto-number fields and audit fields
     * are also excluded automatically by getEditableFields().
     */
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
            CHILD_PARENT_FIELD
        };

    /*
     * Visualforce renders two columns, so values are ordered:
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

    public LaneQuoteCloneController() {
        cloneCount = 1;
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

    /*
     * Record types available to the current user.
     */
    public List<SelectOption> getLaneQuoteRecordTypeOptions() {
        List<SelectOption> options =
            new List<SelectOption>();
        
        Schema.SObjectType laneQuoteType =
            getObjectType(LANE_QUOTE_OBJECT);
        
        if (
            laneQuoteType == null ||
            !objectHasField(laneQuoteType, 'RecordTypeId')
        ) {
            return options;
        }
        
        List<RecordTypeOptionWrapper> sortedOptions =
            new List<RecordTypeOptionWrapper>();
        
        for (
            Schema.RecordTypeInfo recordTypeInfo :
            laneQuoteType.getDescribe().getRecordTypeInfos()
        ) {
            if (
                recordTypeInfo.isAvailable() &&
                recordTypeInfo.getRecordTypeId() != null &&
                !recordTypeInfo.isMaster()
            ) {
                sortedOptions.add(
                    new RecordTypeOptionWrapper(
                        recordTypeInfo.getRecordTypeId(),
                        recordTypeInfo.getName()
                    )
                );
            }
        }
        
        sortedOptions.sort();
        
        for (
            RecordTypeOptionWrapper optionWrapper :
            sortedOptions
        ) {
            options.add(
                new SelectOption(
                    String.valueOf(
                        optionWrapper.recordTypeId
                    ),
                    optionWrapper.label
                )
            );
        }
        
        return options;
    }

    public Boolean getHasLaneQuoteRecordTypes() {
        return !getLaneQuoteRecordTypeOptions().isEmpty();
    }

    private void initializeMetadata() {
        validateObjectAccess(LANE_QUOTE_OBJECT);
        validateObjectAccess(QUOTE_LINE_OBJECT);
        validateObjectAccess(QUOTE_PAY_OBJECT);
        validateObjectAccess(QUOTE_LEG_OBJECT);

        laneQuoteFields = getEditableFields(
            LANE_QUOTE_OBJECT,
            EXCLUDED_LANE_QUOTE_FIELDS
        );

        quoteLineFields = getEditableFields(
            QUOTE_LINE_OBJECT,
            EXCLUDED_CHILD_FIELDS
        );

        quotePayFields = getEditableFields(
            QUOTE_PAY_OBJECT,
            EXCLUDED_CHILD_FIELDS
        );

        quoteLegFields = getEditableFields(
            QUOTE_LEG_OBJECT,
            EXCLUDED_CHILD_FIELDS
        );
    }

    private void loadExistingData() {
        SObject sourceLaneQuote =
            querySourceLaneQuote();

        selectedRecordTypeId =
            (Id)getFieldValueIgnoreCase(
                sourceLaneQuote,
                'RecordTypeId'
            );

        /*
         * Create an unsaved editable template.
         */
        laneQuoteRecord =
            sourceLaneQuote.clone(
                false,
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

        addFieldIfPresent(
            selectedFields,
            LANE_QUOTE_OBJECT,
            'RecordTypeId'
        );

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
            throw new LaneQuoteCloneException(
                'The source Lane Quote was not found or is not accessible.'
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
            CHILD_PARENT_FIELD +
            ' = :sourceLaneQuoteId' +
            ' ORDER BY CreatedDate';

        List<ChildRow> rows =
            new List<ChildRow>();

        for (
            SObject queriedRecord :
            Database.query(soql)
        ) {
            SObject editableRecord =
                queriedRecord.clone(
                    false,
                    true,
                    false,
                    false
                );

            rows.add(
                new ChildRow(editableRecord)
            );
        }

        return rows;
    }

    private static List<FieldWrapper> getEditableFields(
        String objectApiName,
        Set<String> excludedFields
    ) {
        Schema.SObjectType objectType =
            getObjectType(objectApiName);

        if (objectType == null) {
            throw new LaneQuoteCloneException(
                'Object does not exist: ' +
                objectApiName
            );
        }

        Schema.DescribeSObjectResult objectDescribe =
            objectType.getDescribe();

        Map<String, Schema.SObjectField> fieldMap =
            objectDescribe.fields.getMap();

        Set<String> normalizedExcludedFields =
            normalizeFieldSet(excludedFields);

        Map<String, FieldWrapper> fieldsByApiName =
            new Map<String, FieldWrapper>();

        for (String mapFieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe =
                fieldMap
                    .get(mapFieldName)
                    .getDescribe();

            String canonicalFieldName =
                fieldDescribe.getName();

            String normalizedFieldName =
                canonicalFieldName.toLowerCase();

            if (
                normalizedExcludedFields.contains(
                    normalizedFieldName
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

            fieldsByApiName.put(
                normalizedFieldName,
                new FieldWrapper(
                    canonicalFieldName,
                    fieldDescribe.getLabel(),
                    fieldDescribe.isNillable()
                )
            );
        }

        if (
            objectApiName.equalsIgnoreCase(
                LANE_QUOTE_OBJECT
            )
        ) {
            return orderFields(
                fieldsByApiName,
                LANE_QUOTE_FIELD_ORDER
            );
        }

        if (
            objectApiName.equalsIgnoreCase(
                QUOTE_LINE_OBJECT
            )
        ) {
            return orderFields(
                fieldsByApiName,
                QUOTE_LINE_FIELD_ORDER
            );
        }

        if (
            objectApiName.equalsIgnoreCase(
                QUOTE_PAY_OBJECT
            )
        ) {
            return orderFields(
                fieldsByApiName,
                QUOTE_PAY_FIELD_ORDER
            );
        }

        if (
            objectApiName.equalsIgnoreCase(
                QUOTE_LEG_OBJECT
            )
        ) {
            return orderFields(
                fieldsByApiName,
                QUOTE_LEG_FIELD_ORDER
            );
        }

        List<FieldWrapper> alphabeticalFields =
            fieldsByApiName.values();

        alphabeticalFields.sort();

        return alphabeticalFields;
    }

    private static List<FieldWrapper> orderFields(
        Map<String, FieldWrapper> fieldsByApiName,
        List<String> configuredOrder
    ) {
        List<FieldWrapper> orderedFields =
            new List<FieldWrapper>();

        Set<String> addedFields =
            new Set<String>();

        if (fieldsByApiName == null) {
            return orderedFields;
        }

        if (configuredOrder != null) {
            for (String configuredFieldName : configuredOrder) {
                if (String.isBlank(configuredFieldName)) {
                    continue;
                }

                String normalizedFieldName =
                    configuredFieldName.toLowerCase();

                if (
                    fieldsByApiName.containsKey(
                        normalizedFieldName
                    ) &&
                    !addedFields.contains(
                        normalizedFieldName
                    )
                ) {
                    orderedFields.add(
                        fieldsByApiName.get(
                            normalizedFieldName
                        )
                    );

                    addedFields.add(
                        normalizedFieldName
                    );
                }
            }
        }

        /*
         * Preserve any future editable fields by appending them.
         */
        List<FieldWrapper> remainingFields =
            new List<FieldWrapper>();

        for (
            String normalizedFieldName :
            fieldsByApiName.keySet()
        ) {
            if (
                !addedFields.contains(
                    normalizedFieldName
                )
            ) {
                remainingFields.add(
                    fieldsByApiName.get(
                        normalizedFieldName
                    )
                );
            }
        }

        remainingFields.sort();
        orderedFields.addAll(remainingFields);

        return orderedFields;
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

    private static List<String> getFieldNames(
        List<FieldWrapper> fields
    ) {
        List<String> names =
            new List<String>();

        if (fields == null) {
            return names;
        }

        for (FieldWrapper field : fields) {
            names.add(field.apiName);
        }

        return removeDuplicateFields(names);
    }

    private static void addFieldIfPresent(
        List<String> selectedFields,
        String objectApiName,
        String requestedFieldName
    ) {
        Schema.SObjectType objectType =
            getObjectType(objectApiName);

        if (objectType == null) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap =
            objectType
                .getDescribe()
                .fields
                .getMap();

        for (String mapFieldName : fieldMap.keySet()) {
            if (
                !mapFieldName.equalsIgnoreCase(
                    requestedFieldName
                )
            ) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe =
                fieldMap
                    .get(mapFieldName)
                    .getDescribe();

            if (!fieldDescribe.isAccessible()) {
                return;
            }

            String canonicalFieldName =
                fieldDescribe.getName();

            if (
                !containsFieldIgnoreCase(
                    selectedFields,
                    canonicalFieldName
                )
            ) {
                selectedFields.add(canonicalFieldName);
            }

            return;
        }
    }

    private static Boolean containsFieldIgnoreCase(
        List<String> fieldNames,
        String targetField
    ) {
        if (
            fieldNames == null ||
            String.isBlank(targetField)
        ) {
            return false;
        }

        for (String fieldName : fieldNames) {
            if (
                fieldName != null &&
                fieldName.equalsIgnoreCase(
                    targetField
                )
            ) {
                return true;
            }
        }

        return false;
    }

    private static List<String> removeDuplicateFields(
        List<String> fieldNames
    ) {
        List<String> uniqueFields =
            new List<String>();

        Set<String> normalizedNames =
            new Set<String>();

        if (fieldNames == null) {
            return uniqueFields;
        }

        for (String fieldName : fieldNames) {
            if (String.isBlank(fieldName)) {
                continue;
            }

            String normalizedName =
                fieldName.toLowerCase();

            if (
                !normalizedNames.contains(
                    normalizedName
                )
            ) {
                normalizedNames.add(normalizedName);
                uniqueFields.add(fieldName);
            }
        }

        return uniqueFields;
    }

    public PageReference saveClones() {
        Savepoint savePoint =
            Database.setSavepoint();

        try {
            validateCloneRequest();

            List<SObject> clonedLaneQuotes =
                new List<SObject>();

            for (
                Integer cloneNumber = 0;
                cloneNumber < cloneCount;
                cloneNumber++
            ) {
                SObject clonedLaneQuote =
                    laneQuoteRecord.clone(
                        false,
                        true,
                        false,
                        false
                    );

                putFieldIgnoreCase(
                    clonedLaneQuote,
                    'RecordTypeId',
                    selectedRecordTypeId
                );

                clonedLaneQuotes.add(
                    clonedLaneQuote
                );
            }

            clonedLaneQuotes =
                sanitizeForCreate(
                    clonedLaneQuotes
                );

            if (clonedLaneQuotes.isEmpty()) {
                throw new LaneQuoteCloneException(
                    'No Lane Quote records could be created.'
                );
            }

            insert clonedLaneQuotes;

            Map<String, List<SObject>> childrenByObject =
                initializeChildMap();

            for (SObject newLaneQuote : clonedLaneQuotes) {
                addChildCopies(
                    childrenByObject.get(
                        QUOTE_LINE_OBJECT
                    ),
                    quoteLines,
                    newLaneQuote.Id
                );

                addChildCopies(
                    childrenByObject.get(
                        QUOTE_PAY_OBJECT
                    ),
                    quotePays,
                    newLaneQuote.Id
                );

                addChildCopies(
                    childrenByObject.get(
                        QUOTE_LEG_OBJECT
                    ),
                    quoteLegs,
                    newLaneQuote.Id
                );
            }

            insertChildRecords(
                childrenByObject.get(
                    QUOTE_LINE_OBJECT
                )
            );

            insertChildRecords(
                childrenByObject.get(
                    QUOTE_PAY_OBJECT
                )
            );

            insertChildRecords(
                childrenByObject.get(
                    QUOTE_LEG_OBJECT
                )
            );

            if (clonedLaneQuotes.size() == 1) {
                PageReference newRecordPage =
                    new PageReference(
                        '/' + clonedLaneQuotes[0].Id
                    );

                newRecordPage.setRedirect(true);
                return newRecordPage;
            }

            PageReference sourcePage =
                new PageReference(
                    '/' + sourceLaneQuoteId
                );

            sourcePage.setRedirect(true);
            return sourcePage;

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

    private static Map<String, List<SObject>>
        initializeChildMap() {

        Map<String, List<SObject>> childrenByObject =
            new Map<String, List<SObject>>();

        childrenByObject.put(
            QUOTE_LINE_OBJECT,
            new List<SObject>()
        );

        childrenByObject.put(
            QUOTE_PAY_OBJECT,
            new List<SObject>()
        );

        childrenByObject.put(
            QUOTE_LEG_OBJECT,
            new List<SObject>()
        );

        return childrenByObject;
    }

    private static void addChildCopies(
        List<SObject> destination,
        List<ChildRow> sourceRows,
        Id newLaneQuoteId
    ) {
        if (
            destination == null ||
            sourceRows == null
        ) {
            return;
        }

        for (ChildRow sourceRow : sourceRows) {
            if (
                sourceRow == null ||
                sourceRow.record == null
            ) {
                continue;
            }

            SObject clonedChild =
                sourceRow.record.clone(
                    false,
                    true,
                    false,
                    false
                );

            putFieldIgnoreCase(
                clonedChild,
                CHILD_PARENT_FIELD,
                newLaneQuoteId
            );

            destination.add(clonedChild);
        }
    }

    private static void insertChildRecords(
        List<SObject> childRecords
    ) {
        if (
            childRecords == null ||
            childRecords.isEmpty()
        ) {
            return;
        }

        List<SObject> sanitizedRecords =
            sanitizeForCreate(childRecords);

        if (!sanitizedRecords.isEmpty()) {
            insert sanitizedRecords;
        }
    }

    private static List<SObject> sanitizeForCreate(
        List<SObject> records
    ) {
        if (
            records == null ||
            records.isEmpty()
        ) {
            return new List<SObject>();
        }

        SObjectAccessDecision accessDecision =
            Security.stripInaccessible(
                AccessType.CREATABLE,
                records
            );

        return accessDecision.getRecords();
    }

    private static Boolean userCanUseRecordType(
        Id recordTypeId
    ) {
        if (recordTypeId == null) {
            return false;
        }
        
        Schema.SObjectType objectType =
            getObjectType(LANE_QUOTE_OBJECT);
        
        if (objectType == null) {
            return false;
        }
        
        Map<Id, Schema.RecordTypeInfo> recordTypesById =
            objectType
            .getDescribe()
            .getRecordTypeInfosById();
        
        if (!recordTypesById.containsKey(recordTypeId)) {
            return false;
        }
        
        Schema.RecordTypeInfo recordTypeInfo =
            recordTypesById.get(recordTypeId);
        
        return recordTypeInfo.isAvailable() &&
            !recordTypeInfo.isMaster();
    }

    private void validateCloneRequest() {
        if (
            getHasLaneQuoteRecordTypes() &&
            (
                selectedRecordTypeId == null ||
                !userCanUseRecordType(
                    selectedRecordTypeId
                )
            )
        ) {
            throw new LaneQuoteCloneException(
                'Select an available Lane Quote Record Type.'
            );
        }

        if (
            cloneCount == null ||
            cloneCount < 1 ||
            cloneCount > MAX_CLONES
        ) {
            throw new LaneQuoteCloneException(
                'Number of Lane Quotes must be between 1 and ' +
                MAX_CLONES +
                '.'
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

    private static void validateChildCount(
        String sectionName,
        List<ChildRow> rows
    ) {
        if (
            rows != null &&
            rows.size() > MAX_CHILD_ROWS
        ) {
            throw new LaneQuoteCloneException(
                sectionName +
                ' cannot contain more than ' +
                MAX_CHILD_ROWS +
                ' records.'
            );
        }
    }

    public void addQuoteLine() {
        addChildRow(
            quoteLines,
            QUOTE_LINE_OBJECT
        );

        ChildRow row =
            quoteLines[quoteLines.size() - 1];

        putFieldIgnoreCase(
            row.record,
            'Number_of_Units__c',
            Decimal.valueOf('1.00')
        );
    }

    public void addQuotePay() {
        addChildRow(
            quotePays,
            QUOTE_PAY_OBJECT
        );

        ChildRow row =
            quotePays[quotePays.size() - 1];

        putFieldIgnoreCase(
            row.record,
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

    private static void addChildRow(
        List<ChildRow> rows,
        String objectApiName
    ) {
        if (rows == null) {
            throw new LaneQuoteCloneException(
                'The child record collection is unavailable.'
            );
        }

        if (rows.size() >= MAX_CHILD_ROWS) {
            throw new LaneQuoteCloneException(
                'The maximum number of child records has been reached.'
            );
        }

        Schema.SObjectType objectType =
            getObjectType(objectApiName);

        if (objectType == null) {
            throw new LaneQuoteCloneException(
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

    public void removeQuoteLine() {
        removeChildRow(quoteLines);
    }

    public void removeQuotePay() {
        removeChildRow(quotePays);
    }

    public void removeQuoteLeg() {
        removeChildRow(quoteLegs);
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

    public PageReference cancel() {
        PageReference sourcePage =
            new PageReference(
                '/' + sourceLaneQuoteId
            );

        sourcePage.setRedirect(true);
        return sourcePage;
    }

    private static Object getFieldValueIgnoreCase(
        SObject sourceRecord,
        String requestedFieldName
    ) {
        if (
            sourceRecord == null ||
            String.isBlank(requestedFieldName)
        ) {
            return null;
        }

        Map<String, Schema.SObjectField> fieldMap =
            sourceRecord
                .getSObjectType()
                .getDescribe()
                .fields
                .getMap();

        for (String fieldName : fieldMap.keySet()) {
            if (fieldName.equalsIgnoreCase(requestedFieldName)) {
                return sourceRecord.get(
                    fieldMap.get(fieldName).getDescribe().getName()
                );
            }
        }

        return null;
    }

    private static void putFieldIgnoreCase(
        SObject targetRecord,
        String requestedFieldName,
        Object fieldValue
    ) {
        if (
            targetRecord == null ||
            String.isBlank(requestedFieldName)
        ) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap =
            targetRecord
                .getSObjectType()
                .getDescribe()
                .fields
                .getMap();

        for (String mapFieldName : fieldMap.keySet()) {
            if (
                !mapFieldName.equalsIgnoreCase(
                    requestedFieldName
                )
            ) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe =
                fieldMap
                    .get(mapFieldName)
                    .getDescribe();

            if (fieldDescribe.isCreateable()) {
                targetRecord.put(
                    fieldDescribe.getName(),
                    fieldValue
                );
            }

            return;
        }
    }

    private static void validateObjectAccess(
        String objectApiName
    ) {
        Schema.SObjectType objectType =
            getObjectType(objectApiName);

        if (objectType == null) {
            throw new LaneQuoteCloneException(
                'Object does not exist: ' +
                objectApiName
            );
        }

        Schema.DescribeSObjectResult objectDescribe =
            objectType.getDescribe();

        if (!objectDescribe.isAccessible()) {
            throw new LaneQuoteCloneException(
                'You do not have read access to ' +
                objectDescribe.getLabelPlural() +
                '.'
            );
        }

        if (!objectDescribe.isCreateable()) {
            throw new LaneQuoteCloneException(
                'You do not have create access to ' +
                objectDescribe.getLabelPlural() +
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
        String requestedObjectName
    ) {
        Map<String, Schema.SObjectType> globalDescribe =
            Schema.getGlobalDescribe();

        for (String objectName : globalDescribe.keySet()) {
            if (
                objectName.equalsIgnoreCase(
                    requestedObjectName
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

        public Integer compareTo(
            Object otherObject
        ) {
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

        public Integer compareTo(
            Object otherObject
        ) {
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

    public class LaneQuoteCloneException
        extends Exception {
    }
}