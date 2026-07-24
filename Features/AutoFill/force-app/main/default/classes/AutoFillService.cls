public without sharing class AutoFillService {

    private static final String LOAD_OBJECT_API_NAME = 'FreightTM__Load__c';
    private static final String PROCESSING_KEY_FIELD = 'AutoFill_Processing_Key__c';
    private static final Integer BUSINESS_DEDUP_LOOKBACK_HOURS = 24;
    private static final Integer MAX_PROCESSING_SOURCE_LENGTH = 4000;

    @TestVisible
    private static Map<String, Id> lookupIdCache = new Map<String, Id>();
    @TestVisible
    private static Map<String, Id> transactionDedupCache = new Map<String, Id>();

    public class ProcessingResult {
        @AuraEnabled public Id recordId { get; set; }
        @AuraEnabled public Boolean created { get; set; }
        @AuraEnabled public String objectType { get; set; }
        @AuraEnabled public String itemId { get; set; }
        @AuraEnabled public String autoFillStatus { get; set; }
        @AuraEnabled public String detectedDocumentType { get; set; }
        @AuraEnabled public Decimal documentConfidence { get; set; }
        @AuraEnabled public Decimal classificationConfidence { get; set; }
        @AuraEnabled public Integer fieldCount { get; set; }
        @AuraEnabled public Boolean allFieldsDetected { get; set; }
        @AuraEnabled public String autoFillSource { get; set; }
        @AuraEnabled public String rawResponseJson { get; set; }
    }

    public class Resolution {
        public Id recordId;
        public Boolean created;

        public Resolution(Id recordId, Boolean created) {
            this.recordId = recordId;
            this.created = created;
        }
    }

    private class V2ChildDefinition {
        public String collectionName;
        public String objectApiName;
        public String parentLookupFieldApiName;
        public Map<String, String> fieldMappings = new Map<String, String>();
    }

    public static Id createFromExtractionPayload(
        Map<String, Object> apiResponse
    ) {
        return createFromExtractionPayloadWithStatus(
            apiResponse,
            null,
            'Manual Upload'
        ).recordId;
    }

    public static ProcessingResult createFromExtractionPayloadWithStatus(
        Map<String, Object> apiResponse,
        String deliveryId
    ) {
        return createFromExtractionPayloadWithStatus(
            apiResponse,
            deliveryId,
            'Webhook'
        );
    }

    public static ProcessingResult createFromExtractionPayloadWithStatus(
        Map<String, Object> apiResponse,
        String deliveryId,
        String defaultSource
    ) {
        if (apiResponse == null || apiResponse.isEmpty()) {
            throw new RecordCreationException('The extraction payload is empty.');
        }

        String objectApiName = resolveExistingSObjectApiName(
            resolveParentObjectApiName(apiResponse)
        );

        if (String.isBlank(objectApiName)) {
            throw new RecordCreationException(
                'The parent Salesforce object API name was not returned or does not exist. ' +
                'Provide SalesforceObjectType or Metadata.salesforceParent.objectApiName.'
            );
        }

        String processingIdentifier = resolveProcessingIdentifier(
            apiResponse,
            deliveryId
        );

        Id alreadyProcessedId = findProcessedRecord(
            'EXTRACTION',
            processingIdentifier,
            objectApiName
        );

        if (alreadyProcessedId != null) {
            return buildProcessingResult(
                alreadyProcessedId,
                false,
                objectApiName,
                apiResponse,
                null,
                0,
                defaultSource
            );
        }

        Object extractedObject = getValue(
            apiResponse,
            new List<String>{ 'ExtractedFields', 'extractedFields' }
        );

        if (!(extractedObject instanceof Map<String, Object>)) {
            throw new RecordCreationException('ExtractedFields was not returned.');
        }

        Map<String, Object> extractedFields =
            (Map<String, Object>) extractedObject;
        Schema.SObjectType objectType =
            Schema.getGlobalDescribe().get(objectApiName);

        if (objectType == null) {
            throw new RecordCreationException(
                'Salesforce object does not exist: ' + objectApiName
            );
        }

        Schema.DescribeSObjectResult objectDescribe =
            objectType.getDescribe();

        if (!objectDescribe.isCreateable()) {
            throw new RecordCreationException(
                'The current context cannot create ' + objectApiName + '.'
            );
        }

        Map<String, Schema.SObjectField> objectFields =
            objectDescribe.fields.getMap();
        Map<String, String> fieldsByNormalizedName =
            buildFieldNameMap(objectFields);
        Map<String, String> v2ParentFieldMappings =
            getV2ParentFieldMappings(apiResponse);
        SObject recordToInsert = objectType.newSObject();

        for (String extractedFieldName : extractedFields.keySet()) {
            Object rawValue = unwrapExtractedFieldValue(
                extractedFields.get(extractedFieldName)
            );

            if (isEmpty(rawValue)) {
                continue;
            }

            String fieldApiName = getMappedFieldApiName(
                v2ParentFieldMappings,
                fieldsByNormalizedName,
                extractedFieldName
            );

            if (String.isBlank(fieldApiName)) {
                System.debug(
                    LoggingLevel.WARN,
                    'AutoFill skipped an unmapped field: ' + extractedFieldName
                );
                continue;
            }

            Schema.SObjectField objectField = objectFields.get(fieldApiName);
            if (objectField == null) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe =
                objectField.getDescribe();

            if (!fieldDescribe.isCreateable() ||
                fieldDescribe.isCalculated() ||
                fieldDescribe.isAutoNumber()) {
                continue;
            }

            try {
                if (fieldDescribe.getType() == Schema.DisplayType.Reference) {
                    Id lookupId = findOrCreateLookup(
                        fieldDescribe,
                        String.valueOf(rawValue).trim(),
                        extractedFieldName,
                        extractedFields
                    );

                    if (lookupId != null) {
                        recordToInsert.put(fieldApiName, lookupId);
                    }
                    continue;
                }

                Object convertedValue = convertValueForField(
                    rawValue,
                    fieldDescribe
                );

                if (convertedValue != null) {
                    recordToInsert.put(fieldApiName, convertedValue);
                }
            } catch (Exception e) {
                // One unusable extracted value must not block the rest of the
                // document. This includes lookup values that cannot be
                // resolved, invalid data types, and org-specific field
                // configurations. Log the field and continue with the next
                // extracted value.
                System.debug(
                    LoggingLevel.WARN,
                    'AutoFill skipped field "' + extractedFieldName +
                    '" mapped to "' + fieldApiName +
                    '". Reason: ' + e.getMessage()
                );
            }
        }

        populateAutoFillLoadFields(
            recordToInsert,
            objectApiName,
            objectFields,
            apiResponse,
            extractedFields,
            defaultSource
        );

        assignProcessingKey(
            recordToInsert,
            objectApiName,
            objectFields,
            'EXTRACTION',
            processingIdentifier
        );

        Id duplicateRecordId = findExistingRecordByBusinessKey(
            recordToInsert,
            objectApiName,
            objectFields
        );

        if (duplicateRecordId != null) {
            cacheProcessedRecord(
                'EXTRACTION',
                processingIdentifier,
                objectApiName,
                duplicateRecordId
            );

            return buildProcessingResult(
                duplicateRecordId,
                false,
                objectApiName,
                apiResponse,
                recordToInsert,
                0,
                defaultSource
            );
        }

        Resolution insertResolution;
        try {
            insertResolution = insertRecordOnce(
                'EXTRACTION',
                processingIdentifier,
                objectApiName,
                recordToInsert,
                objectFields
            );
        } catch (Exception e) {
            throw new RecordCreationException(e.getMessage());
        }

        Integer childRecordCount = 0;
        if (insertResolution.created == true) {
            childRecordCount = createV2ChildRecords(
                apiResponse,
                insertResolution.recordId,
                objectApiName
            );
        }

        return buildProcessingResult(
            insertResolution.recordId,
            insertResolution.created,
            objectApiName,
            apiResponse,
            recordToInsert,
            childRecordCount,
            defaultSource
        );
    }

    @TestVisible
    private static ProcessingResult buildProcessingResult(
        Id recordId,
        Boolean created,
        String objectApiName,
        Map<String, Object> apiResponse,
        SObject mappedRecord,
        Integer childRecordCount,
        String defaultSource
    ) {
        Object extractedObject = getValue(
            apiResponse,
            new List<String>{ 'ExtractedFields', 'extractedFields' }
        );
        Map<String, Object> extractedFields =
            extractedObject instanceof Map<String, Object>
            ? (Map<String, Object>) extractedObject
            : new Map<String, Object>();
        Map<String, Object> fieldConfidences =
            getFieldConfidences(apiResponse);

        ProcessingResult result = new ProcessingResult();
        result.recordId = recordId;
        result.created = created;
        result.objectType = objectApiName;
        result.itemId = getFirstStringValue(
            apiResponse,
            new List<String>{ 'ItemId', 'itemId', 'CorrelationId', 'correlationId' }
        );
        result.autoFillStatus = objectApiName == LOAD_OBJECT_API_NAME
            ? 'Draft'
            : null;
        result.detectedDocumentType = resolveDocumentType(
            apiResponse,
            extractedFields
        );
        result.documentConfidence = resolveOverallConfidence(
            apiResponse,
            extractedFields,
            fieldConfidences
        );
        result.classificationConfidence = resolveClassificationConfidence(
            apiResponse
        );
        result.fieldCount = getMappedFieldCount(mappedRecord) +
            (childRecordCount == null ? 0 : childRecordCount);
        result.allFieldsDetected = resolveAllFieldsDetected(apiResponse);
        result.autoFillSource = resolveAutoFillSource(
            apiResponse,
            defaultSource
        );
        result.rawResponseJson = serializeRawResponse(apiResponse);
        return result;
    }

    @TestVisible
    private static Integer getMappedFieldCount(SObject mappedRecord) {
        if (mappedRecord == null) {
            return 0;
        }

        try {
            Object value = mappedRecord.get('AutoFill_Field_Count__c');
            return value == null ? 0 : Integer.valueOf(String.valueOf(value));
        } catch (Exception ignored) {
            return 0;
        }
    }

    @TestVisible
    private static Decimal resolveClassificationConfidence(
        Map<String, Object> apiResponse
    ) {
        return normalizeConfidenceForPercent(
            toDecimalOrNull(
                getFirstValue(
                    apiResponse,
                    new List<String>{
                        'ClassificationConfidence',
                        'classificationConfidence',
                        'DocumentClassificationConfidence',
                        'documentClassificationConfidence'
                    }
                )
            )
        );
    }

    @TestVisible
    private static Id findExistingRecordByBusinessKey(
        SObject candidate,
        String objectApiName,
        Map<String, Schema.SObjectField> objectFields
    ) {
        if (candidate == null ||
            String.isBlank(objectApiName) ||
            objectFields == null ||
            objectFields.isEmpty()) {
            return null;
        }

        Map<String, Object> populated =
            candidate.getPopulatedFieldsAsMap();

        if (objectFields.containsKey(PROCESSING_KEY_FIELD) &&
            populated.containsKey(PROCESSING_KEY_FIELD)) {
            Id processingMatch = queryFirstByFields(
                objectApiName,
                new Map<String, Object>{
                    PROCESSING_KEY_FIELD => populated.get(PROCESSING_KEY_FIELD)
                },
                false
            );

            if (processingMatch != null) {
                return processingMatch;
            }
        }

        List<String> preferredIdentifiers = objectApiName == LOAD_OBJECT_API_NAME
            ? new List<String>{
                'FreightTM__External_Load_ID__c',
                'FreightTM__PRO__c',
                'FreightTM__Confirmation_Number__c'
            }
            : new List<String>();

        for (String fieldApiName : preferredIdentifiers) {
            if (!objectFields.containsKey(fieldApiName) ||
                !populated.containsKey(fieldApiName) ||
                isEmpty(populated.get(fieldApiName))) {
                continue;
            }

            Id identifierMatch = queryFirstByFields(
                objectApiName,
                new Map<String, Object>{
                    fieldApiName => populated.get(fieldApiName)
                },
                true
            );

            if (identifierMatch != null) {
                return identifierMatch;
            }
        }

        for (String fieldApiName : populated.keySet()) {
            if (!objectFields.containsKey(fieldApiName) ||
                fieldApiName == PROCESSING_KEY_FIELD) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe =
                objectFields.get(fieldApiName).getDescribe();

            if ((!fieldDescribe.isExternalId() && !fieldDescribe.isUnique()) ||
                !fieldDescribe.isFilterable() ||
                isEmpty(populated.get(fieldApiName))) {
                continue;
            }

            Id uniqueMatch = queryFirstByFields(
                objectApiName,
                new Map<String, Object>{
                    fieldApiName => populated.get(fieldApiName)
                },
                false
            );

            if (uniqueMatch != null) {
                return uniqueMatch;
            }
        }

        List<String> fingerprintFields = objectApiName == LOAD_OBJECT_API_NAME
            ? new List<String>{
                'FreightTM__Pickup_City__c',
                'FreightTM__Pickup_State__c',
                'FreightTM__Pickup_Date__c',
                'FreightTM__Delivery_City__c',
                'FreightTM__Delivery_State__c',
                'FreightTM__Delivery_Date__c',
                'FreightTM__Required_Trailer__c',
                'FreightTM__Rate__c'
            }
            : new List<String>();

        Map<String, Object> fingerprint = new Map<String, Object>();

        for (String fieldApiName : fingerprintFields) {
            if (objectFields.containsKey(fieldApiName) &&
                populated.containsKey(fieldApiName) &&
                !isEmpty(populated.get(fieldApiName)) &&
                objectFields.get(fieldApiName).getDescribe().isFilterable()) {
                fingerprint.put(fieldApiName, populated.get(fieldApiName));
            }
        }

        if (fingerprint.size() < 3) {
            fingerprint.clear();

            for (String fieldApiName : populated.keySet()) {
                if (fingerprint.size() >= 5 ||
                    !objectFields.containsKey(fieldApiName) ||
                    fieldApiName == PROCESSING_KEY_FIELD ||
                    fieldApiName.startsWith('AutoFill_') ||
                    isEmpty(populated.get(fieldApiName))) {
                    continue;
                }

                Schema.DescribeFieldResult fieldDescribe =
                    objectFields.get(fieldApiName).getDescribe();
                Schema.DisplayType fieldType = fieldDescribe.getType();

                if (!fieldDescribe.isFilterable() ||
                    fieldDescribe.isCalculated() ||
                    fieldType == Schema.DisplayType.TextArea ||
                    fieldType == Schema.DisplayType.Base64 ||
                    fieldType == Schema.DisplayType.EncryptedString) {
                    continue;
                }

                fingerprint.put(fieldApiName, populated.get(fieldApiName));
            }
        }

        return fingerprint.size() >= 3
            ? queryFirstByFields(objectApiName, fingerprint, true)
            : null;
    }

    @TestVisible
    private static Id queryFirstByFields(
        String objectApiName,
        Map<String, Object> criteria,
        Boolean recentOnly
    ) {
        if (String.isBlank(objectApiName) ||
            criteria == null ||
            criteria.isEmpty()) {
            return null;
        }

        List<String> conditions = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();
        Integer bindIndex = 0;

        for (String fieldApiName : criteria.keySet()) {
            Object fieldValue = criteria.get(fieldApiName);
            if (fieldValue == null) {
                continue;
            }

            String bindName = 'value' + String.valueOf(bindIndex++);
            conditions.add(fieldApiName + ' = :' + bindName);
            binds.put(bindName, fieldValue);
        }

        if (conditions.isEmpty()) {
            return null;
        }

        if (recentOnly == true) {
            conditions.add('CreatedDate >= :recentCutoff');
            binds.put(
                'recentCutoff',
                System.now().addHours(-BUSINESS_DEDUP_LOOKBACK_HOURS)
            );
        }

        String soql =
            'SELECT Id FROM ' + objectApiName +
            ' WHERE ' + String.join(conditions, ' AND ') +
            ' ORDER BY CreatedDate DESC LIMIT 1';

        try {
            List<SObject> rows = Database.queryWithBinds(
                soql,
                binds,
                AccessLevel.SYSTEM_MODE
            );
            return rows.isEmpty() ? null : (Id) rows[0].get('Id');
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'AutoFill duplicate query skipped for ' + objectApiName +
                ': ' + e.getMessage()
            );
            return null;
        }
    }


    @TestVisible
    private static void populateAutoFillLoadFields(
        SObject recordToInsert,
        String objectApiName,
        Map<String, Schema.SObjectField> objectFields,
        Map<String, Object> apiResponse,
        Map<String, Object> extractedFields,
        String defaultSource
    ) {
        if (objectApiName != LOAD_OBJECT_API_NAME || objectFields == null) {
            return;
        }

        safePut(recordToInsert, objectFields, 'Created_By_AutoFill__c', true);
        safePut(recordToInsert, objectFields, 'AutoFill_Status__c', 'Draft');
        safePut(
            recordToInsert,
            objectFields,
            'AutoFill_Source__c',
            resolveAutoFillSource(apiResponse, defaultSource)
        );
        safePut(
            recordToInsert,
            objectFields,
            'AutoFill_Item_Id__c',
            getFirstStringValue(
                apiResponse,
                new List<String>{ 'ItemId', 'itemId', 'DocumentId', 'documentId' }
            )
        );
        safePut(
            recordToInsert,
            objectFields,
            'AutoFill_Extracted_Fields_JSON__c',
            serializeRawResponse(extractedFields)
        );
        safePut(recordToInsert, objectFields, 'AutoFill_Document_Type__c', resolveDocumentType(apiResponse, extractedFields));
        Map<String, Object> fieldConfidences = getFieldConfidences(apiResponse);
        Map<String, Object> detectedFieldsAudit = buildDetectedFieldsAudit(extractedFields, objectFields, recordToInsert, fieldConfidences);

        safePut(recordToInsert, objectFields, 'AutoFill_Confidence__c', resolveOverallConfidence(apiResponse, extractedFields, fieldConfidences));
        safePut(recordToInsert, objectFields, 'AutoFill_Field_Count__c', getAuditSectionCount(detectedFieldsAudit, 'savedToLoad'));
        safePut(recordToInsert, objectFields, 'AutoFill_Detected_Fields__c', serializeDetectedFields(detectedFieldsAudit));
        safePut(recordToInsert, objectFields, 'AutoFill_Raw_Response__c', serializeRawResponse(apiResponse));
        safePut(recordToInsert, objectFields, 'AutoFill_All_Fields_Detected__c', resolveAllFieldsDetected(apiResponse));
    }

    @TestVisible
    private static void safePut(
        SObject recordToUpdate,
        Map<String, Schema.SObjectField> fields,
        String fieldApiName,
        Object value
    ) {
        if (recordToUpdate == null || fields == null || !fields.containsKey(fieldApiName) || value == null) {
            return;
        }

        Schema.DescribeFieldResult describe = fields.get(fieldApiName).getDescribe();

        if (describe.isCalculated() || describe.isAutoNumber()) {
            return;
        }

        Object valueToStore = value;

        if (
            fieldApiName == 'AutoFill_Source__c' &&
            value instanceof String &&
            describe.isRestrictedPicklist()
        ) {
            String activeSourceValue = resolveActiveSourcePicklistValue(
                describe,
                String.valueOf(value)
            );

            if (!String.isBlank(activeSourceValue)) {
                valueToStore = activeSourceValue;
            }
        }

        recordToUpdate.put(fieldApiName, valueToStore);
    }

    @TestVisible
    private static String resolveActiveSourcePicklistValue(
        Schema.DescribeFieldResult fieldDescribe,
        String requestedValue
    ) {
        if (fieldDescribe == null || String.isBlank(requestedValue)) {
            return null;
        }

        String normalizedRequested = normalize(requestedValue);
        Boolean requestsEmail =
            normalizedRequested.contains('email') ||
            normalizedRequested.contains('webhook');
        Boolean requestsManual = normalizedRequested.contains('manual');
        Boolean requestsApi = normalizedRequested.contains('api');

        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }

            String normalizedValue = normalize(entry.getValue());
            String normalizedLabel = normalize(entry.getLabel());

            if (
                normalizedRequested == normalizedValue ||
                normalizedRequested == normalizedLabel
            ) {
                return entry.getValue();
            }

            String searchableValue = normalizedValue + normalizedLabel;

            if (
                (requestsEmail &&
                    (searchableValue.contains('email') ||
                     searchableValue.contains('webhook'))) ||
                (requestsManual && searchableValue.contains('manual')) ||
                (requestsApi && searchableValue.contains('api'))
            ) {
                return entry.getValue();
            }
        }

        return null;
    }

    @TestVisible
    private static Object getFirstValue(Map<String, Object> source, List<String> possibleKeys) {
        if (source == null || possibleKeys == null || possibleKeys.isEmpty()) {
            return null;
        }

        Set<String> normalizedKeys = new Set<String>();

        for (String key : possibleKeys) {
            normalizedKeys.add(normalize(key));
        }

        for (String key : source.keySet()) {
            if (normalizedKeys.contains(normalize(key))) {
                return source.get(key);
            }
        }

        for (Object value : source.values()) {
            if (value instanceof Map<String, Object>) {
                Object nestedValue = getFirstValue(
                    (Map<String, Object>) value,
                    possibleKeys
                );

                if (nestedValue != null) {
                    return nestedValue;
                }
            }
        }

        return null;
    }

    @TestVisible
    private static String getFirstStringValue(Map<String, Object> source, List<String> possibleKeys) {
        Object value = getFirstValue(source, possibleKeys);
        return value == null ? null : String.valueOf(value);
    }

    @TestVisible
    private static String resolveAutoFillSource(Map<String, Object> apiResponse, String defaultSource) {
        String rawSource = getFirstStringValue(
            apiResponse,
            new List<String>{ 'AutoFillSource', 'autoFillSource', 'Source', 'source', 'UploadSource', 'uploadSource' }
        );

        String sourceCandidate = String.isBlank(rawSource)
            ? defaultSource
            : rawSource;

        if (String.isBlank(sourceCandidate)) {
            return 'Unknown';
        }

        String normalized = normalize(sourceCandidate);

        if (normalized.contains('webhook') || normalized.contains('email')) {
            return 'Email';
        }

        if (normalized.contains('manual')) {
            return 'Manual Upload';
        }

        if (normalized.contains('api')) {
            return 'API Upload';
        }

        return 'Unknown';
    }

    @TestVisible
    private static String resolveDocumentType(Map<String, Object> apiResponse, Map<String, Object> extractedFields) {
        String rawType = getFirstStringValue(
            apiResponse,
            new List<String>{ 'DetectedDocumentType', 'detectedDocumentType', 'DocumentType', 'documentType', 'DocType', 'docType' }
        );

        if (String.isBlank(rawType)) {
            rawType = inferDocumentTypeFromFields(extractedFields);
        }

        if (String.isBlank(rawType)) {
            return null;
        }

        String normalized = normalize(rawType);

        if (normalized == 'bol' || normalized.contains('billoflading')) {
            return 'BOL';
        }

        if (normalized == 'pod' || normalized.contains('proofofdelivery')) {
            return 'POD';
        }

        if (normalized.contains('rate') || normalized.contains('confirmation')) {
            return 'Rate Confirmation';
        }

        if (normalized.contains('invoice')) {
            return 'Carrier Invoice';
        }

        if (normalized.contains('tender')) {
            return 'Load Tender';
        }

        return 'Other';
    }

    @TestVisible
    private static String inferDocumentTypeFromFields(Map<String, Object> extractedFields) {
        if (extractedFields == null || extractedFields.isEmpty()) {
            return null;
        }

        List<String> normalizedFieldKeys = new List<String>();
        for (String key : extractedFields.keySet()) {
            normalizedFieldKeys.add(normalize(key));
        }
        String combinedKeys = String.join(normalizedFieldKeys, ' ');

        if (combinedKeys.contains('bol') || combinedKeys.contains('billoflading') || combinedKeys.contains('pronumber') || normalizedFieldKeys.contains('pro')) {
            return 'BOL';
        }

        if (combinedKeys.contains('pod') || combinedKeys.contains('proofofdelivery') || combinedKeys.contains('signature')) {
            return 'POD';
        }

        if (combinedKeys.contains('invoice') || combinedKeys.contains('invoicenumber')) {
            return 'Carrier Invoice';
        }

        if (combinedKeys.contains('rateconfirmation') || combinedKeys.contains('carrierpay') || combinedKeys.contains('rate')) {
            return 'Rate Confirmation';
        }

        if (combinedKeys.contains('pickup') && combinedKeys.contains('delivery') && combinedKeys.contains('requiredtrailer')) {
            return 'Load Tender';
        }

        return null;
    }

    @TestVisible
    private static Decimal resolveOverallConfidence(
        Map<String, Object> apiResponse,
        Map<String, Object> extractedFields,
        Map<String, Object> fieldConfidencesByName
    ) {
        Decimal explicitConfidence = normalizeConfidenceForPercent(
            toDecimalOrNull(getFirstValue(apiResponse, new List<String>{
                'Confidence',
                'confidence',
                'OverallConfidence',
                'overallConfidence',
                'ClassificationConfidence',
                'classificationConfidence'
            }))
        );

        if (explicitConfidence != null) {
            return explicitConfidence;
        }

        List<Decimal> fieldConfidences = new List<Decimal>();
        collectFieldConfidencesFromExtractedFields(extractedFields, fieldConfidencesByName, fieldConfidences);

        if (fieldConfidences.isEmpty()) {
            return null;
        }

        Decimal total = 0;
        for (Decimal confidence : fieldConfidences) {
            total += confidence;
        }

        return total / fieldConfidences.size();
    }

    @TestVisible
    private static void collectFieldConfidencesFromExtractedFields(
        Map<String, Object> extractedFields,
        Map<String, Object> fieldConfidencesByName,
        List<Decimal> confidences
    ) {
        if (extractedFields == null || confidences == null) {
            return;
        }

        for (String fieldName : extractedFields.keySet()) {
            Object rawFieldObject = extractedFields.get(fieldName);
            Object rawValue = unwrapExtractedFieldValue(rawFieldObject);

            if (isEmpty(rawValue)) {
                continue;
            }

            Decimal confidence = getConfidenceForExtractedField(fieldName, rawFieldObject, fieldConfidencesByName);

            if (confidence != null) {
                confidences.add(confidence);
            }
        }
    }




    @TestVisible
    private static Object unwrapExtractedFieldValue(Object value) {
        if (!(value instanceof Map<String, Object>)) {
            return value;
        }

        Map<String, Object> valueMap = (Map<String, Object>) value;

        for (String key : valueMap.keySet()) {
            String normalizedKey = normalize(key);

            if (normalizedKey == 'value' || normalizedKey == 'rawvalue' || normalizedKey == 'extractedvalue' || normalizedKey == 'text' || normalizedKey == 'content') {
                return valueMap.get(key);
            }
        }

        return value;
    }

    @TestVisible
    private static Decimal normalizeConfidenceForPercent(Decimal confidence) {
        if (confidence == null) {
            return null;
        }

        return confidence <= 1 ? confidence * 100 : confidence;
    }

    @TestVisible
    private static Decimal toDecimalOrNull(Object value) {
        if (value == null) {
            return null;
        }

        try {
            String cleaned = cleanNumericValue(String.valueOf(value));
            return String.isBlank(cleaned) ? null : Decimal.valueOf(cleaned);
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static Map<String, Object> buildDetectedFieldsAudit(
        Map<String, Object> extractedFields,
        Map<String, Schema.SObjectField> objectFields,
        SObject recordToInsert,
        Map<String, Object> fieldConfidencesByName
    ) {
        Map<String, Object> audit = new Map<String, Object>();
        List<Object> savedToLoad = new List<Object>();
        List<Object> detectedNotSavedToLoad = new List<Object>();
        List<Object> rawDetectedFields = new List<Object>();

        if (extractedFields == null || extractedFields.isEmpty() || objectFields == null) {
            audit.put('savedToLoad', savedToLoad);
            audit.put('detectedNotSavedToLoad', detectedNotSavedToLoad);
            audit.put('rawDetectedFields', rawDetectedFields);
            audit.put('summary', new Map<String, Object>{
                'savedToLoadCount' => 0,
                'detectedNotSavedToLoadCount' => 0,
                'rawDetectedFieldCount' => 0
            });
            return audit;
        }

        Map<String, String> fieldsByNormalizedName = buildFieldNameMap(objectFields);
        Map<String, Object> populatedFields = recordToInsert == null
            ? new Map<String, Object>()
            : recordToInsert.getPopulatedFieldsAsMap();

        for (String extractedFieldName : extractedFields.keySet()) {
            Object rawFieldObject = extractedFields.get(extractedFieldName);
            Object rawValue = unwrapExtractedFieldValue(rawFieldObject);

            if (isEmpty(rawValue)) {
                continue;
            }

            String fieldApiName = fieldsByNormalizedName.get(normalize(extractedFieldName));
            Decimal confidence = getConfidenceForExtractedField(extractedFieldName, rawFieldObject, fieldConfidencesByName);
            Map<String, Object> row = new Map<String, Object>{
                'fieldName' => extractedFieldName,
                'value' => String.valueOf(rawValue),
                'confidence' => confidence
            };
            rawDetectedFields.add(row.clone());

            if (String.isBlank(fieldApiName) || !objectFields.containsKey(fieldApiName)) {
                row.put('reason', 'No matching Load field');
                detectedNotSavedToLoad.add(row);
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe = objectFields.get(fieldApiName).getDescribe();
            row.put('loadFieldApiName', fieldApiName);
            row.put('loadFieldLabel', fieldDescribe.getLabel());

            Boolean wasSavedToLoad = populatedFields.containsKey(fieldApiName);

            if (!wasSavedToLoad && recordToInsert != null) {
                try {
                    wasSavedToLoad = recordToInsert.get(fieldApiName) != null;
                } catch (Exception ignoredGet) {
                    wasSavedToLoad = false;
                }
            }

            if (!wasSavedToLoad &&
                fieldDescribe.isCreateable() &&
                !fieldDescribe.isCalculated() &&
                !fieldDescribe.isAutoNumber() &&
                fieldDescribe.getType() != Schema.DisplayType.Reference) {
                    try {
                        Object convertedValue = convertValueForField(
                            rawValue,
                            fieldDescribe
                        );

                        wasSavedToLoad = convertedValue != null;
                    } catch (Exception ignoredConvert) {
                        wasSavedToLoad = false;
                    }
            }

            if (wasSavedToLoad) {
                row.put('savedToLoad', true);
                row.put('reason', 'Saved to Load');
                savedToLoad.add(row);
                continue;
            }

            if (!fieldDescribe.isCreateable()) {
                row.put('reason', 'Matched Load field but field is not createable');
            } else if (fieldDescribe.isCalculated() || fieldDescribe.isAutoNumber()) {
                row.put('reason', 'Matched Load field but field is calculated or auto-number');
            } else if (fieldDescribe.getType() == Schema.DisplayType.Reference) {
                row.put('reason', 'Matched Load lookup field but lookup value was not created or found');
            } else {
                row.put('reason', 'Matched Load field but value was not saved');
            }

            detectedNotSavedToLoad.add(row);
        }

        audit.put('savedToLoad', savedToLoad);
        audit.put('detectedNotSavedToLoad', detectedNotSavedToLoad);
        audit.put('rawDetectedFields', rawDetectedFields);
        audit.put('summary', new Map<String, Object>{
            'savedToLoadCount' => savedToLoad.size(),
            'detectedNotSavedToLoadCount' => detectedNotSavedToLoad.size(),
            'rawDetectedFieldCount' => rawDetectedFields.size()
        });

        return audit;
    }

    @TestVisible
    private static Map<String, Object> getFieldConfidences(Map<String, Object> apiResponse) {
        Object value = getFirstValue(
            apiResponse,
            new List<String>{ 'FieldConfidences', 'fieldConfidences', 'FieldConfidence', 'fieldConfidence' }
        );

        return value instanceof Map<String, Object>
            ? (Map<String, Object>) value
            : new Map<String, Object>();
    }

    @TestVisible
    private static Decimal getConfidenceForExtractedField(
        String extractedFieldName,
        Object rawFieldObject,
        Map<String, Object> fieldConfidencesByName
    ) {
        Decimal inlineConfidence = extractConfidenceFromField(rawFieldObject);

        if (inlineConfidence != null) {
            return inlineConfidence;
        }

        if (fieldConfidencesByName == null || String.isBlank(extractedFieldName)) {
            return null;
        }

        String normalizedFieldName = normalize(extractedFieldName);

        for (String confidenceFieldName : fieldConfidencesByName.keySet()) {
            if (normalize(confidenceFieldName) == normalizedFieldName) {
                return normalizeConfidenceForPercent(toDecimalOrNull(fieldConfidencesByName.get(confidenceFieldName)));
            }
        }

        return null;
    }

    @TestVisible
    private static Decimal extractConfidenceFromField(Object rawFieldObject) {
        if (!(rawFieldObject instanceof Map<String, Object>)) {
            return null;
        }

        Object confidenceValue = getFirstValue(
            (Map<String, Object>) rawFieldObject,
            new List<String>{ 'Confidence', 'confidence', 'Score', 'score', 'ConfidencePercent', 'confidencePercent', 'ConfidencePercentage', 'confidencePercentage' }
        );

        return normalizeConfidenceForPercent(toDecimalOrNull(confidenceValue));
    }

    @TestVisible
    private static Integer getAuditSectionCount(Map<String, Object> audit, String sectionName) {
        if (audit == null || String.isBlank(sectionName) || !audit.containsKey(sectionName)) {
            return 0;
        }

        Object section = audit.get(sectionName);
        return section instanceof List<Object> ? ((List<Object>) section).size() : 0;
    }

    @TestVisible
    private static String serializeRawResponse(Object rawPayload) {
        if (rawPayload == null) {
            return null;
        }

        String serialized = rawPayload instanceof String
            ? String.valueOf(rawPayload)
            : JSON.serialize(rawPayload);
        Integer maxLength = 131000;

        return serialized.length() > maxLength
            ? serialized.substring(0, maxLength)
            : serialized;
    }

    @TestVisible
    private static String serializeDetectedFields(Map<String, Object> detectedFieldsPayload) {
        if (detectedFieldsPayload == null || detectedFieldsPayload.isEmpty()) {
            return null;
        }

        String serialized = JSON.serialize(detectedFieldsPayload);
        Integer maxLength = 32768;

        return serialized.length() > maxLength
            ? serialized.substring(0, maxLength)
            : serialized;
    }

    @TestVisible
    private static Boolean resolveAllFieldsDetected(Map<String, Object> apiResponse) {
        Object explicitValue = getFirstValue(
            apiResponse,
            new List<String>{ 'AllFieldsDetected', 'allFieldsDetected', 'AllRequiredFieldsDetected', 'allRequiredFieldsDetected', 'IsComplete', 'isComplete' }
        );

        if (explicitValue != null) {
            return parseBoolean(explicitValue);
        }

        Object missingFields = getFirstValue(
            apiResponse,
            new List<String>{ 'MissingFields', 'missingFields', 'RequiredFieldsMissing', 'requiredFieldsMissing' }
        );

        if (missingFields instanceof List<Object>) {
            return ((List<Object>) missingFields).isEmpty();
        }

        if (missingFields instanceof String) {
            return String.isBlank((String) missingFields);
        }

        Object lowConfidenceFields = getFirstValue(
            apiResponse,
            new List<String>{ 'LowConfidenceFields', 'lowConfidenceFields' }
        );

        if (lowConfidenceFields instanceof List<Object>) {
            return ((List<Object>) lowConfidenceFields).isEmpty();
        }

        if (lowConfidenceFields instanceof String) {
            return String.isBlank((String) lowConfidenceFields);
        }

        return null;
    }

    @TestVisible
    private static Object getValue(Map<String, Object> source, List<String> possibleKeys) {
        if (source == null || possibleKeys == null) {
            return null;
        }

        for (String key : possibleKeys) {
            if (source.containsKey(key)) {
                return source.get(key);
            }
        }

        return null;
    }

    @TestVisible
    private static String getStringValue(Map<String, Object> source, List<String> possibleKeys) {
        Object value = getValue(source, possibleKeys);
        return value == null ? null : String.valueOf(value);
    }


    /**
     * Returns a string value from the current map only. Key matching is
     * case/format insensitive, but nested maps are intentionally not searched.
     */
    @TestVisible
    private static String getDirectStringValue(
        Map<String, Object> source,
        List<String> possibleKeys
    ) {
        if (source == null || possibleKeys == null || possibleKeys.isEmpty()) {
            return null;
        }

        Set<String> normalizedKeys = new Set<String>();

        for (String possibleKey : possibleKeys) {
            normalizedKeys.add(normalize(possibleKey));
        }

        for (String sourceKey : source.keySet()) {
            if (!normalizedKeys.contains(normalize(sourceKey))) {
                continue;
            }

            Object value = source.get(sourceKey);
            return value == null ? null : String.valueOf(value);
        }

        return null;
    }

    @TestVisible
    private static String resolveProcessingIdentifier(
        Map<String, Object> payload,
        String fallbackDeliveryId
    ) {
        Object value = findDirectValue(
            payload,
            new Set<String>{
                'correlationid',
                'itemid',
                'documentid',
                'extractionid'
            }
        );

        if (value != null && !String.isBlank(String.valueOf(value))) {
            return String.valueOf(value).trim();
        }

        return String.isBlank(fallbackDeliveryId)
            ? null
            : fallbackDeliveryId.trim();
    }

    @TestVisible
    private static Id findProcessedRecord(
        String kind,
        String processingIdentifier,
        String objectApiName
    ) {
        if (String.isBlank(processingIdentifier) ||
            String.isBlank(objectApiName)) {
            return null;
        }

        String processingKey = buildProcessingKey(
            kind,
            objectApiName,
            processingIdentifier
        );

        if (transactionDedupCache.containsKey(processingKey)) {
            return transactionDedupCache.get(processingKey);
        }

        Schema.SObjectType objectType =
            Schema.getGlobalDescribe().get(objectApiName);

        if (objectType == null) {
            return null;
        }

        Map<String, Schema.SObjectField> objectFields =
            objectType.getDescribe().fields.getMap();

        if (!objectFields.containsKey(PROCESSING_KEY_FIELD) ||
            !objectFields.get(PROCESSING_KEY_FIELD)
                .getDescribe().isFilterable()) {
            return null;
        }

        Id existingId = queryFirstByFields(
            objectApiName,
            new Map<String, Object>{
                PROCESSING_KEY_FIELD => processingKey
            },
            false
        );

        if (existingId != null) {
            transactionDedupCache.put(processingKey, existingId);
        }

        return existingId;
    }

    @TestVisible
    private static void assignProcessingKey(
        SObject recordToInsert,
        String objectApiName,
        Map<String, Schema.SObjectField> objectFields,
        String kind,
        String processingIdentifier
    ) {
        if (recordToInsert == null ||
            String.isBlank(processingIdentifier) ||
            objectFields == null ||
            !objectFields.containsKey(PROCESSING_KEY_FIELD)) {
            return;
        }

        Schema.DescribeFieldResult fieldDescribe =
            objectFields.get(PROCESSING_KEY_FIELD).getDescribe();

        if (fieldDescribe.isCalculated() ||
            fieldDescribe.isAutoNumber()) {
            return;
        }

        recordToInsert.put(
            PROCESSING_KEY_FIELD,
            buildProcessingKey(kind, objectApiName, processingIdentifier)
        );
    }

    @TestVisible
    private static void cacheProcessedRecord(
        String kind,
        String processingIdentifier,
        String objectApiName,
        Id recordId
    ) {
        if (String.isBlank(processingIdentifier) ||
            String.isBlank(objectApiName) ||
            recordId == null) {
            return;
        }

        transactionDedupCache.put(
            buildProcessingKey(kind, objectApiName, processingIdentifier),
            recordId
        );
    }

    @TestVisible
    private static Resolution insertRecordOnce(
        String kind,
        String processingIdentifier,
        String objectApiName,
        SObject recordToInsert,
        Map<String, Schema.SObjectField> objectFields
    ) {
        if (recordToInsert == null || String.isBlank(objectApiName)) {
            throw new RecordCreationException('Record metadata is incomplete.');
        }

        if (String.isBlank(processingIdentifier)) {
            AutoFillSafeDml.insertRecord(recordToInsert);
            return new Resolution((Id) recordToInsert.get('Id'), true);
        }

        Id existingId = findProcessedRecord(
            kind,
            processingIdentifier,
            objectApiName
        );

        if (existingId != null) {
            return new Resolution(existingId, false);
        }

        assignProcessingKey(
            recordToInsert,
            objectApiName,
            objectFields,
            kind,
            processingIdentifier
        );

        try {
            AutoFillSafeDml.insertRecord(recordToInsert);
        } catch (Exception e) {
            existingId = findProcessedRecord(
                kind,
                processingIdentifier,
                objectApiName
            );

            if (existingId == null) {
                existingId = findExistingRecordByBusinessKey(
                    recordToInsert,
                    objectApiName,
                    objectFields
                );
            }

            if (existingId != null) {
                cacheProcessedRecord(
                    kind,
                    processingIdentifier,
                    objectApiName,
                    existingId
                );
                return new Resolution(existingId, false);
            }

            throw new RecordCreationException(e.getMessage());
        }

        Id insertedId = (Id) recordToInsert.get('Id');
        cacheProcessedRecord(
            kind,
            processingIdentifier,
            objectApiName,
            insertedId
        );
        return new Resolution(insertedId, true);
    }

    @TestVisible
    private static String buildProcessingKey(
        String kind,
        String objectApiName,
        String processingIdentifier
    ) {
        String safeKind = String.isBlank(kind)
            ? 'AUTOFILL'
            : kind.trim().toUpperCase();
        String safeObject = String.isBlank(objectApiName)
            ? 'UNKNOWN'
            : objectApiName.trim().toLowerCase();
        String safeSource = String.isBlank(processingIdentifier)
            ? ''
            : processingIdentifier.trim().toLowerCase();

        if (safeSource.length() > MAX_PROCESSING_SOURCE_LENGTH) {
            safeSource = safeSource.substring(
                0,
                MAX_PROCESSING_SOURCE_LENGTH
            );
        }

        String digest = EncodingUtil.convertToHex(
            Crypto.generateDigest(
                'SHA-256',
                Blob.valueOf(safeObject + '|' + safeSource)
            )
        ).toLowerCase();

        return safeKind + ':' + digest;
    }

    @TestVisible
    private static Resolution resolveOrCreateLookup(
        Schema.SObjectType referenceType,
        String nameFieldApiName,
        String rawLookupValue,
        SObject recordToCreate
    ) {
        if (referenceType == null || String.isBlank(nameFieldApiName)) {
            throw new RecordCreationException(
                'Lookup metadata is incomplete.'
            );
        }

        String cleanedValue = cleanDisplayValue(rawLookupValue);
        if (String.isBlank(cleanedValue)) {
            return new Resolution(null, false);
        }

        String objectApiName = referenceType.getDescribe().getName();
        String normalizedValue = normalizeLookupValue(cleanedValue);
        Id existingId = findExistingLookupId(
            objectApiName,
            nameFieldApiName,
            cleanedValue,
            normalizedValue
        );

        if (existingId != null) {
            return new Resolution(existingId, false);
        }

        if (recordToCreate == null) {
            throw new RecordCreationException(
                'Lookup record was not supplied for creation.'
            );
        }

        try {
            AutoFillSafeDml.insertRecord(recordToCreate);
        } catch (Exception e) {
            existingId = findExistingLookupId(
                objectApiName,
                nameFieldApiName,
                cleanedValue,
                normalizedValue
            );

            if (existingId != null) {
                return new Resolution(existingId, false);
            }

            throw new RecordCreationException(e.getMessage());
        }

        return new Resolution((Id) recordToCreate.get('Id'), true);
    }

    @TestVisible
    private static String cleanDisplayValue(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        return value
            .replaceAll('[\\r\\n\\t]+', ' ')
            .replaceAll(' +', ' ')
            .trim();
    }

    @TestVisible
    private static String normalizeLookupValue(String value) {
        String cleaned = cleanDisplayValue(value);
        if (String.isBlank(cleaned)) {
            return '';
        }

        String normalizedValue = cleaned
            .toLowerCase()
            .replaceAll('[^a-z0-9]+', '');

        return String.isBlank(normalizedValue)
            ? cleaned.toLowerCase()
            : normalizedValue;
    }

    @TestVisible
    private static Id findExistingLookupId(
        String objectApiName,
        String nameFieldApiName,
        String cleanedLookupValue,
        String normalizedLookupValue
    ) {
        Map<String, Object> exactBinds = new Map<String, Object>{
            'lookupValue' => cleanedLookupValue
        };
        List<SObject> exactMatches = Database.queryWithBinds(
            'SELECT Id, ' + nameFieldApiName +
            ' FROM ' + objectApiName +
            ' WHERE ' + nameFieldApiName + ' = :lookupValue' +
            ' ORDER BY CreatedDate ASC LIMIT 1',
            exactBinds,
            AccessLevel.SYSTEM_MODE
        );

        if (!exactMatches.isEmpty()) {
            return (Id) exactMatches[0].get('Id');
        }

        String patternBody = cleanedLookupValue.replaceAll(
            '[^A-Za-z0-9]+',
            '%'
        );

        if (String.isBlank(patternBody) ||
            String.isBlank(patternBody.replace('%', ''))) {
            return null;
        }

        String lookupPattern = '%' + patternBody + '%';
        List<SObject> candidates = Database.queryWithBinds(
            'SELECT Id, ' + nameFieldApiName +
            ' FROM ' + objectApiName +
            ' WHERE ' + nameFieldApiName + ' LIKE :lookupPattern' +
            ' ORDER BY CreatedDate ASC LIMIT 500',
            new Map<String, Object>{
                'lookupPattern' => lookupPattern
            },
            AccessLevel.SYSTEM_MODE
        );

        for (SObject candidate : candidates) {
            String candidateName = String.valueOf(
                candidate.get(nameFieldApiName)
            );

            if (normalizeLookupValue(candidateName) ==
                normalizedLookupValue) {
                return (Id) candidate.get('Id');
            }
        }

        return null;
    }

    @TestVisible
    private static Object findDirectValue(
        Map<String, Object> source,
        Set<String> normalizedKeys
    ) {
        if (source == null || normalizedKeys == null) {
            return null;
        }

        for (String key : source.keySet()) {
            if (normalizedKeys.contains(normalize(key))) {
                Object value = source.get(key);
                if (value != null) {
                    return value;
                }
            }
        }

        return null;
    }

    @TestVisible
    private static Id findOrCreateLookup(
        Schema.DescribeFieldResult lookupField,
        String lookupValue,
        String extractedFieldName,
        Map<String, Object> extractedFields
    ) {
        String cleanedLookupValue =
            cleanDisplayValue(lookupValue);

        if (String.isBlank(cleanedLookupValue)) {
            return null;
        }

        List<Schema.SObjectType> referenceTypes =
            lookupField.getReferenceTo();

        if (referenceTypes == null || referenceTypes.isEmpty()) {
            throw new RecordCreationException(
                'The lookup has no reference object.'
            );
        }

        if (referenceTypes.size() > 1) {
            throw new RecordCreationException(
                'Polymorphic lookups are not supported automatically.'
            );
        }

        Schema.SObjectType referenceType = referenceTypes[0];
        Schema.DescribeSObjectResult referenceDescribe =
            referenceType.getDescribe();
        String referenceObjectApiName = referenceDescribe.getName();

        Schema.SObjectField nameField =
            getCreateableNameField(referenceDescribe);

        if (nameField == null) {
            throw new RecordCreationException(
                'No usable name field was found on ' +
                referenceObjectApiName +
                '.'
            );
        }

        String nameFieldApiName =
            nameField.getDescribe().getName();
        String normalizedLookupValue =
            normalizeLookupValue(cleanedLookupValue);
        String cacheKey =
            referenceObjectApiName + ':' + normalizedLookupValue;

        if (lookupIdCache.containsKey(cacheKey)) {
            return lookupIdCache.get(cacheKey);
        }

        SObject lookupRecord = referenceType.newSObject();
        lookupRecord.put(nameFieldApiName, cleanedLookupValue);

        if (isFacilityField(extractedFieldName)) {
            populateFacilityFields(
                lookupRecord,
                referenceDescribe,
                extractedFieldName,
                extractedFields
            );
        }

        Resolution resolution;

        try {
            resolution = resolveOrCreateLookup(
                referenceType,
                nameFieldApiName,
                cleanedLookupValue,
                lookupRecord
            );
        } catch (Exception e) {
            throw new RecordCreationException(
                'Could not resolve ' +
                referenceObjectApiName +
                ' "' + cleanedLookupValue +
                '": ' + e.getMessage()
            );
        }

        if (resolution.recordId != null) {
            lookupIdCache.put(cacheKey, resolution.recordId);
        }

        return resolution.recordId;
    }

    @TestVisible
    private static void populateFacilityFields(
        SObject facilityRecord,
        Schema.DescribeSObjectResult facilityDescribe,
        String extractedFacilityField,
        Map<String, Object> extractedFields
    ) {
        String prefix = normalize(extractedFacilityField) == 'pickupfacility'
            ? 'Pickup '
            : 'Delivery ';

        Map<String, Schema.SObjectField> facilityFields = facilityDescribe.fields.getMap();
        Map<String, String> normalizedFacilityFields = buildFieldNameMap(facilityFields);

        Map<String, List<String>> fieldCandidates = new Map<String, List<String>>{
            'City' => new List<String>{ 'City' },
            'State/Province' => new List<String>{ 'State/Province', 'State Province', 'State' },
            'Street' => new List<String>{ 'Street', 'Street Address', 'Address' },
            'Zip Code' => new List<String>{ 'Zip Code', 'ZIP/Postal Code', 'Postal Code', 'Zip' },
            'Country' => new List<String>{ 'Country', 'Country/Territory' }
        };

        for (String sourceSuffix : fieldCandidates.keySet()) {
            Object rawValue = getExtractedValue(extractedFields, prefix + sourceSuffix);

            if (isEmpty(rawValue)) {
                continue;
            }

            String facilityFieldApiName = findCandidateField(
                normalizedFacilityFields,
                fieldCandidates.get(sourceSuffix)
            );

            if (String.isBlank(facilityFieldApiName)) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe =
                facilityFields.get(facilityFieldApiName).getDescribe();

            if (
                fieldDescribe.isCalculated() ||
                fieldDescribe.isAutoNumber() ||
                fieldDescribe.getType() == Schema.DisplayType.Reference
            ) {
                continue;
            }

            try {
                Object convertedValue = convertValueForField(rawValue, fieldDescribe);

                if (convertedValue != null) {
                    facilityRecord.put(facilityFieldApiName, convertedValue);
                }
            } catch (Exception e) {
                System.debug(
                    'Could not populate Facility field ' +
                    facilityFieldApiName +
                    ' from "' +
                    prefix +
                    sourceSuffix +
                    '". Reason: ' +
                    e.getMessage()
                );
            }
        }
    }


    /**
     * Resolves the parent object only from explicit API metadata. There is no
     * Load fallback. This prevents a V2 response with missing metadata from
     * creating the wrong Salesforce object.
     */
    @TestVisible
    private static String resolveParentObjectApiName(
        Map<String, Object> apiResponse
    ) {
        String objectApiName = getStringValue(
            apiResponse,
            new List<String>{
                'SalesforceObjectType',
                'salesforceObjectType',
                'ParentObject',
                'parentObject',
                'ParentObjectApiName',
                'parentObjectApiName'
            }
        );

        if (isUsableObjectApiName(objectApiName)) {
            return objectApiName;
        }

        Map<String, Object> metadata = getResponseMetadata(apiResponse);

        objectApiName = getStringValue(
            metadata,
            new List<String>{
                'SalesforceObjectType',
                'salesforceObjectType',
                'ParentObject',
                'parentObject',
                'ParentObjectApiName',
                'parentObjectApiName'
            }
        );

        if (isUsableObjectApiName(objectApiName)) {
            return objectApiName;
        }

        Map<String, Object> parentDefinition = getMapValue(
            metadata,
            new List<String>{
                'salesforceParent',
                'SalesforceParent',
                'parent',
                'Parent'
            }
        );

        objectApiName = getStringValue(
            parentDefinition,
            new List<String>{
                'SalesforceObjectType',
                'salesforceObjectType',
                'ObjectApiName',
                'objectApiName',
                'ParentObjectApiName',
                'parentObjectApiName'
            }
        );

        if (isUsableObjectApiName(objectApiName)) {
            return objectApiName;
        }

        Map<String, Object> objectGraph = getMapValue(
            metadata,
            new List<String>{ 'objectGraph', 'ObjectGraph' }
        );

        parentDefinition = getMapValue(
            objectGraph,
            new List<String>{
                'salesforceParent',
                'SalesforceParent',
                'parent',
                'Parent'
            }
        );

        objectApiName = getStringValue(
            parentDefinition,
            new List<String>{
                'SalesforceObjectType',
                'salesforceObjectType',
                'ObjectApiName',
                'objectApiName',
                'ParentObjectApiName',
                'parentObjectApiName'
            }
        );

        if (isUsableObjectApiName(objectApiName)) {
            return objectApiName;
        }

        return resolveLegacyV2ParentObjectApiName(apiResponse);
    }

    /**
     * Backward compatibility for the current FreightGraph V2 contract.
     *
     * New/generic payloads should always return the parent object explicitly.
     * The currently deployed V2 extractor identifies only `pipeline = v2` and
     * historically represents a Load graph. This fallback restores that parent
     * only for that exact legacy envelope. It does not infer or create children.
     */
    @TestVisible
    private static String resolveLegacyV2ParentObjectApiName(
        Map<String, Object> apiResponse
    ) {
        if (apiResponse == null) {
            return null;
        }

        Map<String, Object> metadata = getResponseMetadata(apiResponse);
        String pipeline = getDirectStringValue(
            metadata,
            new List<String>{
                'pipeline',
                'Pipeline',
                'pipelineVersion',
                'PipelineVersion'
            }
        );

        if (String.isBlank(pipeline)) {
            pipeline = getDirectStringValue(
                apiResponse,
                new List<String>{
                    'pipeline',
                    'Pipeline',
                    'pipelineVersion',
                    'PipelineVersion'
                }
            );
        }

        if (String.isBlank(pipeline)) {
            Map<String, Object> objectGraph = getMapValue(
                metadata,
                new List<String>{ 'objectGraph', 'ObjectGraph' }
            );
            pipeline = getDirectStringValue(
                objectGraph,
                new List<String>{
                    'pipeline',
                    'Pipeline',
                    'pipelineVersion',
                    'PipelineVersion'
                }
            );
        }

        String normalizedPipeline = normalize(pipeline);
        if (normalizedPipeline != 'v2' && normalizedPipeline != '2') {
            return null;
        }

        Object extractedObject = getFirstObjectValue(
            apiResponse,
            new List<String>{ 'ExtractedFields', 'extractedFields' }
        );

        if (!(extractedObject instanceof Map<String, Object>)) {
            return null;
        }

        return resolveExistingSObjectApiName(LOAD_OBJECT_API_NAME);
    }

    /**
     * Creates direct child records for any parent object, but only when the API
     * explicitly defines the child collection in metadata. Collection names,
     * object labels, plural names, Legs, and Line Items are never guessed.
     */
    @TestVisible
    private static Integer createV2ChildRecords(
        Map<String, Object> apiResponse,
        Id parentRecordId,
        String parentObjectApiName
    ) {
        if (parentRecordId == null ||
            String.isBlank(parentObjectApiName)) {
            return 0;
        }

        Map<String, Object> collections = getV2Collections(apiResponse);

        if (collections == null || collections.isEmpty()) {
            return 0;
        }

        Integer createdCount = 0;

        for (String collectionName : collections.keySet()) {
            Object rowsObject = collections.get(collectionName);

            if (!(rowsObject instanceof List<Object>) ||
                ((List<Object>) rowsObject).isEmpty()) {
                continue;
            }

            V2ChildDefinition childDefinition =
                resolveV2ChildDefinition(
                    apiResponse,
                    collectionName
                );

            if (childDefinition == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'Skipping child collection because it has no explicit ' +
                    'Salesforce child definition in API metadata: ' +
                    collectionName
                );
                continue;
            }

            childDefinition.objectApiName = resolveExistingSObjectApiName(
                childDefinition.objectApiName
            );

            if (String.isBlank(childDefinition.objectApiName)) {
                System.debug(
                    LoggingLevel.WARN,
                    'Skipping child collection because the explicitly defined ' +
                    'Salesforce object does not exist: ' + collectionName
                );
                continue;
            }

            Schema.SObjectType childObjectType =
                Schema.getGlobalDescribe().get(
                    childDefinition.objectApiName
                );
            Schema.DescribeSObjectResult childDescribe =
                childObjectType.getDescribe();

            Map<String, Schema.SObjectField> childFields =
                childDescribe.fields.getMap();
            Map<String, String> fieldsByNormalizedName =
                buildFieldNameMap(childFields);

            String parentLookupFieldApiName =
                resolveConfiguredFieldApiName(
                    childFields,
                    childDefinition.parentLookupFieldApiName
                );

            if (String.isBlank(parentLookupFieldApiName)) {
                parentLookupFieldApiName =
                    findParentLookupFieldApiName(
                        childFields,
                        parentObjectApiName
                    );
            }

            Schema.SObjectField parentLookupField =
                String.isBlank(parentLookupFieldApiName)
                ? null
                : childFields.get(parentLookupFieldApiName);

            if (parentLookupField == null ||
                !isReferenceToParent(
                    parentLookupField.getDescribe(),
                    parentObjectApiName
                )) {
                System.debug(
                    LoggingLevel.WARN,
                    'Skipping child collection because no unique createable ' +
                    'lookup/master-detail field to ' + parentObjectApiName +
                    ' was explicitly configured or safely resolved on ' +
                    childDefinition.objectApiName + ': ' + collectionName
                );
                continue;
            }

            List<SObject> recordsToInsert = new List<SObject>();

            for (Object rowObject : (List<Object>) rowsObject) {
                Map<String, Object> extractedChildFields =
                    extractChildRowFields(rowObject);

                if (extractedChildFields == null ||
                    extractedChildFields.isEmpty()) {
                    continue;
                }

                SObject childRecord = childObjectType.newSObject();
                Boolean hasMappedValue = false;

                for (String extractedFieldName :
                     extractedChildFields.keySet()) {
                    Object rawValue = unwrapExtractedFieldValue(
                        extractedChildFields.get(extractedFieldName)
                    );

                    if (isEmpty(rawValue)) {
                        continue;
                    }

                    String fieldApiName = getMappedFieldApiName(
                        childDefinition.fieldMappings,
                        fieldsByNormalizedName,
                        extractedFieldName
                    );

                    if (String.isBlank(fieldApiName) ||
                        fieldApiName == parentLookupFieldApiName) {
                        continue;
                    }

                    Schema.SObjectField childField =
                        childFields.get(fieldApiName);

                    if (childField == null) {
                        continue;
                    }

                    Schema.DescribeFieldResult fieldDescribe =
                        childField.getDescribe();

                    if (!fieldDescribe.isCreateable() ||
                        fieldDescribe.isCalculated() ||
                        fieldDescribe.isAutoNumber()) {
                        continue;
                    }

                    try {
                        if (fieldDescribe.getType() ==
                            Schema.DisplayType.Reference) {
                            Id lookupId = findOrCreateLookup(
                                fieldDescribe,
                                String.valueOf(rawValue).trim(),
                                extractedFieldName,
                                extractedChildFields
                            );

                            if (lookupId != null) {
                                childRecord.put(fieldApiName, lookupId);
                                hasMappedValue = true;
                            }
                        } else {
                            Object convertedValue = convertValueForField(
                                rawValue,
                                fieldDescribe
                            );

                            if (convertedValue != null) {
                                childRecord.put(
                                    fieldApiName,
                                    convertedValue
                                );
                                hasMappedValue = true;
                            }
                        }
                    } catch (Exception e) {
                        System.debug(
                            LoggingLevel.WARN,
                            'Skipping child field "' +
                            extractedFieldName + '" for ' +
                            childDefinition.objectApiName +
                            '. Reason: ' + e.getMessage()
                        );
                    }
                }

                // A relationship value alone is never enough to create a child.
                // At least one actual child field must have mapped successfully.
                if (!hasMappedValue) {
                    continue;
                }

                childRecord.put(
                    parentLookupFieldApiName,
                    parentRecordId
                );
                recordsToInsert.add(childRecord);
            }

            if (recordsToInsert.isEmpty()) {
                continue;
            }

            Database.SaveResult[] childInsertResults =
                Database.insert(recordsToInsert, false);

            for (Integer resultIndex = 0;
                 resultIndex < childInsertResults.size();
                 resultIndex++) {
                Database.SaveResult childInsertResult =
                    childInsertResults[resultIndex];

                if (childInsertResult.isSuccess()) {
                    createdCount++;
                    continue;
                }

                List<String> childErrors = new List<String>();

                for (Database.Error childError :
                     childInsertResult.getErrors()) {
                    childErrors.add(childError.getMessage());
                }

                System.debug(
                    LoggingLevel.WARN,
                    'Skipping child row ' +
                    String.valueOf(resultIndex + 1) +
                    ' for ' + childDefinition.objectApiName +
                    '. Reason: ' + String.join(childErrors, ' | ')
                );
            }
        }

        return createdCount;
    }

    @TestVisible
    private static Map<String, Object> getV2Collections(
        Map<String, Object> apiResponse
    ) {
        Map<String, Object> metadata = getResponseMetadata(apiResponse);

        Object collectionsObject = getFirstObjectValue(
            metadata,
            new List<String>{ 'collections', 'Collections' }
        );

        if (!(collectionsObject instanceof Map<String, Object>)) {
            collectionsObject = getFirstObjectValue(
                apiResponse,
                new List<String>{ 'collections', 'Collections' }
            );
        }

        if (!(collectionsObject instanceof Map<String, Object>)) {
            Map<String, Object> objectGraph = getMapValue(
                metadata,
                new List<String>{ 'objectGraph', 'ObjectGraph' }
            );

            collectionsObject = getFirstObjectValue(
                objectGraph,
                new List<String>{ 'collections', 'Collections' }
            );
        }

        return collectionsObject instanceof Map<String, Object>
            ? (Map<String, Object>) collectionsObject
            : null;
    }

    @TestVisible
    private static Map<String, Object> getResponseMetadata(
        Map<String, Object> apiResponse
    ) {
        if (apiResponse == null) {
            return new Map<String, Object>();
        }

        Object metadataObject = apiResponse.get('Metadata');

        if (!(metadataObject instanceof Map<String, Object>)) {
            metadataObject = apiResponse.get('metadata');
        }

        return metadataObject instanceof Map<String, Object>
            ? (Map<String, Object>) metadataObject
            : new Map<String, Object>();
    }

    /**
     * Returns only an explicit child definition from the API. It never creates
     * a definition from the collection name and never guesses an SObject.
     */
    @TestVisible
    private static V2ChildDefinition resolveV2ChildDefinition(
        Map<String, Object> apiResponse,
        String collectionName
    ) {
        V2ChildDefinition definition =
            findV2ChildDefinitionInMetadata(
                apiResponse,
                collectionName
            );

        if (definition == null ||
            String.isBlank(definition.objectApiName)) {
            return null;
        }

        definition.collectionName = collectionName;
        return definition;
    }

    @TestVisible
    private static V2ChildDefinition findV2ChildDefinitionInMetadata(
        Map<String, Object> apiResponse,
        String collectionName
    ) {
        Map<String, Object> metadata = getResponseMetadata(apiResponse);
        Object definitionsObject = getFirstObjectValue(
            metadata,
            new List<String>{
                'salesforceChildren',
                'SalesforceChildren',
                'childDefinitions',
                'ChildDefinitions'
            }
        );

        if (definitionsObject == null) {
            Map<String, Object> objectGraph = getMapValue(
                metadata,
                new List<String>{ 'objectGraph', 'ObjectGraph' }
            );

            definitionsObject = getFirstObjectValue(
                objectGraph,
                new List<String>{
                    'salesforceChildren',
                    'SalesforceChildren',
                    'childDefinitions',
                    'ChildDefinitions',
                    'children',
                    'Children'
                }
            );
        }

        if (definitionsObject == null) {
            definitionsObject = getFirstObjectValue(
                apiResponse,
                new List<String>{
                    'salesforceChildren',
                    'SalesforceChildren',
                    'childDefinitions',
                    'ChildDefinitions'
                }
            );
        }

        if (definitionsObject instanceof List<Object>) {
            for (Object item : (List<Object>) definitionsObject) {
                V2ChildDefinition definition =
                    parseV2ChildDefinition(null, item);

                if (definition != null &&
                    namesMatch(
                        definition.collectionName,
                        collectionName
                    )) {
                    return definition;
                }
            }
        }

        if (definitionsObject instanceof Map<String, Object>) {
            Map<String, Object> definitions =
                (Map<String, Object>) definitionsObject;

            for (String key : definitions.keySet()) {
                V2ChildDefinition definition =
                    parseV2ChildDefinition(
                        key,
                        definitions.get(key)
                    );

                if (definition != null &&
                    namesMatch(
                        definition.collectionName,
                        collectionName
                    )) {
                    return definition;
                }
            }
        }

        return null;
    }

    @TestVisible
    private static V2ChildDefinition parseV2ChildDefinition(
        String fallbackCollectionName,
        Object rawDefinition
    ) {
        V2ChildDefinition definition = new V2ChildDefinition();
        definition.collectionName = fallbackCollectionName;

        if (rawDefinition instanceof String) {
            definition.objectApiName =
                String.valueOf(rawDefinition);
            return definition;
        }

        if (!(rawDefinition instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> definitionMap =
            (Map<String, Object>) rawDefinition;

        String collectionName = getFirstStringFromMap(
            definitionMap,
            new List<String>{
                'collectionKey',
                'CollectionKey',
                'collectionName',
                'CollectionName',
                'key',
                'Key'
            }
        );

        if (!String.isBlank(collectionName)) {
            definition.collectionName = collectionName;
        }

        definition.objectApiName = getFirstStringFromMap(
            definitionMap,
            new List<String>{
                'SalesforceObjectType',
                'salesforceObjectType',
                'objectApiName',
                'ObjectApiName',
                'childObjectApiName',
                'ChildObjectApiName'
            }
        );

        definition.parentLookupFieldApiName =
            getFirstStringFromMap(
                definitionMap,
                new List<String>{
                    'parentLookupField',
                    'ParentLookupField',
                    'parentLookupFieldApiName',
                    'ParentLookupFieldApiName',
                    'relationshipField',
                    'RelationshipField'
                }
            );

        Object mappingsObject = getFirstObjectValue(
            definitionMap,
            new List<String>{
                'fieldMappings',
                'FieldMappings',
                'fields',
                'Fields'
            }
        );

        definition.fieldMappings =
            parseFieldMappings(mappingsObject);

        return definition;
    }

    @TestVisible
    private static Map<String, Object> extractChildRowFields(
        Object rowObject
    ) {
        if (!(rowObject instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> row =
            (Map<String, Object>) rowObject;
        Object nestedFields = getFirstObjectValue(
            row,
            new List<String>{
                'ExtractedFields',
                'extractedFields',
                'recordFields',
                'RecordFields'
            }
        );

        return nestedFields instanceof Map<String, Object>
            ? (Map<String, Object>) nestedFields
            : row;
    }

    @TestVisible
    private static String resolveConfiguredFieldApiName(
        Map<String, Schema.SObjectField> objectFields,
        String configuredFieldName
    ) {
        if (objectFields == null ||
            String.isBlank(configuredFieldName)) {
            return null;
        }

        if (objectFields.containsKey(configuredFieldName)) {
            return configuredFieldName;
        }

        Map<String, String> normalizedFields =
            buildFieldNameMap(objectFields);
        return normalizedFields.get(
            normalize(configuredFieldName)
        );
    }

    /**
     * Safely infers the relationship only when exactly one createable reference
     * field points to the parent. Multiple possible relationships are treated
     * as ambiguous and require explicit metadata.
     */
    @TestVisible
    private static String findParentLookupFieldApiName(
        Map<String, Schema.SObjectField> childFields,
        String parentObjectApiName
    ) {
        if (childFields == null ||
            String.isBlank(parentObjectApiName)) {
            return null;
        }

        List<String> candidates = new List<String>();

        for (String fieldApiName : childFields.keySet()) {
            Schema.DescribeFieldResult fieldDescribe =
                childFields.get(fieldApiName).getDescribe();

            if (!isReferenceToParent(
                    fieldDescribe,
                    parentObjectApiName
                )) {
                continue;
            }

            candidates.add(fieldApiName);
        }

        return candidates.size() == 1
            ? candidates[0]
            : null;
    }

    @TestVisible
    private static Boolean isReferenceToParent(
        Schema.DescribeFieldResult fieldDescribe,
        String parentObjectApiName
    ) {
        if (fieldDescribe == null ||
            String.isBlank(parentObjectApiName) ||
            fieldDescribe.getType() != Schema.DisplayType.Reference) {
            return false;
        }

        for (Schema.SObjectType referenceType :
             fieldDescribe.getReferenceTo()) {
            if (referenceType.getDescribe().getName() ==
                parentObjectApiName) {
                return true;
            }
        }

        return false;
    }

    @TestVisible
    private static String resolveExistingSObjectApiName(
        String requestedObjectApiName
    ) {
        if (!isUsableObjectApiName(requestedObjectApiName)) {
            return null;
        }

        String trimmedName = requestedObjectApiName.trim();
        Map<String, Schema.SObjectType> globalDescribe =
            Schema.getGlobalDescribe();

        if (globalDescribe.containsKey(trimmedName)) {
            return trimmedName;
        }

        for (String existingApiName : globalDescribe.keySet()) {
            if (existingApiName.equalsIgnoreCase(trimmedName)) {
                return existingApiName;
            }
        }

        return null;
    }

    @TestVisible
    private static Map<String, String> getV2ParentFieldMappings(
        Map<String, Object> apiResponse
    ) {
        Map<String, Object> metadata = getResponseMetadata(apiResponse);
        Map<String, Object> parentDefinition = getMapValue(
            metadata,
            new List<String>{
                'salesforceParent',
                'SalesforceParent',
                'parent',
                'Parent'
            }
        );

        if (parentDefinition.isEmpty()) {
            Map<String, Object> objectGraph = getMapValue(
                metadata,
                new List<String>{ 'objectGraph', 'ObjectGraph' }
            );
            parentDefinition = getMapValue(
                objectGraph,
                new List<String>{
                    'salesforceParent',
                    'SalesforceParent',
                    'parent',
                    'Parent'
                }
            );
        }

        Object mappingsObject = getFirstObjectValue(
            parentDefinition,
            new List<String>{
                'fieldMappings',
                'FieldMappings',
                'fields',
                'Fields'
            }
        );

        return parseFieldMappings(mappingsObject);
    }

    @TestVisible
    private static Map<String, String> parseFieldMappings(
        Object mappingsObject
    ) {
        Map<String, String> result = new Map<String, String>();

        if (!(mappingsObject instanceof Map<String, Object>)) {
            return result;
        }

        Map<String, Object> mappings =
            (Map<String, Object>) mappingsObject;

        for (String sourceName : mappings.keySet()) {
            Object mappingValue = mappings.get(sourceName);
            String fieldApiName;

            if (mappingValue instanceof String) {
                fieldApiName = String.valueOf(mappingValue);
            } else if (mappingValue instanceof Map<String, Object>) {
                fieldApiName = getFirstStringFromMap(
                    (Map<String, Object>) mappingValue,
                    new List<String>{
                        'fieldApiName',
                        'FieldApiName',
                        'salesforceFieldApiName',
                        'SalesforceFieldApiName',
                        'targetField',
                        'TargetField'
                    }
                );
            }

            if (!String.isBlank(fieldApiName)) {
                result.put(normalize(sourceName), fieldApiName);
            }
        }

        return result;
    }

    @TestVisible
    private static String getMappedFieldApiName(
        Map<String, String> explicitMappings,
        Map<String, String> inferredMappings,
        String extractedFieldName
    ) {
        String normalizedName = normalize(extractedFieldName);
        String fieldApiName = explicitMappings == null
            ? null
            : explicitMappings.get(normalizedName);

        if (!String.isBlank(fieldApiName)) {
            // Explicit mappings may return either an API name or a label.
            // Resolve it only against fields that actually exist on the
            // target object. A stale or org-specific mapping is skipped
            // instead of being passed into dynamic SObject operations.
            return inferredMappings == null
                ? null
                : inferredMappings.get(normalize(fieldApiName));
        }

        if (inferredMappings == null) {
            return null;
        }

        fieldApiName = inferredMappings.get(normalizedName);

        if (!String.isBlank(fieldApiName)) {
            return fieldApiName;
        }

        // Use a conservative unique partial match for small naming
        // differences such as "Delivery State" versus
        // "Delivery State/Province". Ambiguous matches are skipped.
        String partialMatch;
        Boolean ambiguous = false;

        for (String candidateName : inferredMappings.keySet()) {
            if (String.isBlank(candidateName) ||
                (!candidateName.startsWith(normalizedName) &&
                 !normalizedName.startsWith(candidateName))) {
                continue;
            }

            String candidateFieldApiName =
                inferredMappings.get(candidateName);

            if (String.isBlank(partialMatch)) {
                partialMatch = candidateFieldApiName;
            } else if (partialMatch != candidateFieldApiName) {
                ambiguous = true;
                break;
            }
        }

        return ambiguous ? null : partialMatch;
    }

    @TestVisible
    private static Map<String, Object> getMapValue(
        Map<String, Object> source,
        List<String> keys
    ) {
        Object value = getFirstObjectValue(source, keys);
        return value instanceof Map<String, Object>
            ? (Map<String, Object>) value
            : new Map<String, Object>();
    }

    @TestVisible
    private static Object getFirstObjectValue(
        Map<String, Object> source,
        List<String> keys
    ) {
        if (source == null || keys == null) {
            return null;
        }

        for (String key : keys) {
            if (source.containsKey(key)) {
                return source.get(key);
            }
        }

        return null;
    }

    @TestVisible
    private static String getFirstStringFromMap(
        Map<String, Object> source,
        List<String> keys
    ) {
        Object value = getFirstObjectValue(source, keys);
        return value == null ? null : String.valueOf(value);
    }

    @TestVisible
    private static Boolean isUsableObjectApiName(String value) {
        return !String.isBlank(value) &&
            !value.equalsIgnoreCase('null');
    }

    @TestVisible
    private static Boolean namesMatch(
        String firstName,
        String secondName
    ) {
        return !String.isBlank(firstName) &&
            !String.isBlank(secondName) &&
            normalize(firstName) == normalize(secondName);
    }

    @TestVisible
    private static Map<String, String> buildFieldNameMap(
        Map<String, Schema.SObjectField> objectFields
    ) {
        Map<String, String> result = new Map<String, String>();

        for (String fieldApiName : objectFields.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = objectFields.get(fieldApiName).getDescribe();

            addFieldMapping(result, normalize(fieldApiName), fieldApiName);
            addFieldMapping(result, normalize(fieldDescribe.getLabel()), fieldApiName);

            String localApiName = fieldApiName;

            if (localApiName.contains('__')) {
                List<String> parts = localApiName.split('__');

                if (parts.size() >= 3) {
                    localApiName = parts[1];
                } else if (parts.size() == 2) {
                    localApiName = parts[0];
                }
            }

            addFieldMapping(result, normalize(localApiName), fieldApiName);
        }

        return result;
    }

    @TestVisible
    private static void addFieldMapping(
        Map<String, String> mappings,
        String normalizedName,
        String fieldApiName
    ) {
        if (!String.isBlank(normalizedName) && !mappings.containsKey(normalizedName)) {
            mappings.put(normalizedName, fieldApiName);
        }
    }

    @TestVisible
    private static Schema.SObjectField getCreateableNameField(
        Schema.DescribeSObjectResult objectDescribe
    ) {
        Map<String, Schema.SObjectField> fields =
            objectDescribe.fields.getMap();

        for (Schema.SObjectField field : fields.values()) {
            Schema.DescribeFieldResult fieldDescribe =
                field.getDescribe();

            if (fieldDescribe.isNameField() &&
                fieldDescribe.isCreateable() &&
                !fieldDescribe.isAutoNumber() &&
                !fieldDescribe.isCalculated()) {
                return field;
            }
        }

        return null;
    }


    /**
     * Converts an extracted value for a specific Salesforce field.
     * Invalid restricted picklist values are intentionally ignored so one
     * optional field cannot prevent the parent record from being created.
     */
    @TestVisible
    private static Object convertValueForField(
        Object rawValue,
        Schema.DescribeFieldResult fieldDescribe
    ) {
        if (rawValue == null || fieldDescribe == null) {
            return null;
        }

        Schema.DisplayType fieldType = fieldDescribe.getType();

        if (fieldType == Schema.DisplayType.Picklist) {
            String rawText = String.valueOf(rawValue).trim();

            if (String.isBlank(rawText)) {
                return null;
            }

            // Unrestricted picklists accept values not already present in
            // the value set. Restricted picklists must match an active
            // Salesforce value; otherwise only this field is skipped.
            if (!fieldDescribe.isRestrictedPicklist()) {
                return skipOversizedOptionalValue(
                    rawText,
                    fieldDescribe
                );
            }

            return skipOversizedOptionalValue(
                resolveValidPicklistValue(
                    rawText,
                    fieldDescribe.getPicklistValues()
                ),
                fieldDescribe
            );
        }

        if (fieldType == Schema.DisplayType.MultiPicklist) {
            String rawText = String.valueOf(rawValue).trim();

            if (String.isBlank(rawText)) {
                return null;
            }

            List<String> submittedValues = rawText.split('[;,]');

            if (!fieldDescribe.isRestrictedPicklist()) {
                List<String> cleanedValues = new List<String>();

                for (String submittedValue : submittedValues) {
                    String cleanedValue = submittedValue == null
                        ? null
                        : submittedValue.trim();

                    if (!String.isBlank(cleanedValue) &&
                        !cleanedValues.contains(cleanedValue)) {
                        cleanedValues.add(cleanedValue);
                    }
                }

                return skipOversizedOptionalValue(
                    cleanedValues.isEmpty()
                        ? null
                        : String.join(cleanedValues, ';'),
                    fieldDescribe
                );
            }

            List<String> validValues = new List<String>();

            for (String candidate : submittedValues) {
                String validValue = resolveValidPicklistValue(
                    candidate,
                    fieldDescribe.getPicklistValues()
                );

                if (!String.isBlank(validValue) &&
                    !validValues.contains(validValue)) {
                    validValues.add(validValue);
                }
            }

            return skipOversizedOptionalValue(
                validValues.isEmpty()
                    ? null
                    : String.join(validValues, ';'),
                fieldDescribe
            );
        }

        Object convertedValue = convertValue(rawValue, fieldType);
        return skipOversizedOptionalValue(convertedValue, fieldDescribe);
    }

    @TestVisible
    private static Object skipOversizedOptionalValue(
        Object convertedValue,
        Schema.DescribeFieldResult fieldDescribe
    ) {
        if (!(convertedValue instanceof String) ||
            fieldDescribe == null) {
            return convertedValue;
        }

        Integer maximumLength = fieldDescribe.getLength();
        String textValue = String.valueOf(convertedValue);
        Boolean optionalOnCreate = fieldDescribe.isNillable() ||
            fieldDescribe.isDefaultedOnCreate();

        if (optionalOnCreate &&
            maximumLength > 0 &&
            textValue.length() > maximumLength) {
            System.debug(
                LoggingLevel.WARN,
                'AutoFill skipped an oversized optional value for field ' +
                fieldDescribe.getName() + '. Maximum length: ' +
                maximumLength + ', received length: ' +
                textValue.length() + '.'
            );
            return null;
        }

        return convertedValue;
    }

    @TestVisible
    private static String resolveValidPicklistValue(
        String rawValue,
        List<Schema.PicklistEntry> entries
    ) {
        String candidate = String.isBlank(rawValue)
            ? null
            : rawValue.trim();

        if (String.isBlank(candidate) || entries == null) {
            return null;
        }

        for (Schema.PicklistEntry entry : entries) {
            if (!entry.isActive()) {
                continue;
            }

            if (candidate.equalsIgnoreCase(entry.getValue()) ||
                candidate.equalsIgnoreCase(entry.getLabel())) {
                return entry.getValue();
            }
        }

        System.debug(
            LoggingLevel.WARN,
            'Skipping invalid restricted picklist value "' +
            candidate +
            '".'
        );

        return null;
    }

    @TestVisible
    private static Object convertValue(Object rawValue, Schema.DisplayType fieldType) {
        if (rawValue == null) {
            return null;
        }

        String value = String.valueOf(rawValue).trim();

        if (String.isBlank(value)) {
            return null;
        }

        if (fieldType == Schema.DisplayType.Boolean) {
            return parseBoolean(rawValue);
        }

        if (fieldType == Schema.DisplayType.Integer) {
            String numericValue = cleanNumericValue(value);
            return numericValue == null ? null : Decimal.valueOf(numericValue).intValue();
        }

        if (
            fieldType == Schema.DisplayType.Double ||
            fieldType == Schema.DisplayType.Currency ||
            fieldType == Schema.DisplayType.Percent
        ) {
            String numericValue = cleanNumericValue(value);
            return numericValue == null ? null : Decimal.valueOf(numericValue);
        }

        if (fieldType == Schema.DisplayType.Date) {
            if (value.length() >= 10) {
                value = value.substring(0, 10);
            }

            if (value.startsWith('0001-')) {
                return null;
            }

            return Date.valueOf(value);
        }

        if (fieldType == Schema.DisplayType.DateTime) {
            if (value.startsWith('0001-')) {
                return null;
            }

            return JSON.deserialize(JSON.serialize(value), Datetime.class);
        }

        if (fieldType == Schema.DisplayType.Time) {
            return parseTime(value);
        }

        return value;
    }

    @TestVisible
    private static Boolean parseBoolean(Object rawValue) {
        if (rawValue == null) {
            return false;
        }

        String value = String.valueOf(rawValue).trim().toLowerCase();

        return value == 'true' ||
            value == 'yes' ||
            value == 'y' ||
            value == '1';
    }

    @TestVisible
    private static Time parseTime(String value) {
        String cleanedValue = value.trim().replace('Z', '');
        List<String> parts = cleanedValue.split(':');

        if (parts.size() < 2) {
            throw new RecordCreationException('Invalid time value: ' + value);
        }

        Integer hour = Integer.valueOf(parts[0]);
        Integer minute = Integer.valueOf(parts[1]);
        Integer second = 0;
        Integer millisecond = 0;

        if (parts.size() >= 3) {
            List<String> secondParts = parts[2].split('\\.');
            second = Integer.valueOf(secondParts[0]);

            if (secondParts.size() > 1) {
                String milliseconds = secondParts[1];

                if (milliseconds.length() > 3) {
                    milliseconds = milliseconds.substring(0, 3);
                }

                while (milliseconds.length() < 3) {
                    milliseconds += '0';
                }

                millisecond = Integer.valueOf(milliseconds);
            }
        }

        return Time.newInstance(hour, minute, second, millisecond);
    }

    @TestVisible
    private static Boolean isEmpty(Object value) {
        return value == null ||
            (value instanceof String && String.isBlank((String) value));
    }

    @TestVisible
    private static String normalize(String value) {
        if (String.isBlank(value)) {
            return '';
        }

        return value.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    @TestVisible
    private static String cleanNumericValue(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        String normalized = value.trim().toLowerCase();

        if (
            normalized == 'true' ||
            normalized == 'false' ||
            normalized == 'yes' ||
            normalized == 'no'
        ) {
            return null;
        }

        String cleaned = value
            .replace(',', '')
            .replace('$', '')
            .replace('€', '')
            .replace('£', '')
            .replace('%', '')
            .trim();

        return String.isBlank(cleaned) ? null : cleaned;
    }

    @TestVisible
    private static Boolean isFacilityField(String extractedFieldName) {
        if (String.isBlank(extractedFieldName)) {
            return false;
        }

        String normalizedName = normalize(extractedFieldName);

        return normalizedName == 'pickupfacility' ||
            normalizedName == 'deliveryfacility';
    }

    @TestVisible
    private static Object getExtractedValue(
        Map<String, Object> extractedFields,
        String requestedFieldName
    ) {
        String requestedNormalized = normalize(requestedFieldName);

        for (String fieldName : extractedFields.keySet()) {
            if (normalize(fieldName) == requestedNormalized) {
                return extractedFields.get(fieldName);
            }
        }

        return null;
    }

    @TestVisible
    private static String findCandidateField(
        Map<String, String> normalizedFields,
        List<String> candidates
    ) {
        for (String candidate : candidates) {
            String fieldApiName = normalizedFields.get(normalize(candidate));

            if (!String.isBlank(fieldApiName)) {
                return fieldApiName;
            }
        }

        return null;
    }

    /**
     * A client-correctable payload, mapping, or record-creation error.
     * Public visibility lets REST controllers return HTTP 422 instead of
     * hiding these errors behind a generic HTTP 500 response.
     */
    public class RecordCreationException extends Exception {}
}