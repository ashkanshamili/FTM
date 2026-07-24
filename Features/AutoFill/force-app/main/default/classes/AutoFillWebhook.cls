@RestResource(urlMapping='/freightgraph/autofill-email-extraction')
global without sharing class AutoFillWebhook {

    @HttpPost
    global static WebhookResponse handlePost() {
        RestResponse response = RestContext.response;

        if (response == null) {
            response = new RestResponse();
            RestContext.response = response;
        }

        response.addHeader(
            'Content-Type',
            'application/json; charset=UTF-8'
        );

        try {
            RestRequest request = RestContext.request;
            String body =
                request == null || request.requestBody == null
                ? null
                : request.requestBody.toString();

            System.debug(
                LoggingLevel.INFO,
                'AUTOFILL_WEBHOOK request received. Body length: ' +
                (body == null ? 0 : body.length())
            );

            if (String.isBlank(body)) {
                response.statusCode = 400;
                return buildError(
                    'EMPTY_BODY',
                    'Request body is empty.'
                );
            }

            AutoFillWebhookAuthenticator.AuthenticationResult
                authentication =
                    AutoFillWebhookAuthenticator.authenticateWebhook(
                        request,
                        body
                    );

            if (!authentication.valid) {
                System.debug(
                    LoggingLevel.WARN,
                    'AUTOFILL_WEBHOOK authentication failed. Code: ' +
                    authentication.code
                );

                response.statusCode = authentication.statusCode;
                return buildError(
                    authentication.code,
                    authentication.message
                );
            }

            Object rawPayload;

            try {
                rawPayload = JSON.deserializeUntyped(body);
            } catch (Exception jsonException) {
                response.statusCode = 400;
                return buildError(
                    'INVALID_JSON',
                    'The request body is not valid JSON.'
                );
            }

            Map<String, Object> payload;

            try {
                payload = preparePayload(rawPayload);
            } catch (AutoFillWebhookPayloadAdapter.PayloadException e) {
                System.debug(
                    LoggingLevel.WARN,
                    'AUTOFILL_WEBHOOK payload rejected: ' +
                    e.getMessage()
                );

                response.statusCode = 422;
                return buildError(
                    'INVALID_PAYLOAD',
                    e.getMessage()
                );
            }

            AutoFillService.ProcessingResult processingResult;
            Savepoint processingSavepoint = Database.setSavepoint();

            try {
                processingResult =
                    AutoFillService.createFromExtractionPayloadWithStatus(
                            payload,
                            authentication.deliveryId
                        );
            } catch (AutoFillService.RecordCreationException e) {
                Database.rollback(processingSavepoint);
                System.debug(
                    LoggingLevel.WARN,
                    'AUTOFILL_WEBHOOK record creation rejected: ' +
                    e.getMessage()
                );

                response.statusCode = 422;
                return buildError(
                    'RECORD_CREATION_FAILED',
                    e.getMessage()
                );
            }

            Id recordId = processingResult.recordId;

            if (
                processingResult.created == true &&
                recordId != null
            ) {
                try {
                    AutoFillController.saveWebhookFilesToRecord(
                        recordId,
                        rawPayload,
                        processingResult.itemId,
                        processingResult.objectType
                    );
                } catch (Exception fileSaveException) {
                    Database.rollback(processingSavepoint);

                    System.debug(
                        LoggingLevel.ERROR,
                        'AUTOFILL_WEBHOOK record and source document save failed: ' +
                        fileSaveException.getMessage()
                    );

                    response.statusCode = 500;
                    return buildError(
                        'FILE_SAVE_FAILED',
                        'The record and its source documents could not be saved.'
                    );
                }
            }

            if (
                processingResult.created == true &&
                recordId != null &&
                recordId.getSObjectType() ==
                    FreightTM__Load__c.SObjectType
            ) {
                try {
                    System.enqueueJob(
                        new AutoFillRecordEmailNotifier(recordId)
                    );
                } catch (Exception emailQueueException) {
                    System.debug(
                        LoggingLevel.WARN,
                        'AUTOFILL_WEBHOOK record created, but confirmation ' +
                        'email could not be queued: ' +
                        emailQueueException.getMessage()
                    );
                }
            }

            response.statusCode =
                processingResult.created == true ? 201 : 200;

            System.debug(
                LoggingLevel.INFO,
                'AUTOFILL_WEBHOOK completed. Record ID: ' +
                recordId +
                '. Created: ' +
                processingResult.created
            );

            return buildSuccess(
                recordId,
                processingResult.created
            );

        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'AUTOFILL_WEBHOOK processing error: ' +
                e.getTypeName() +
                ' | ' +
                e.getMessage() +
                ' | line ' +
                e.getLineNumber()
            );
            System.debug(
                LoggingLevel.ERROR,
                e.getStackTraceString()
            );

            response.statusCode = 500;
            return buildError(
                'SERVER_ERROR',
                'The webhook could not be processed.'
            );
        }
    }

    /**
     * Keeps the previously working webhook contract unchanged when the API
     * already returns ExtractedFields at the root level. Wrapped, V1
     * LoadDetails, and generic V2 responses still use the compatibility
     * adapter.
     */
    @TestVisible
    private static Map<String, Object> preparePayload(Object rawPayload) {
        if (rawPayload instanceof Map<String, Object>) {
            Map<String, Object> rootPayload =
                (Map<String, Object>) rawPayload;

            Object directExtractedFields = getDirectValueIgnoreCase(
                rootPayload,
                new Set<String>{ 'extractedfields' }
            );

            if (directExtractedFields instanceof Map<String, Object>) {
                Object directObjectApiName = getDirectValueIgnoreCase(
                    rootPayload,
                    new Set<String>{
                        'salesforceobjecttype',
                        'parentobject',
                        'parentobjectapiname'
                    }
                );

                if (isUsableObjectApiName(directObjectApiName)) {
                    Object directSource = getDirectValueIgnoreCase(
                        rootPayload,
                        new Set<String>{
                            'autofillsource',
                            'source',
                            'uploadsource'
                        }
                    );

                    if (
                        directSource == null ||
                        String.isBlank(String.valueOf(directSource))
                    ) {
                        rootPayload.put('AutoFillSource', 'Webhook');
                    }

                    System.debug(
                        LoggingLevel.INFO,
                        'AUTOFILL_WEBHOOK using the existing direct payload contract.'
                    );
                    return rootPayload;
                }

                System.debug(
                    LoggingLevel.INFO,
                    'AUTOFILL_WEBHOOK direct payload has extracted fields but no usable parent object. Normalizing payload.'
                );
            }
        }

        System.debug(
            LoggingLevel.INFO,
            'AUTOFILL_WEBHOOK normalizing a wrapped or compatibility payload.'
        );

        return AutoFillWebhookPayloadAdapter.normalize(rawPayload);
    }

    @TestVisible
    private static Boolean isUsableObjectApiName(Object value) {
        if (value == null) {
            return false;
        }

        String textValue = String.valueOf(value).trim();
        return !String.isBlank(textValue) &&
            !textValue.equalsIgnoreCase('null');
    }

    @TestVisible
    private static Object getDirectValueIgnoreCase(
        Map<String, Object> source,
        Set<String> normalizedKeys
    ) {
        if (
            source == null ||
            source.isEmpty() ||
            normalizedKeys == null ||
            normalizedKeys.isEmpty()
        ) {
            return null;
        }

        for (String key : source.keySet()) {
            if (
                key != null &&
                normalizedKeys.contains(
                    key.trim().toLowerCase()
                )
            ) {
                return source.get(key);
            }
        }

        return null;
    }

    global class WebhookResponse {
        public Boolean success;
        public String code;
        public String message;
        public Id recordId;
    }

    @TestVisible
    private static WebhookResponse buildSuccess(
        Id recordId,
        Boolean created
    ) {
        WebhookResponse result = new WebhookResponse();
        result.success = true;
        result.code = created == true
            ? 'CREATED'
            : 'ALREADY_PROCESSED';
        result.recordId = recordId;
        result.message = created == true
            ? 'Record created successfully.'
            : 'This delivery was already processed. Existing record reused.';
        return result;
    }

    @TestVisible
    private static WebhookResponse buildError(
        String code,
        String message
    ) {
        WebhookResponse result = new WebhookResponse();
        result.success = false;
        result.code = code;
        result.message = message;
        return result;
    }
}