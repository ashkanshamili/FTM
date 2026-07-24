public without sharing class AutoFillSafeDml {

    private static final Integer MAX_INSERT_ATTEMPTS = 25;
    private static final String RESTRICTED_PICKLIST_MARKER =
        'bad value for restricted picklist field:';

    private static final String LOAD_OBJECT_API_NAME =
        'FreightTM__Load__c';
    private static final String LOAD_STATUS_FIELD_API_NAME =
        'FreightTM__Status__c';
    private static final String LOAD_STATUS_FALLBACK =
        'Assigned';

    public class SafeDmlException extends Exception {}

    /**
     * Inserts an AutoFill-created record in system mode.
     *
     * Invalid optional restricted picklist values are removed and retried.
     * FreightTM__Load__c.FreightTM__Status__c is handled separately because
     * some Load record types do not allow the API value "Open". In that case,
     * AutoFill replaces it with the valid operational fallback "Assigned".
     */
    public static void insertRecord(SObject recordToInsert) {
        if (recordToInsert == null) {
            throw new SafeDmlException('Record was not supplied for insert.');
        }

        Set<String> handledFieldValues = new Set<String>();

        // Remove optional extracted text values that exceed the actual
        // Salesforce field limit before DML. This keeps one oversized value,
        // such as Commodity, from rejecting the complete AutoFill record.
        clearOversizedOptionalTextFields(recordToInsert);

        for (Integer attempt = 1;
             attempt <= MAX_INSERT_ATTEMPTS;
             attempt++) {
            try {
                Database.insert(
                    recordToInsert,
                    AccessLevel.SYSTEM_MODE
                );
                return;
            } catch (DmlException e) {
                Boolean correctedInvalidPicklist =
                    correctInvalidRestrictedPicklists(
                        recordToInsert,
                        e,
                        handledFieldValues
                    );
                Boolean correctedOversizedText =
                    correctStringTooLongFields(
                        recordToInsert,
                        e,
                        handledFieldValues
                    );

                if (!correctedInvalidPicklist &&
                    !correctedOversizedText) {
                    throw e;
                }
            }
        }

        throw new SafeDmlException(
            'Salesforce could not create the record after correcting invalid ' +
            'optional field values.'
        );
    }

    /**
     * Clears populated optional text-like fields whose extracted values are
     * longer than the destination Salesforce field. Required values are not
     * silently removed because doing so would still produce an invalid
     * record.
     */
    @TestVisible
    private static Boolean clearOversizedOptionalTextFields(
        SObject recordToInsert
    ) {
        if (recordToInsert == null) {
            return false;
        }

        Map<String, Schema.SObjectField> fields =
            recordToInsert.getSObjectType()
                .getDescribe()
                .fields
                .getMap();
        Map<String, Object> populatedFields =
            recordToInsert.getPopulatedFieldsAsMap();
        Boolean clearedAnyField = false;

        for (String fieldApiName : populatedFields.keySet()) {
            Object currentValue = populatedFields.get(fieldApiName);
            Schema.SObjectField fieldToken = fields.get(fieldApiName);

            if (!(currentValue instanceof String) || fieldToken == null) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe =
                fieldToken.getDescribe();
            Integer maximumLength = fieldDescribe.getLength();

            if (maximumLength <= 0 ||
                String.valueOf(currentValue).length() <= maximumLength ||
                !isOptionalOnCreate(fieldDescribe)) {
                continue;
            }

            recordToInsert.put(fieldApiName, null);
            clearedAnyField = true;

            System.debug(
                LoggingLevel.WARN,
                'AutoFill skipped optional field ' + fieldApiName +
                ' because its extracted value exceeded the Salesforce ' +
                'maximum length of ' + maximumLength + ' characters.'
            );
        }

        return clearedAnyField;
    }

    /**
     * Fallback for STRING_TOO_LONG errors that are only exposed by DML.
     * Salesforce normally returns the offending field API name in the DML
     * error. The field is cleared and the same record is retried.
     */
    @TestVisible
    private static Boolean correctStringTooLongFields(
        SObject recordToInsert,
        DmlException error,
        Set<String> handledFieldValues
    ) {
        if (recordToInsert == null || error == null) {
            return false;
        }

        Set<String> candidateFieldNames = new Set<String>();
        Boolean hasStringTooLongError = false;

        for (Integer index = 0;
             index < error.getNumDml();
             index++) {
            if (String.valueOf(error.getDmlStatusCode(index)) !=
                'STRING_TOO_LONG') {
                continue;
            }

            hasStringTooLongError = true;

            List<String> errorFieldNames =
                error.getDmlFieldNames(index);

            if (errorFieldNames != null) {
                candidateFieldNames.addAll(errorFieldNames);
            }

            if (errorFieldNames == null || errorFieldNames.isEmpty()) {
                candidateFieldNames.addAll(
                    extractDmlFieldNames(error.getDmlMessage(index))
                );
            }
        }

        if (!hasStringTooLongError || candidateFieldNames.isEmpty()) {
            return false;
        }

        Map<String, Schema.SObjectField> fields =
            recordToInsert.getSObjectType()
                .getDescribe()
                .fields
                .getMap();
        Boolean correctedAnyField = false;

        for (String fieldApiName : candidateFieldNames) {
            if (String.isBlank(fieldApiName)) {
                continue;
            }

            Schema.SObjectField fieldToken = fields.get(fieldApiName);

            if (fieldToken == null) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe =
                fieldToken.getDescribe();
            Object rejectedValue = recordToInsert.get(fieldApiName);

            if (rejectedValue == null ||
                !isOptionalOnCreate(fieldDescribe)) {
                continue;
            }

            String handledKey = 'string-too-long|' +
                buildHandledKey(fieldApiName, rejectedValue);

            if (handledFieldValues != null &&
                handledFieldValues.contains(handledKey)) {
                continue;
            }

            if (handledFieldValues != null) {
                handledFieldValues.add(handledKey);
            }

            recordToInsert.put(fieldApiName, null);
            correctedAnyField = true;

            System.debug(
                LoggingLevel.WARN,
                'AutoFill skipped oversized optional field ' +
                fieldApiName + ' and retried record creation.'
            );
        }

        return correctedAnyField;
    }

    @TestVisible
    private static Boolean isOptionalOnCreate(
        Schema.DescribeFieldResult fieldDescribe
    ) {
        return fieldDescribe != null &&
            (fieldDescribe.isNillable() ||
             fieldDescribe.isDefaultedOnCreate());
    }

    @TestVisible
    private static Set<String> extractDmlFieldNames(String message) {
        Set<String> fieldNames = new Set<String>();

        if (String.isBlank(message)) {
            return fieldNames;
        }

        Integer openingBracket = message.lastIndexOf('[');
        Integer closingBracket = message.lastIndexOf(']');

        if (openingBracket < 0 ||
            closingBracket <= openingBracket) {
            return fieldNames;
        }

        String fieldList = message.substring(
            openingBracket + 1,
            closingBracket
        );

        for (String fieldApiName : fieldList.split(',')) {
            if (!String.isBlank(fieldApiName)) {
                fieldNames.add(fieldApiName.trim());
            }
        }

        return fieldNames;
    }

    @TestVisible
    private static Boolean correctInvalidRestrictedPicklists(
        SObject recordToInsert,
        DmlException error,
        Set<String> handledFieldValues
    ) {
        if (recordToInsert == null || error == null) {
            return false;
        }

        Set<String> candidateFieldNames = new Set<String>();
        Boolean hasRestrictedPicklistError = false;

        for (Integer index = 0;
             index < error.getNumDml();
             index++) {
            if (String.valueOf(error.getDmlStatusCode(index)) !=
                'INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST') {
                continue;
            }

            hasRestrictedPicklistError = true;

            List<String> errorFieldNames =
                error.getDmlFieldNames(index);

            if (errorFieldNames != null) {
                candidateFieldNames.addAll(errorFieldNames);
            }
        }

        if (!hasRestrictedPicklistError) {
            return false;
        }

        Map<String, Schema.SObjectField> fields =
            recordToInsert.getSObjectType()
                .getDescribe()
                .fields
                .getMap();

        // Salesforce does not always populate getDmlFieldNames(). When it
        // does not, match the rejected value from the error to populated
        // restricted picklist fields on the record.
        if (candidateFieldNames.isEmpty()) {
            String rejectedValue = extractRejectedPicklistValue(
                error.getNumDml() > 0
                    ? error.getDmlMessage(0)
                    : error.getMessage()
            );

            if (!String.isBlank(rejectedValue)) {
                Map<String, Object> populatedFields =
                    recordToInsert.getPopulatedFieldsAsMap();

                for (String fieldApiName : populatedFields.keySet()) {
                    Schema.SObjectField fieldToken = fields.get(fieldApiName);

                    if (fieldToken == null) {
                        continue;
                    }

                    Schema.DescribeFieldResult fieldDescribe =
                        fieldToken.getDescribe();

                    if (!isRestrictedPicklist(fieldDescribe)) {
                        continue;
                    }

                    Object currentValue = populatedFields.get(fieldApiName);

                    if (currentValue != null &&
                        rejectedValue.equalsIgnoreCase(
                            String.valueOf(currentValue).trim()
                        )) {
                        candidateFieldNames.add(fieldApiName);
                    }
                }
            }
        }

        Boolean correctedAnyField = false;

        for (String fieldApiName : candidateFieldNames) {
            if (String.isBlank(fieldApiName)) {
                continue;
            }

            Schema.SObjectField fieldToken = fields.get(fieldApiName);

            if (fieldToken == null) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe =
                fieldToken.getDescribe();

            if (!isRestrictedPicklist(fieldDescribe)) {
                continue;
            }

            Object rejectedValue = recordToInsert.get(fieldApiName);
            String handledKey = buildHandledKey(
                fieldApiName,
                rejectedValue
            );

            if (handledFieldValues.contains(handledKey)) {
                continue;
            }

            handledFieldValues.add(handledKey);

            // AutoFill may receive "Open" for the Load status even when the
            // active/default Load record type does not permit that value.
            // The existing FTM load workflow uses "Assigned" as its safe
            // initial operational status.
            if (isLoadStatusField(recordToInsert, fieldApiName)) {
                String fallbackValue = findActivePicklistValue(
                    fieldDescribe,
                    LOAD_STATUS_FALLBACK
                );

                if (!String.isBlank(fallbackValue) &&
                    (rejectedValue == null ||
                     !fallbackValue.equalsIgnoreCase(
                         String.valueOf(rejectedValue).trim()
                     ))) {
                    recordToInsert.put(fieldApiName, fallbackValue);
                    correctedAnyField = true;

                    System.debug(
                        LoggingLevel.WARN,
                        'AutoFill replaced invalid Load status "' +
                        String.valueOf(rejectedValue) +
                        '" with "' + fallbackValue + '".'
                    );

                    continue;
                }

                // If the fallback itself is unavailable for the current
                // record type, clear the submitted value and allow Salesforce
                // defaults or package automation to provide the status.
                if (rejectedValue != null) {
                    recordToInsert.put(fieldApiName, null);
                    correctedAnyField = true;

                    System.debug(
                        LoggingLevel.WARN,
                        'AutoFill cleared invalid Load status "' +
                        String.valueOf(rejectedValue) + '".'
                    );

                    continue;
                }
            }

            // Other required picklists remain blocking. Optional picklists
            // can be removed so one invalid extracted value does not prevent
            // the parent record from being created.
            if (!fieldDescribe.isNillable() &&
                !fieldDescribe.isDefaultedOnCreate()) {
                continue;
            }

            if (rejectedValue == null) {
                continue;
            }

            recordToInsert.put(fieldApiName, null);
            correctedAnyField = true;

            System.debug(
                LoggingLevel.WARN,
                'AutoFill skipped invalid optional restricted picklist field ' +
                fieldApiName +
                ' with value "' + String.valueOf(rejectedValue) + '".'
            );
        }

        return correctedAnyField;
    }

    @TestVisible
    private static Boolean isLoadStatusField(
        SObject recordToInsert,
        String fieldApiName
    ) {
        if (recordToInsert == null || String.isBlank(fieldApiName)) {
            return false;
        }

        String objectApiName = recordToInsert.getSObjectType()
            .getDescribe()
            .getName();

        return LOAD_OBJECT_API_NAME.equalsIgnoreCase(objectApiName) &&
            LOAD_STATUS_FIELD_API_NAME.equalsIgnoreCase(fieldApiName);
    }

    @TestVisible
    private static String findActivePicklistValue(
        Schema.DescribeFieldResult fieldDescribe,
        String requestedValue
    ) {
        if (fieldDescribe == null || String.isBlank(requestedValue)) {
            return null;
        }

        for (Schema.PicklistEntry entry :
             fieldDescribe.getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }

            if (requestedValue.equalsIgnoreCase(entry.getValue()) ||
                requestedValue.equalsIgnoreCase(entry.getLabel())) {
                return entry.getValue();
            }
        }

        return null;
    }

    @TestVisible
    private static String buildHandledKey(
        String fieldApiName,
        Object fieldValue
    ) {
        return String.valueOf(fieldApiName).toLowerCase() + '|' +
            (fieldValue == null
                ? '<null>'
                : String.valueOf(fieldValue).trim().toLowerCase());
    }

    @TestVisible
    private static Boolean isRestrictedPicklist(
        Schema.DescribeFieldResult fieldDescribe
    ) {
        if (fieldDescribe == null ||
            !fieldDescribe.isRestrictedPicklist()) {
            return false;
        }

        Schema.DisplayType fieldType = fieldDescribe.getType();

        return fieldType == Schema.DisplayType.Picklist ||
            fieldType == Schema.DisplayType.MultiPicklist;
    }

    @TestVisible
    private static String extractRejectedPicklistValue(String message) {
        if (String.isBlank(message)) {
            return null;
        }

        String lowerMessage = message.toLowerCase();
        Integer markerIndex = lowerMessage.indexOf(
            RESTRICTED_PICKLIST_MARKER
        );

        if (markerIndex < 0) {
            return null;
        }

        String rejectedValue = message.substring(
            markerIndex + RESTRICTED_PICKLIST_MARKER.length()
        ).trim();

        Integer fieldListIndex = rejectedValue.lastIndexOf(': [');

        if (fieldListIndex >= 0) {
            rejectedValue = rejectedValue.substring(
                0,
                fieldListIndex
            ).trim();
        }

        return String.isBlank(rejectedValue)
            ? null
            : rejectedValue;
    }
}