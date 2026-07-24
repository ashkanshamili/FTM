public without sharing class AutoFillWebhookPayloadAdapter {

    private static final String LOAD_OBJECT_API_NAME =
        'FreightTM__Load__c';

    private static final Integer MAX_SEARCH_DEPTH = 6;

    public class PayloadException extends Exception {
    }

    /**
     * Normalizes both legacy V1 LoadDetails payloads and current/generic V2
     * extraction payloads into the contract expected by
     * AutoFillService.
     */
    public static Map<String, Object> normalize(Object rawPayload) {
        Object decodedPayload = decodeJsonValue(rawPayload, 0);
        Map<String, Object> root = asMap(decodedPayload);

        if (root == null || root.isEmpty()) {
            throw new PayloadException(
                'The webhook payload does not contain a JSON object.'
            );
        }

        Map<String, Object> candidate = findPayloadCandidate(
            root,
            0
        );

        if (candidate == null) {
            candidate = root;
        }

        Map<String, Object> normalized = deepCloneMap(candidate);

        Object reportedSuccess = findFirstValue(
            root,
            new Set<String>{ 'success', 'issuccess', 'succeeded' },
            0
        );

        if (
            reportedSuccess != null &&
            parseBoolean(reportedSuccess) == false
        ) {
            Object reportedMessage = findFirstValue(
                root,
                new Set<String>{
                    'message',
                    'error',
                    'errormessage',
                    'failurereason'
                },
                0
            );

            throw new PayloadException(
                reportedMessage == null
                ? 'FreightGraph reported that extraction failed.'
                : String.valueOf(reportedMessage)
            );
        }

        Map<String, Object> loadDetails = findDirectMap(
            candidate,
            new Set<String>{
                'loaddetails',
                'load',
                'shipmentdetails',
                'shipment'
            }
        );

        if (loadDetails == null && candidate != root) {
            loadDetails = findDirectMap(
                root,
                new Set<String>{
                    'loaddetails',
                    'load',
                    'shipmentdetails',
                    'shipment'
                }
            );
        }

        Map<String, Object> extractedFields = extractFieldsMap(
            findFirstValue(
                candidate,
                new Set<String>{
                    'extractedfields',
                    'detectedfields',
                    'recordfields',
                    'fields'
                },
                0
            )
        );

        if (
            (extractedFields == null || extractedFields.isEmpty()) &&
            candidate != root
        ) {
            extractedFields = extractFieldsMap(
                findFirstValue(
                    root,
                    new Set<String>{
                        'extractedfields',
                        'detectedfields',
                        'recordfields'
                    },
                    0
                )
            );
        }

        Map<String, Object> finalFields = new Map<String, Object>();

        if (loadDetails != null && !loadDetails.isEmpty()) {
            mergeFields(
                finalFields,
                convertLegacyLoadFields(loadDetails)
            );

            mergeFields(
                finalFields,
                extractFieldsMap(
                    findDirectValue(
                        loadDetails,
                        new Set<String>{
                            'extractedfields',
                            'detectedfields',
                            'recordfields'
                        }
                    )
                )
            );
        }

        mergeFields(finalFields, extractedFields);

        if (finalFields.isEmpty()) {
            Map<String, Object> directLegacyFields =
                convertLegacyLoadFields(candidate);

            if (directLegacyFields.isEmpty() && candidate != root) {
                directLegacyFields = convertLegacyLoadFields(root);
            }

            mergeFields(finalFields, directLegacyFields);
        }

        if (finalFields.isEmpty()) {
            throw new PayloadException(
                'The webhook payload does not contain extracted fields.'
            );
        }

        String explicitObjectApiName = resolveExplicitObjectApiName(
            candidate,
            root
        );

        if (
            String.isBlank(explicitObjectApiName) &&
            isLegacyLoadEnvelope(
                candidate,
                root,
                loadDetails,
                finalFields
            )
        ) {
            explicitObjectApiName = LOAD_OBJECT_API_NAME;
        }

        if (!String.isBlank(explicitObjectApiName)) {
            normalized.put(
                'SalesforceObjectType',
                canonicalizeObjectApiName(explicitObjectApiName)
            );
        }
        normalized.put('ExtractedFields', finalFields);
        normalized.put('Success', true);

        copyCanonicalValue(
            root,
            normalized,
            'ItemId',
            new Set<String>{
                'itemid',
                'correlationid',
                'documentid',
                'extractionid',
                'loadid'
            }
        );
        copyCanonicalValue(
            root,
            normalized,
            'DetectedDocumentType',
            new Set<String>{
                'detecteddocumenttype',
                'documenttype',
                'doctype'
            }
        );
        copyCanonicalValue(
            root,
            normalized,
            'Confidence',
            new Set<String>{
                'confidence',
                'overallconfidence',
                'documentconfidence'
            }
        );
        copyCanonicalValue(
            root,
            normalized,
            'ClassificationConfidence',
            new Set<String>{ 'classificationconfidence' }
        );
        copyCanonicalValue(
            root,
            normalized,
            'AllFieldsDetected',
            new Set<String>{
                'allfieldsdetected',
                'allrequiredfieldsdetected',
                'iscomplete'
            }
        );
        copyCanonicalValue(
            root,
            normalized,
            'MissingFields',
            new Set<String>{
                'missingfields',
                'requiredfieldsmissing'
            }
        );
        copyCanonicalValue(
            root,
            normalized,
            'Metadata',
            new Set<String>{ 'metadata' }
        );

        if (!hasDirectKey(normalized, 'AutoFillSource')) {
            normalized.put('AutoFillSource', 'Webhook');
        }

        return normalized;
    }

    @TestVisible
    private static Map<String, Object> findPayloadCandidate(
        Map<String, Object> source,
        Integer depth
    ) {
        if (source == null || depth > MAX_SEARCH_DEPTH) {
            return null;
        }

        if (looksLikePayload(source)) {
            return source;
        }

        for (String wrapperName : new List<String>{
            'payload',
            'data',
            'result',
            'response',
            'body',
            'extraction',
            'extractionresult',
            'document',
            'webhook'
        }) {
            Object wrapperValue = findDirectValue(
                source,
                new Set<String>{ wrapperName }
            );
            wrapperValue = decodeJsonValue(
                wrapperValue,
                depth + 1
            );

            Map<String, Object> wrapperMap = asMap(wrapperValue);

            if (wrapperMap == null) {
                continue;
            }

            Map<String, Object> nestedCandidate =
                findPayloadCandidate(wrapperMap, depth + 1);

            if (nestedCandidate != null) {
                return nestedCandidate;
            }
        }

        for (Object value : source.values()) {
            Object decodedValue = decodeJsonValue(
                value,
                depth + 1
            );
            Map<String, Object> nestedMap = asMap(decodedValue);

            if (nestedMap == null) {
                continue;
            }

            Map<String, Object> nestedCandidate =
                findPayloadCandidate(nestedMap, depth + 1);

            if (nestedCandidate != null) {
                return nestedCandidate;
            }
        }

        return null;
    }

    @TestVisible
    private static Boolean looksLikePayload(
        Map<String, Object> source
    ) {
        if (source == null || source.isEmpty()) {
            return false;
        }

        Set<String> payloadKeys = new Set<String>{
            'loaddetails',
            'extractedfields',
            'detectedfields',
            'salesforceobjecttype',
            'parentobject',
            'parentobjectapiname'
        };

        for (String key : source.keySet()) {
            if (payloadKeys.contains(normalizeKey(key))) {
                return true;
            }
        }

        Integer legacyLoadFieldCount = 0;
        Set<String> legacyLoadKeys = getLegacyLoadFieldMappings().keySet();

        for (String key : source.keySet()) {
            if (legacyLoadKeys.contains(normalizeKey(key))) {
                legacyLoadFieldCount++;
            }
        }

        return legacyLoadFieldCount >= 2;
    }

    @TestVisible
    private static Map<String, Object> convertLegacyLoadFields(
        Map<String, Object> source
    ) {
        Map<String, Object> converted = new Map<String, Object>();

        if (source == null) {
            return converted;
        }

        Map<String, String> mappings = getLegacyLoadFieldMappings();
        Set<String> ignoredKeys = new Set<String>{
            'success',
            'message',
            'errors',
            'metadata',
            'extractedtext',
            'extractedfields',
            'detectedfields',
            'recordfields',
            'salesforceobjecttype',
            'parentobject',
            'parentobjectapiname',
            'pipeline',
            'pipelineversion',
            'webhookstatus'
        };

        for (String sourceKey : source.keySet()) {
            String normalizedKey = normalizeKey(sourceKey);

            if (ignoredKeys.contains(normalizedKey)) {
                continue;
            }

            Object rawValue = source.get(sourceKey);

            if (isEmptyValue(rawValue)) {
                continue;
            }

            String targetFieldName = mappings.get(normalizedKey);

            if (String.isBlank(targetFieldName)) {
                targetFieldName = sourceKey;
            }

            converted.put(targetFieldName, rawValue);
        }

        return converted;
    }

    @TestVisible
    private static Map<String, String> getLegacyLoadFieldMappings() {
        return new Map<String, String>{
            'origin' => 'FreightTM__Pickup_City__c',
            'origincity' => 'FreightTM__Pickup_City__c',
            'pickupcity' => 'FreightTM__Pickup_City__c',
            'originstate' => 'FreightTM__Pickup_State__c',
            'pickupstate' => 'FreightTM__Pickup_State__c',
            'destination' => 'FreightTM__Delivery_City__c',
            'destinationcity' => 'FreightTM__Delivery_City__c',
            'deliverycity' => 'FreightTM__Delivery_City__c',
            'destinationstate' => 'FreightTM__Delivery_State__c',
            'deliverystate' => 'FreightTM__Delivery_State__c',
            'weight' => 'FreightTM__Weight__c',
            'equipmenttype' => 'FreightTM__Required_Trailer__c',
            'requiredtrailer' => 'FreightTM__Required_Trailer__c',
            'pickupdate' => 'FreightTM__Pickup_Date__c',
            'deliverydate' => 'FreightTM__Delivery_Date__c',
            'rate' => 'FreightTM__Rate__c',
            'confirmationnumber' => 'FreightTM__Confirmation_Number__c',
            'commodity' => 'FreightTM__Commodity__c',
            'priority' => 'FreightTM__Priority__c',
            'status' => 'FreightTM__Status__c',
            'pro' => 'FreightTM__PRO__c',
            'pronumber' => 'FreightTM__PRO__c',
            'hazmat' => 'FreightTM__Hazmat__c',
            'quote' => 'FreightTM__Quote__c',
            'ratetocarrier' => 'FreightTM__Rate_to_Carrier__c',
            'pickupcontact' => 'FreightTM__Pickup_Contact__c',
            'deliverycontact' => 'FreightTM__Delivery_Contact__c',
            'pickupphone' => 'FreightTM__Pickup_Phone__c',
            'deliveryphone' => 'FreightTM__Delivery_Phone__c',
            'pickupemail' => 'FreightTM__Pickup_Email__c',
            'deliveryemail' => 'FreightTM__Delivery_Email__c',
            'pickupref' => 'FreightTM__Pickup_Ref__c',
            'deliveryref' => 'FreightTM__Delivery_Ref__c',
            'pickupremarks' => 'FreightTM__Pickup_Remarks__c',
            'deliveryremarks' => 'FreightTM__Delivery_Remarks__c',
            'distance' => 'FreightTM__Distance__c',
            'temperature' => 'FreightTM__Temperature__c',
            'numberofpallets' => 'FreightTM__Number_of_Pallets__c',
            'containernumber' => 'FreightTM__Container_Number__c',
            'length' => 'FreightTM__Length__c',
            'width' => 'FreightTM__Width__c',
            'height' => 'FreightTM__Height__c',
            'remarks' => 'FreightTM__Remarks__c',
            'billstatus' => 'FreightTM__Bill_Status__c',
            'paystatus' => 'FreightTM__Pay_Status__c',
            'invoicestatus' => 'FreightTM__Invoice_Status__c',
            'billedon' => 'FreightTM__Billed_On__c',
            'paydate' => 'FreightTM__Pay_Date__c',
            'invoicedate' => 'FreightTM__Invoiced_On__c',
            'factoringrate' => 'FreightTM__Factoring_Rate__c',
            'factoring' => 'FreightTM__Factoring__c'
        };
    }

    @TestVisible
    private static Map<String, Object> extractFieldsMap(Object value) {
        value = decodeJsonValue(value, 0);

        if (value instanceof Map<String, Object>) {
            return (Map<String, Object>) value;
        }

        Map<String, Object> result = new Map<String, Object>();

        if (!(value instanceof List<Object>)) {
            return result;
        }

        for (Object rowObject : (List<Object>) value) {
            rowObject = decodeJsonValue(rowObject, 1);

            if (!(rowObject instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> row =
                (Map<String, Object>) rowObject;
            Object fieldNameValue = findDirectValue(
                row,
                new Set<String>{
                    'fieldname',
                    'name',
                    'key',
                    'label',
                    'salesforcefieldapiname'
                }
            );

            if (fieldNameValue == null) {
                continue;
            }

            String fieldName = String.valueOf(fieldNameValue).trim();

            if (String.isBlank(fieldName)) {
                continue;
            }

            Object fieldValue = findDirectValue(
                row,
                new Set<String>{
                    'value',
                    'fieldvalue',
                    'extractedvalue',
                    'text'
                }
            );

            if (fieldValue == null) {
                fieldValue = row;
            } else if (
                findDirectValue(
                    row,
                    new Set<String>{
                        'confidence',
                        'score',
                        'confidencepercent',
                        'confidencepercentage'
                    }
                ) != null
            ) {
                fieldValue = row;
            }

            result.put(fieldName, fieldValue);
        }

        return result;
    }

    @TestVisible
    private static Boolean isLegacyLoadEnvelope(
        Map<String, Object> candidate,
        Map<String, Object> root,
        Map<String, Object> loadDetails,
        Map<String, Object> extractedFields
    ) {
        if (loadDetails != null && !loadDetails.isEmpty()) {
            return true;
        }

        Object pipelineValue = findFirstValue(
            candidate,
            new Set<String>{ 'pipeline', 'pipelineversion' },
            0
        );

        if (pipelineValue == null && candidate != root) {
            pipelineValue = findFirstValue(
                root,
                new Set<String>{ 'pipeline', 'pipelineversion' },
                0
            );
        }

        String normalizedPipeline = pipelineValue == null
            ? ''
            : normalizeKey(String.valueOf(pipelineValue));

        if (
            normalizedPipeline == 'v1' ||
            normalizedPipeline == '1' ||
            normalizedPipeline == 'v2' ||
            normalizedPipeline == '2'
        ) {
            return true;
        }

        if (extractedFields == null || extractedFields.isEmpty()) {
            return false;
        }

        Set<String> loadIndicators = new Set<String>{
            'origin',
            'origincity',
            'pickupcity',
            'freighttmpickupcityc',
            'destination',
            'destinationcity',
            'deliverycity',
            'freighttmdeliverycityc',
            'pickupdate',
            'freighttmpickupdatec',
            'deliverydate',
            'freighttmdeliverydatec',
            'equipmenttype',
            'requiredtrailer',
            'freighttmrequiredtrailerc',
            'pronumber',
            'freighttmproc'
        };

        for (String fieldName : extractedFields.keySet()) {
            if (loadIndicators.contains(normalizeKey(fieldName))) {
                return true;
            }
        }

        return false;
    }

    @TestVisible
    private static String resolveExplicitObjectApiName(
        Map<String, Object> candidate,
        Map<String, Object> root
    ) {
        Set<String> directObjectKeys = new Set<String>{
            'salesforceobjecttype',
            'parentobject',
            'parentobjectapiname'
        };

        Object value = findDirectValue(
            candidate,
            directObjectKeys
        );

        if (value == null && candidate != root) {
            value = findDirectValue(root, directObjectKeys);
        }

        if (value != null) {
            return String.valueOf(value);
        }

        Map<String, Object> metadata = findDirectMap(
            candidate,
            new Set<String>{ 'metadata' }
        );

        if ((metadata == null || metadata.isEmpty()) && candidate != root) {
            metadata = findDirectMap(
                root,
                new Set<String>{ 'metadata' }
            );
        }

        if (metadata == null || metadata.isEmpty()) {
            return null;
        }

        value = findDirectValue(metadata, directObjectKeys);

        if (value != null) {
            return String.valueOf(value);
        }

        Map<String, Object> parentDefinition = findDirectMap(
            metadata,
            new Set<String>{ 'salesforceparent', 'parent' }
        );

        value = findDirectValue(
            parentDefinition,
            new Set<String>{
                'salesforceobjecttype',
                'objectapiname',
                'parentobjectapiname'
            }
        );

        if (value != null) {
            return String.valueOf(value);
        }

        Map<String, Object> objectGraph = findDirectMap(
            metadata,
            new Set<String>{ 'objectgraph' }
        );
        parentDefinition = findDirectMap(
            objectGraph,
            new Set<String>{ 'salesforceparent', 'parent' }
        );
        value = findDirectValue(
            parentDefinition,
            new Set<String>{
                'salesforceobjecttype',
                'objectapiname',
                'parentobjectapiname'
            }
        );

        return value == null ? null : String.valueOf(value);
    }

    @TestVisible
    private static String canonicalizeObjectApiName(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        String normalizedValue = normalizeKey(value);

        if (
            normalizedValue == 'load' ||
            normalizedValue == 'loads' ||
            normalizedValue == 'shipment' ||
            normalizedValue == 'freightload' ||
            normalizedValue == 'freighttmload' ||
            normalizedValue == 'freighttmloadc'
        ) {
            return LOAD_OBJECT_API_NAME;
        }

        return value.trim();
    }

    @TestVisible
    private static void copyCanonicalValue(
        Map<String, Object> source,
        Map<String, Object> target,
        String canonicalKey,
        Set<String> possibleKeys
    ) {
        if (
            source == null ||
            target == null ||
            hasDirectKey(target, canonicalKey)
        ) {
            return;
        }

        Object value = findFirstValue(
            source,
            possibleKeys,
            0
        );

        if (value != null) {
            target.put(canonicalKey, value);
        }
    }

    @TestVisible
    private static void mergeFields(
        Map<String, Object> target,
        Map<String, Object> source
    ) {
        if (target == null || source == null) {
            return;
        }

        Set<String> existingNormalizedKeys = new Set<String>();

        for (String existingKey : target.keySet()) {
            existingNormalizedKeys.add(normalizeKey(existingKey));
        }

        for (String sourceKey : source.keySet()) {
            String normalizedSourceKey = normalizeKey(sourceKey);

            if (
                String.isBlank(normalizedSourceKey) ||
                existingNormalizedKeys.contains(normalizedSourceKey)
            ) {
                continue;
            }

            target.put(sourceKey, source.get(sourceKey));
            existingNormalizedKeys.add(normalizedSourceKey);
        }
    }

    @TestVisible
    private static Map<String, Object> deepCloneMap(
        Map<String, Object> source
    ) {
        if (source == null) {
            return new Map<String, Object>();
        }

        return (Map<String, Object>) JSON.deserializeUntyped(
            JSON.serialize(source)
        );
    }

    @TestVisible
    private static Object decodeJsonValue(
        Object value,
        Integer depth
    ) {
        if (
            !(value instanceof String) ||
            depth > MAX_SEARCH_DEPTH
        ) {
            return value;
        }

        String text = String.valueOf(value).trim();

        if (
            !(text.startsWith('{') || text.startsWith('['))
        ) {
            return value;
        }

        try {
            return JSON.deserializeUntyped(text);
        } catch (Exception ignoredInvalidNestedJson) {
            return value;
        }
    }

    @TestVisible
    private static Map<String, Object> asMap(Object value) {
        if (value instanceof Map<String, Object>) {
            return (Map<String, Object>) value;
        }

        if (value instanceof List<Object>) {
            for (Object item : (List<Object>) value) {
                Object decodedItem = decodeJsonValue(item, 1);

                if (decodedItem instanceof Map<String, Object>) {
                    return (Map<String, Object>) decodedItem;
                }
            }
        }

        return null;
    }

    @TestVisible
    private static Map<String, Object> findDirectMap(
        Map<String, Object> source,
        Set<String> possibleKeys
    ) {
        Object value = findDirectValue(source, possibleKeys);
        value = decodeJsonValue(value, 0);
        return asMap(value);
    }

    @TestVisible
    private static Object findDirectValue(
        Map<String, Object> source,
        Set<String> possibleKeys
    ) {
        if (source == null || possibleKeys == null) {
            return null;
        }

        for (String key : source.keySet()) {
            if (possibleKeys.contains(normalizeKey(key))) {
                return source.get(key);
            }
        }

        return null;
    }

    @TestVisible
    private static Object findFirstValue(
        Object source,
        Set<String> possibleKeys,
        Integer depth
    ) {
        if (
            source == null ||
            possibleKeys == null ||
            depth > MAX_SEARCH_DEPTH
        ) {
            return null;
        }

        source = decodeJsonValue(source, depth);

        if (source instanceof Map<String, Object>) {
            Map<String, Object> sourceMap =
                (Map<String, Object>) source;
            Object directValue = findDirectValue(
                sourceMap,
                possibleKeys
            );

            if (directValue != null) {
                return directValue;
            }

            for (Object childValue : sourceMap.values()) {
                Object nestedValue = findFirstValue(
                    childValue,
                    possibleKeys,
                    depth + 1
                );

                if (nestedValue != null) {
                    return nestedValue;
                }
            }
        } else if (source instanceof List<Object>) {
            for (Object childValue : (List<Object>) source) {
                Object nestedValue = findFirstValue(
                    childValue,
                    possibleKeys,
                    depth + 1
                );

                if (nestedValue != null) {
                    return nestedValue;
                }
            }
        }

        return null;
    }

    @TestVisible
    private static Boolean hasDirectKey(
        Map<String, Object> source,
        String requestedKey
    ) {
        if (source == null || String.isBlank(requestedKey)) {
            return false;
        }

        String normalizedRequestedKey = normalizeKey(requestedKey);

        for (String key : source.keySet()) {
            if (normalizeKey(key) == normalizedRequestedKey) {
                return true;
            }
        }

        return false;
    }

    @TestVisible
    private static Boolean parseBoolean(Object value) {
        if (value == null) {
            return false;
        }

        if (value instanceof Boolean) {
            return (Boolean) value;
        }

        String normalizedValue = normalizeKey(String.valueOf(value));
        return normalizedValue == 'true' ||
            normalizedValue == '1' ||
            normalizedValue == 'yes' ||
            normalizedValue == 'success' ||
            normalizedValue == 'completed';
    }

    @TestVisible
    private static Boolean isEmptyValue(Object value) {
        if (value == null) {
            return true;
        }

        if (value instanceof String) {
            String text = String.valueOf(value).trim();
            return String.isBlank(text) ||
                text.equalsIgnoreCase('null');
        }

        if (value instanceof Map<String, Object>) {
            return ((Map<String, Object>) value).isEmpty();
        }

        if (value instanceof List<Object>) {
            return ((List<Object>) value).isEmpty();
        }

        return false;
    }

    @TestVisible
    private static String normalizeKey(String value) {
        if (String.isBlank(value)) {
            return '';
        }

        return value
            .toLowerCase()
            .replaceAll('[^a-z0-9]', '');
    }
}