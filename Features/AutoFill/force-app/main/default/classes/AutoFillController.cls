public without sharing class AutoFillController {

    @TestVisible
    private static Map<String, Id> lookupIdCache = new Map<String, Id>();

    private static final String BASE_URL = 'https://api-dev.freightgraph.ai';
    private static final String EMAILl_EXTRACTOR = '/api/EmailExtractor/process-email-with-files';
    private static final String DOCUMENT_DETAIL_ENDPOINT = '/api/Ai-scanning/documents/';
    private static final String LOAD_OBJECT_API_NAME = 'FreightTM__Load__c';
    private static final String AUTOFILL_STATUS_DIRECT = 'Direct';
    private static final String AUTOFILL_STATUS_DRAFT = 'Draft';
    private static final String AUTOFILL_STATUS_APPROVED = 'Approved';
    private static final String AUTOFILL_STATUS_REJECTED = 'Rejected';
    private static final String AUTOFILL_FILE_DESCRIPTION_PREFIX = 'AutoFill Upload';
    private static final Integer MAX_WEBHOOK_FILE_SEARCH_DEPTH = 7;
    private static final Integer MAX_WEBHOOK_FILES = 25;

    @TestVisible
    private static String testAccessToken;

    public class UploadFile {
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String contentType { get; set; }
        @AuraEnabled public String base64Data { get; set; }
    }

    public class ApiResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public Integer statusCode { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String responseBody { get; set; }

        @AuraEnabled public Id recordId { get; set; }
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

    public class ExtractedFieldRow {
        @AuraEnabled public String fieldName { get; set; }
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public Decimal confidence { get; set; }
    }

    public class AutoFillRejectResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public Boolean deleted { get; set; }
        @AuraEnabled public String message { get; set; }
    }

    public class DocumentScanResult {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String itemId { get; set; }
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String webhookStatus { get; set; }
        @AuraEnabled public String detectedDocumentType { get; set; }
        @AuraEnabled public Decimal confidence { get; set; }
        @AuraEnabled public Decimal classificationConfidence { get; set; }
        @AuraEnabled public String failureReason { get; set; }
        @AuraEnabled public String processedAt { get; set; }
        @AuraEnabled public List<ExtractedFieldRow> extractedFields { get; set; }
        @AuraEnabled public String rawJson { get; set; }
    }

    @AuraEnabled
    public static ApiResult sendEmailContent(String emailContent, List<UploadFile> files) {
        String submittedEmailContent = String.isBlank(emailContent)
            ? ''
            : emailContent.trim();
        List<UploadFile> safeFiles = files == null
            ? new List<UploadFile>()
            : files;

        Boolean hasEmailContent = !String.isBlank(submittedEmailContent);
        Boolean hasAttachments = hasUsableUploadFile(safeFiles);

        if (!hasEmailContent && !hasAttachments) {
            throw new AuraHandledException(
                'Add email/document notes or upload at least one attachment.'
            );
        }

        String emailContentForApi = hasEmailContent
            ? submittedEmailContent
            : 'text';

        String token;

        if (Test.isRunningTest() &&
            !String.isBlank(testAccessToken)) {
                token = testAccessToken;
            } else {
                token = FreightAuthApi.getStoredToken();

                if (String.isBlank(token)) {
                    token = FreightAuthApi.authenticate();
                }
            }
        //String token = FreightAuthApi.getStoredToken();
        //if (String.isBlank(token)) {
        //    token = FreightAuthApi.authenticate();
        //}

        String boundary = '----SalesforceBoundary' + String.valueOf(Crypto.getRandomLong()).replace('-', '');

        Blob requestBody = buildMultipartBody(boundary, new Map<String, String>{
            'Username' => UserInfo.getUserName(),
                'EmailContent' => emailContentForApi//,
                //'SenderEmail' => UserInfo.getUserEmail(),
                //'Subject' => 'Email Content',
                //'TenantId' => UserInfo.getOrganizationId()
                //'TenantId' => 'c7eb4cb3-34a9-4abb-9883-10ed40dfce73'

                }, safeFiles);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + EMAILl_EXTRACTOR);
        req.setMethod('POST');
        req.setTimeout(120000);
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
        req.setBodyAsBlob(requestBody);

        HttpResponse res = new Http().send(req);

        ApiResult result = new ApiResult();
        result.statusCode = res.getStatusCode();
        result.responseBody = res.getBody();
        result.rawResponseJson = res.getBody();
        Boolean httpSuccess =
            res.getStatusCode() >= 200 &&
            res.getStatusCode() < 300;

        result.success = httpSuccess;

        if (!httpSuccess) {
            result.success = false;
            result.message =
                'API call failed with status ' +
                res.getStatusCode() +
                '. Response: ' +
                res.getBody();

            return result;
        }

        Map<String, Object> apiResponse;

        try {
            apiResponse = (Map<String, Object>)
                JSON.deserializeUntyped(res.getBody());
        } catch (Exception e) {
            result.success = false;
            result.message =
                'The API returned invalid JSON: ' +
                e.getMessage();

            return result;
        }

        Boolean apiSuccess = parseBoolean(apiResponse.get('Success'));

        if (!apiSuccess) {
            result.success = false;
            result.message = apiResponse.containsKey('Message')
                ? String.valueOf(apiResponse.get('Message'))
                : 'The API reported that processing failed.';

            return result;
        }

        result.itemId = getFirstStringValue(
            apiResponse,
            new List<String>{ 'ItemId', 'itemId' }
        );
        result.detectedDocumentType = getFirstStringValue(
            apiResponse,
            new List<String>{
                'DetectedDocumentType',
                'detectedDocumentType',
                'DocumentType',
                'documentType'
            }
        );
        result.documentConfidence = normalizeConfidenceForPercent(
            toDecimalOrNull(
                getFirstValue(
                    apiResponse,
                    new List<String>{ 'Confidence', 'confidence', 'OverallConfidence', 'overallConfidence' }
                )
            )
        );
        result.classificationConfidence = resolveClassificationConfidence(apiResponse);

        // Preserve manually submitted text so the review popup can display it
        // when the Load has no inline-previewable PDF or image attachment.
        if (hasEmailContent) {
            apiResponse.put('AutoFillSourceText', submittedEmailContent);
        }

        Savepoint savepoint = Database.setSavepoint();

        try {
            AutoFillService.ProcessingResult created =
                AutoFillService.createFromExtractionPayloadWithStatus(
                    apiResponse,
                    null,
                    'Manual Upload'
                );

            Integer attachedFileCount = 0;

            if (created.recordId != null) {
                attachedFileCount = saveUploadedFilesToRecord(
                    created.recordId,
                    safeFiles,
                    created.itemId,
                    created.objectType
                );

                if (attachedFileCount > 0) {
                    created.fieldCount =
                        (created.fieldCount == null ? 0 : created.fieldCount) +
                        attachedFileCount;
                }
            }

            result.success = true;
            result.recordId = created.recordId;
            result.objectType = created.objectType;
            result.itemId = String.isBlank(result.itemId) ? created.itemId : result.itemId;
            result.autoFillStatus = created.autoFillStatus;
            result.detectedDocumentType = String.isBlank(result.detectedDocumentType)
                ? created.detectedDocumentType
                : result.detectedDocumentType;
            result.documentConfidence = result.documentConfidence == null
                ? created.documentConfidence
                : result.documentConfidence;
            result.classificationConfidence = result.classificationConfidence == null
                ? created.classificationConfidence
                : result.classificationConfidence;
            result.fieldCount = created.fieldCount;
            result.allFieldsDetected = created.allFieldsDetected;
            result.autoFillSource = created.autoFillSource;
            result.message =
                'AutoFill processed the submission and created ' +
                created.objectType +
                (attachedFileCount > 0
                    ? ' with ' + String.valueOf(attachedFileCount) +
                        (attachedFileCount == 1 ? ' attached file.' : ' attached files.')
                    : ' successfully.');

            return result;
        } catch (Exception e) {
            Database.rollback(savepoint);

            result.success = false;
            result.message =
                'The API processed the submission, but Salesforce could not ' +
                'create the record: ' +
                e.getMessage();

            return result;
        }
    }

    @AuraEnabled
    public static DocumentScanResult getExtractedDocument(String itemId) {
        if (String.isBlank(itemId)) {
            throw new AuraHandledException('Item Id is required.');
        }

        String token = Test.isRunningTest() && !String.isBlank(testAccessToken)
            ? testAccessToken
            : FreightAuthApi.getStoredToken();

        if (String.isBlank(token)) {
            token = FreightAuthApi.authenticate();
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            BASE_URL +
            DOCUMENT_DETAIL_ENDPOINT +
            EncodingUtil.urlEncode(itemId, 'UTF-8')
        );
        req.setMethod('GET');
        req.setTimeout(120000);
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Accept', 'application/json');

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() == 404) {
            throw new AuraHandledException('Extracted document was not found.');
        }

        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new AuraHandledException(
                'Could not load extracted document. Status: ' +
                res.getStatusCode() +
                '. Response: ' +
                res.getBody()
            );
        }

        try {
            Map<String, Object> body = (Map<String, Object>)
                JSON.deserializeUntyped(res.getBody());

            return buildDocumentScanResult(body, res.getBody());
        } catch (Exception e) {
            throw new AuraHandledException(
                'The extracted document response was invalid: ' +
                e.getMessage()
            );
        }
    }

    @AuraEnabled
    public static void approveAutoFillLoad(Id loadId) {
        SObject loadRecord = getAutoFillLoadForUpdate(loadId);

        String currentStatus = String.valueOf(loadRecord.get('AutoFill_Status__c'));

        if (currentStatus == AUTOFILL_STATUS_APPROVED) {
            return;
        }

        if (currentStatus == AUTOFILL_STATUS_REJECTED) {
            throw new AuraHandledException(
                'Rejected AutoFill loads cannot be approved.'
            );
        }


        loadRecord.put('AutoFill_Status__c', AUTOFILL_STATUS_APPROVED);
        safePutByDescribe(loadRecord, 'AutoFill_Approved_By__c', UserInfo.getUserId());
        safePutByDescribe(loadRecord, 'AutoFill_Approved_At__c', System.now());

        update loadRecord;
    }

    @AuraEnabled
    public static AutoFillRejectResult rejectAutoFillLoad(Id loadId, String rejectionReason) {
        AutoFillRejectResult result = new AutoFillRejectResult();
        result.success = false;
        result.deleted = false;

        Savepoint savepoint = Database.setSavepoint();

        try {
            SObject loadRecord = getAutoFillLoadForUpdate(loadId);
            String currentStatus = String.valueOf(loadRecord.get('AutoFill_Status__c'));

            if (currentStatus == AUTOFILL_STATUS_APPROVED) {
                throw new AuraHandledException(
                    'Approved AutoFill loads cannot be rejected.'
                );
            }

            // Save the rejection details before moving the draft to the recycle bin.
            loadRecord.put('AutoFill_Status__c', AUTOFILL_STATUS_REJECTED);
            safePutByDescribe(loadRecord, 'AutoFill_Rejected_By__c', UserInfo.getUserId());
            safePutByDescribe(loadRecord, 'AutoFill_Rejected_At__c', System.now());
            safePutByDescribe(loadRecord, 'AutoFill_Rejection_Reason__c', rejectionReason);
            update loadRecord;

            Integer deletedFileCount = deleteAutoFillFilesForLoad(loadId);

            List<Database.DeleteResult> loadDeleteResults = Database.delete(
                new List<SObject>{ loadRecord },
                false
            );

            if (loadDeleteResults.isEmpty() || !loadDeleteResults[0].isSuccess()) {
                throw new AutoFillFileException(
                    'The Load could not be deleted. ' +
                    buildDatabaseErrorMessage(loadDeleteResults)
                );
            }

            result.success = true;
            result.deleted = true;
            result.message =
                'Draft load and ' + String.valueOf(deletedFileCount) +
                (deletedFileCount == 1 ? ' attached file were' : ' attached files were') +
                ' deleted successfully.';
            return result;
        } catch (AuraHandledException e) {
            Database.rollback(savepoint);
            throw e;
        } catch (Exception e) {
            Database.rollback(savepoint);
            throw new AuraHandledException(
                'Could not reject and delete the AutoFill draft: ' + e.getMessage()
            );
        }
    }

    @TestVisible
    private static String buildDatabaseErrorMessage(List<Database.DeleteResult> deleteResults) {
        if (deleteResults == null || deleteResults.isEmpty()) {
            return 'No delete result was returned.';
        }

        List<String> messages = new List<String>();

        for (Database.Error error : deleteResults[0].getErrors()) {
            messages.add(String.valueOf(error.getStatusCode()) + ': ' + error.getMessage());
        }

        return messages.isEmpty()
            ? 'Salesforce did not return a delete error message.'
            : String.join(messages, ' | ');
    }






    @TestVisible
    private static Boolean parseBoolean(Object rawValue) {
        if (rawValue == null) {
            return false;
        }

        String value =
            String.valueOf(rawValue).trim().toLowerCase();

        return value == 'true' ||
            value == 'yes' ||
            value == 'y' ||
            value == '1';
    }

    @TestVisible
    private static Boolean isEmpty(Object value) {
        return value == null ||
            (value instanceof String &&
             String.isBlank((String) value));
    }

    @TestVisible
    private static String normalize(String value) {
        if (String.isBlank(value)) {
            return '';
        }

        return value.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    @TestVisible
    private static Boolean hasUsableUploadFile(List<UploadFile> files) {
        if (files == null || files.isEmpty()) {
            return false;
        }

        for (UploadFile file : files) {
            if (file != null && !String.isBlank(file.base64Data)) {
                return true;
            }
        }

        return false;
    }

    @TestVisible
    private static Blob buildMultipartBody(
        String boundary,
        Map<String, String> fields,
        List<UploadFile> files
    ) {
        String hexBody = '';

        for (String fieldName : fields.keySet()) {
            hexBody += EncodingUtil.convertToHex(
                Blob.valueOf(
                    '--' + boundary + '\r\n' +
                    'Content-Disposition: form-data; name="' +
                    fieldName +
                    '"\r\n\r\n' +
                    fields.get(fieldName) +
                    '\r\n'
                )
            );
        }

        if (files == null) {
            files = new List<UploadFile>();
        }

        for (UploadFile file : files) {
            if (file == null || String.isBlank(file.base64Data)) {
                continue;
            }

            Blob fileBody =
                EncodingUtil.base64Decode(file.base64Data);

            String contentType =
                String.isBlank(file.contentType)
                ? 'application/octet-stream'
                : file.contentType;

            String safeFileName = String.isBlank(file.fileName)
                ? 'attachment'
                : file.fileName
                .replace('\r', '')
                .replace('\n', '')
                .replace('"', '');

            hexBody += EncodingUtil.convertToHex(
                Blob.valueOf(
                    '--' + boundary + '\r\n' +
                    'Content-Disposition: form-data; ' +
                    'name="Attachments"; filename="' +
                    safeFileName +
                    '"\r\n' +
                    'Content-Type: ' +
                    contentType +
                    '\r\n\r\n'
                )
            );

            hexBody += EncodingUtil.convertToHex(fileBody);
            hexBody += EncodingUtil.convertToHex(
                Blob.valueOf('\r\n')
            );
        }

        hexBody += EncodingUtil.convertToHex(
            Blob.valueOf('--' + boundary + '--\r\n')
        );

        return EncodingUtil.convertFromHex(hexBody);
    }


    /**
     * Saves uploaded files on any newly created Salesforce parent record.
     * Load-specific AutoFill audit fields are updated only when the parent is
     * actually FreightTM__Load__c.
     */
    @TestVisible
    private static Integer saveUploadedFilesToRecord(
        Id parentRecordId,
        List<UploadFile> files,
        String itemId,
        String parentObjectApiName
    ) {
        if (parentRecordId == null || files == null || files.isEmpty()) {
            return 0;
        }

        List<ContentVersion> versionsToInsert = new List<ContentVersion>();
        List<String> originalFileNames = new List<String>();

        for (UploadFile upload : files) {
            if (upload == null || String.isBlank(upload.base64Data)) {
                continue;
            }

            String safeFileName = sanitizeFileName(upload.fileName);

            if (String.isBlank(safeFileName)) {
                safeFileName = 'AutoFill-upload.bin';
            }

            Blob fileBody;

            try {
                fileBody = EncodingUtil.base64Decode(upload.base64Data);
            } catch (Exception decodeError) {
                throw new AutoFillFileException(
                    'Could not decode uploaded file "' + safeFileName + '": ' +
                    decodeError.getMessage()
                );
            }

            if (fileBody == null || fileBody.size() == 0) {
                continue;
            }

            ContentVersion version = new ContentVersion();
            version.Title = removeFileExtension(safeFileName);
            version.PathOnClient = safeFileName;
            version.VersionData = fileBody;
            version.FirstPublishLocationId = parentRecordId;
            version.Description = buildAutoFillFileDescription(itemId);

            versionsToInsert.add(version);
            originalFileNames.add(safeFileName);
        }

        if (versionsToInsert.isEmpty()) {
            return 0;
        }

        Database.SaveResult[] insertResults = Database.insert(versionsToInsert, false);
        List<String> fileErrors = new List<String>();
        Set<Id> insertedVersionIds = new Set<Id>();

        for (Integer index = 0; index < insertResults.size(); index++) {
            Database.SaveResult saveResult = insertResults[index];

            if (saveResult.isSuccess()) {
                insertedVersionIds.add(saveResult.getId());
                continue;
            }

            List<String> errors = new List<String>();
            for (Database.Error error : saveResult.getErrors()) {
                errors.add(error.getMessage());
            }

            fileErrors.add(
                originalFileNames[index] + ': ' + String.join(errors, ' | ')
            );
        }

        if (!fileErrors.isEmpty()) {
            throw new AutoFillFileException(
                'Salesforce could not save one or more uploaded files. ' +
                String.join(fileErrors, ' || ')
            );
        }

        List<ContentVersion> insertedVersions = [
            SELECT Id, ContentDocumentId, Title, PathOnClient
            FROM ContentVersion
            WHERE Id IN :insertedVersionIds
            ORDER BY CreatedDate ASC
        ];

        if (parentObjectApiName == LOAD_OBJECT_API_NAME) {
            appendAttachedFilesToDetectedAudit(
                parentRecordId,
                insertedVersions
            );
        }

        return insertedVersions.size();
    }

    @TestVisible
    private static Integer saveUploadedFilesToLoad(
        Id loadId,
        List<UploadFile> files,
        String itemId
    ) {
        return saveUploadedFilesToRecord(
            loadId,
            files,
            itemId,
            LOAD_OBJECT_API_NAME
        );
    }

    /**
     * Extracts original email documents returned in a webhook payload and
     * publishes them as Salesforce Files on the newly created record. The
     * existing AutoFill preview popup automatically discovers these files by
     * their Description prefix.
     *
     * Supported collection names include Documents, Attachments, Files,
     * SourceDocuments, UploadedFiles, and EmailAttachments. Each file may use
     * common property names such as fileName/name/title, contentType/mimeType,
     * and base64Data/base64/fileContent/content/data/body.
     */
    public static Integer saveWebhookFilesToRecord(
        Id parentRecordId,
        Object rawPayload,
        String itemId,
        String parentObjectApiName
    ) {
        if (parentRecordId == null || rawPayload == null) {
            return 0;
        }

        List<UploadFile> webhookFiles = extractWebhookUploadFiles(rawPayload);

        if (webhookFiles.isEmpty()) {
            return 0;
        }

        String resolvedObjectApiName = String.isBlank(parentObjectApiName)
            ? parentRecordId.getSObjectType().getDescribe().getName()
            : parentObjectApiName;

        return saveUploadedFilesToRecord(
            parentRecordId,
            webhookFiles,
            itemId,
            resolvedObjectApiName
        );
    }

    @TestVisible
    private static List<UploadFile> extractWebhookUploadFiles(
        Object rawPayload
    ) {
        List<UploadFile> result = new List<UploadFile>();
        Set<String> seenFileKeys = new Set<String>();

        collectWebhookUploadFiles(
            rawPayload,
            result,
            seenFileKeys,
            0,
            false
        );

        return result;
    }

    @TestVisible
    private static void collectWebhookUploadFiles(
        Object node,
        List<UploadFile> result,
        Set<String> seenFileKeys,
        Integer depth,
        Boolean insideFileCollection
    ) {
        if (
            node == null ||
            result == null ||
            result.size() >= MAX_WEBHOOK_FILES ||
            depth > MAX_WEBHOOK_FILE_SEARCH_DEPTH
        ) {
            return;
        }

        if (node instanceof List<Object>) {
            for (Object item : (List<Object>) node) {
                collectWebhookUploadFiles(
                    item,
                    result,
                    seenFileKeys,
                    depth + 1,
                    insideFileCollection
                );

                if (result.size() >= MAX_WEBHOOK_FILES) {
                    return;
                }
            }
            return;
        }

        if (!(node instanceof Map<String, Object>)) {
            return;
        }

        Map<String, Object> nodeMap = (Map<String, Object>) node;
        UploadFile parsedFile = buildWebhookUploadFile(
            nodeMap,
            insideFileCollection,
            result.size() + 1
        );

        if (parsedFile != null) {
            String dedupKey = buildWebhookFileDedupKey(parsedFile);

            if (!seenFileKeys.contains(dedupKey)) {
                seenFileKeys.add(dedupKey);
                result.add(parsedFile);
            }

            return;
        }

        if (insideFileCollection) {
            collectWebhookFilesFromNamedEntries(
                nodeMap,
                result,
                seenFileKeys
            );
        }

        for (String key : nodeMap.keySet()) {
            Object child = nodeMap.get(key);
            Boolean childIsFileCollection =
                insideFileCollection || isWebhookFileCollectionKey(key);

            if (child instanceof Map<String, Object> ||
                child instanceof List<Object>) {
                collectWebhookUploadFiles(
                    child,
                    result,
                    seenFileKeys,
                    depth + 1,
                    childIsFileCollection
                );
            } else if (child instanceof String &&
                (isWebhookJsonWrapperKey(key) ||
                    isWebhookFileCollectionKey(key))) {
                Object decodedChild = tryDeserializeWebhookJson(
                    String.valueOf(child)
                );

                if (decodedChild != null) {
                    collectWebhookUploadFiles(
                        decodedChild,
                        result,
                        seenFileKeys,
                        depth + 1,
                        childIsFileCollection
                    );
                }
            }

            if (result.size() >= MAX_WEBHOOK_FILES) {
                return;
            }
        }
    }

    @TestVisible
    private static void collectWebhookFilesFromNamedEntries(
        Map<String, Object> source,
        List<UploadFile> result,
        Set<String> seenFileKeys
    ) {
        if (source == null || result == null || seenFileKeys == null) {
            return;
        }

        for (String key : source.keySet()) {
            if (result.size() >= MAX_WEBHOOK_FILES ||
                !looksLikeWebhookFileName(key)) {
                continue;
            }

            Object rawValue = source.get(key);

            if (!(rawValue instanceof String)) {
                continue;
            }

            String normalizedBase64 = normalizeWebhookBase64(
                String.valueOf(rawValue)
            );

            if (!isValidWebhookBase64(normalizedBase64)) {
                continue;
            }

            UploadFile file = new UploadFile();
            file.fileName = sanitizeFileName(key);
            file.contentType = 'application/octet-stream';
            file.base64Data = normalizedBase64;

            String dedupKey = buildWebhookFileDedupKey(file);

            if (!seenFileKeys.contains(dedupKey)) {
                seenFileKeys.add(dedupKey);
                result.add(file);
            }
        }
    }

    @TestVisible
    private static Boolean looksLikeWebhookFileName(String value) {
        if (String.isBlank(value)) {
            return false;
        }

        String normalizedValue = value.trim().toLowerCase();
        Integer lastDot = normalizedValue.lastIndexOf('.');

        return lastDot > 0 && lastDot < normalizedValue.length() - 1;
    }

    @TestVisible
    private static Boolean isWebhookJsonWrapperKey(String key) {
        String normalizedKey = normalize(key);

        Set<String> wrapperKeys = new Set<String>{
            'payload',
            'response',
            'result',
            'body',
            'webhook',
            'extraction',
            'extractionresult'
        };

        return wrapperKeys.contains(normalizedKey);
    }

    @TestVisible
    private static Object tryDeserializeWebhookJson(String rawJson) {
        if (String.isBlank(rawJson)) {
            return null;
        }

        String trimmedValue = rawJson.trim();

        if (!trimmedValue.startsWith('{') &&
            !trimmedValue.startsWith('[')) {
            return null;
        }

        try {
            return JSON.deserializeUntyped(trimmedValue);
        } catch (Exception ignoredInvalidNestedJson) {
            return null;
        }
    }

    @TestVisible
    private static UploadFile buildWebhookUploadFile(
        Map<String, Object> fileMap,
        Boolean insideFileCollection,
        Integer sequenceNumber
    ) {
        if (fileMap == null || fileMap.isEmpty()) {
            return null;
        }

        String fileName = getDirectWebhookString(
            fileMap,
            new Set<String>{
                'filename',
                'name',
                'title',
                'originalfilename',
                'attachmentname',
                'documentname'
            }
        );
        String contentType = getDirectWebhookString(
            fileMap,
            new Set<String>{
                'contenttype',
                'mimetype',
                'mediatype',
                'filetype'
            }
        );

        if (!insideFileCollection &&
            !hasExplicitWebhookFileDataKey(fileMap)) {
            return null;
        }

        String rawBase64 = getWebhookBase64Value(fileMap);
        String normalizedBase64 = normalizeWebhookBase64(rawBase64);

        if (String.isBlank(normalizedBase64)) {
            return null;
        }

        // A filename is required outside an explicitly named file collection
        // so ordinary extracted fields such as "Content" are not mistaken for
        // documents.
        if (String.isBlank(fileName) && !insideFileCollection) {
            return null;
        }

        if (!isValidWebhookBase64(normalizedBase64)) {
            return null;
        }

        UploadFile file = new UploadFile();
        file.contentType = String.isBlank(contentType)
            ? 'application/octet-stream'
            : contentType.trim();
        file.fileName = String.isBlank(fileName)
            ? buildDefaultWebhookFileName(
                file.contentType,
                sequenceNumber
            )
            : sanitizeFileName(fileName);
        file.base64Data = normalizedBase64;
        return file;
    }

    @TestVisible
    private static Boolean hasExplicitWebhookFileDataKey(
        Map<String, Object> fileMap
    ) {
        if (fileMap == null) {
            return false;
        }

        Set<String> explicitFileDataKeys = new Set<String>{
            'base64data',
            'base64',
            'base64content',
            'filebase64',
            'filebytesbase64',
            'filecontent',
            'filecontentbase64',
            'contentbase64',
            'contentbase64string',
            'documentcontent',
            'documentbytes',
            'contentbytes',
            'filedata',
            'bytes'
        };

        for (String key : fileMap.keySet()) {
            if (explicitFileDataKeys.contains(normalize(key))) {
                return true;
            }
        }

        return false;
    }

    @TestVisible
    private static String getWebhookBase64Value(
        Map<String, Object> fileMap
    ) {
        Set<String> base64Keys = new Set<String>{
            'base64data',
            'base64',
            'base64content',
            'filebase64',
            'filebytesbase64',
            'filecontent',
            'filecontentbase64',
            'contentbase64',
            'contentbase64string',
            'documentcontent',
            'documentbytes',
            'contentbytes',
            'filedata',
            'bytes',
            'data',
            'body',
            'content'
        };

        for (String key : fileMap.keySet()) {
            if (!base64Keys.contains(normalize(key))) {
                continue;
            }

            Object value = fileMap.get(key);

            if (value instanceof String) {
                return String.valueOf(value);
            }

            if (value instanceof Map<String, Object>) {
                String nestedValue = getDirectWebhookString(
                    (Map<String, Object>) value,
                    base64Keys
                );

                if (!String.isBlank(nestedValue)) {
                    return nestedValue;
                }
            }
        }

        return null;
    }

    @TestVisible
    private static String getDirectWebhookString(
        Map<String, Object> source,
        Set<String> normalizedKeys
    ) {
        if (source == null || normalizedKeys == null) {
            return null;
        }

        for (String key : source.keySet()) {
            if (!normalizedKeys.contains(normalize(key))) {
                continue;
            }

            Object value = source.get(key);

            if (value == null ||
                value instanceof Map<String, Object> ||
                value instanceof List<Object>) {
                continue;
            }

            String stringValue = String.valueOf(value).trim();
            return stringValue == 'null' ? null : stringValue;
        }

        return null;
    }

    @TestVisible
    private static Boolean isWebhookFileCollectionKey(String key) {
        String normalizedKey = normalize(key);

        Set<String> fileCollectionKeys = new Set<String>{
            'doc',
            'docs',
            'document',
            'documents',
            'emaildocuments',
            'originaldocuments',
            'documentfile',
            'documentfiles',
            'sourcedocument',
            'sourcedocuments',
            'attachment',
            'attachments',
            'emailattachment',
            'emailattachments',
            'sourceattachment',
            'sourceattachments',
            'files',
            'uploadedfiles',
            'sourcefiles',
            'originalfiles'
        };

        return fileCollectionKeys.contains(normalizedKey);
    }

    @TestVisible
    private static String normalizeWebhookBase64(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }

        String normalizedValue = rawValue.trim();
        String lowerValue = normalizedValue.toLowerCase();
        Integer dataMarker = lowerValue.indexOf(';base64,');

        if (dataMarker >= 0) {
            normalizedValue = normalizedValue.substring(dataMarker + 8);
        }

        normalizedValue = normalizedValue
            .replaceAll('\\s+', '')
            .replace('-', '+')
            .replace('_', '/');
        Integer remainder = Math.mod(normalizedValue.length(), 4);

        if (remainder == 2) {
            normalizedValue += '==';
        } else if (remainder == 3) {
            normalizedValue += '=';
        } else if (remainder == 1) {
            return null;
        }

        return normalizedValue;
    }

    @TestVisible
    private static Boolean isValidWebhookBase64(String value) {
        return !String.isBlank(value) &&
            value.length() >= 8 &&
            Math.mod(value.length(), 4) == 0 &&
            Pattern.matches('^[A-Za-z0-9+/]*={0,2}$', value);
    }

    @TestVisible
    private static String buildDefaultWebhookFileName(
        String contentType,
        Integer sequenceNumber
    ) {
        String normalizedContentType = String.isBlank(contentType)
            ? ''
            : contentType.toLowerCase();
        String extension = '.bin';

        if (normalizedContentType.contains('pdf')) {
            extension = '.pdf';
        } else if (normalizedContentType.contains('png')) {
            extension = '.png';
        } else if (normalizedContentType.contains('jpeg') ||
            normalizedContentType.contains('jpg')) {
            extension = '.jpg';
        } else if (normalizedContentType.contains('gif')) {
            extension = '.gif';
        } else if (normalizedContentType.contains('tiff')) {
            extension = '.tif';
        } else if (normalizedContentType.contains('wordprocessingml')) {
            extension = '.docx';
        } else if (normalizedContentType.contains('msword')) {
            extension = '.doc';
        }

        return 'AutoFill-email-document-' +
            String.valueOf(sequenceNumber == null ? 1 : sequenceNumber) +
            extension;
    }

    @TestVisible
    private static String buildWebhookFileDedupKey(UploadFile file) {
        String data = file == null || file.base64Data == null
            ? ''
            : file.base64Data;
        String sample = data.length() <= 128
            ? data
            : data.substring(0, 64) +
                data.substring(data.length() - 64);

        return normalize(file == null ? '' : file.fileName) +
            '|' + String.valueOf(data.length()) +
            '|' + sample;
    }

    @TestVisible
    private static void appendAttachedFilesToDetectedAudit(
        Id loadId,
        List<ContentVersion> insertedVersions
    ) {
        if (loadId == null || insertedVersions == null || insertedVersions.isEmpty()) {
            return;
        }

        Schema.SObjectType loadType = Schema.getGlobalDescribe().get(LOAD_OBJECT_API_NAME);

        if (loadType == null) {
            return;
        }

        Map<String, Schema.SObjectField> loadFields =
            loadType.getDescribe().fields.getMap();

        if (!loadFields.containsKey('AutoFill_Detected_Fields__c')) {
            return;
        }

        List<String> selectedFields = new List<String>{
            'Id',
            'AutoFill_Detected_Fields__c'
        };

        if (loadFields.containsKey('AutoFill_Field_Count__c')) {
            selectedFields.add('AutoFill_Field_Count__c');
        }

        List<SObject> loads = Database.query(
            'SELECT ' + String.join(selectedFields, ',') +
            ' FROM ' + LOAD_OBJECT_API_NAME +
            ' WHERE Id = :loadId LIMIT 1 FOR UPDATE'
        );

        if (loads.isEmpty()) {
            throw new AutoFillFileException(
                'The Load was not found while saving the uploaded files.'
            );
        }

        SObject loadRecord = loads[0];
        Map<String, Object> audit = parseDetectedFieldsAudit(
            String.valueOf(loadRecord.get('AutoFill_Detected_Fields__c'))
        );

        List<Object> savedToLoad = getOrCreateAuditList(audit, 'savedToLoad');
        List<Object> detectedNotSavedToLoad =
            getOrCreateAuditList(audit, 'detectedNotSavedToLoad');
        List<Object> rawDetectedFields =
            getOrCreateAuditList(audit, 'rawDetectedFields');

        Set<String> existingDocumentIds = new Set<String>();

        for (Object existingRowObject : savedToLoad) {
            if (!(existingRowObject instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> existingRow =
                (Map<String, Object>) existingRowObject;
            String existingDocumentId = String.valueOf(
                existingRow.get('contentDocumentId')
            );

            if (!String.isBlank(existingDocumentId) && existingDocumentId != 'null') {
                existingDocumentIds.add(existingDocumentId);
            }
        }

        Integer fileNumber = 0;

        for (ContentVersion version : insertedVersions) {
            if (version.ContentDocumentId == null ||
                existingDocumentIds.contains(String.valueOf(version.ContentDocumentId))) {
                continue;
            }

            fileNumber++;
            String displayFileName = String.isBlank(version.PathOnClient)
                ? version.Title
                : version.PathOnClient;

            savedToLoad.add(new Map<String, Object>{
                'fieldName' => insertedVersions.size() == 1
                    ? 'Uploaded File'
                    : 'Uploaded File ' + String.valueOf(fileNumber),
                'loadFieldApiName' => 'Files',
                'loadFieldLabel' => 'Files',
                'value' => displayFileName,
                'confidence' => 100,
                'savedToLoad' => true,
                'reason' => 'Attached to Load',
                'contentVersionId' => String.valueOf(version.Id),
                'contentDocumentId' => String.valueOf(version.ContentDocumentId)
            });
        }

        audit.put('savedToLoad', savedToLoad);
        audit.put('detectedNotSavedToLoad', detectedNotSavedToLoad);
        audit.put('rawDetectedFields', rawDetectedFields);
        audit.put('summary', new Map<String, Object>{
            'savedToLoadCount' => savedToLoad.size(),
            'detectedNotSavedToLoadCount' => detectedNotSavedToLoad.size(),
            'rawDetectedFieldCount' => rawDetectedFields.size(),
            'attachedFileCount' => insertedVersions.size()
        });

        loadRecord.put(
            'AutoFill_Detected_Fields__c',
            serializeDetectedFields(audit)
        );

        if (loadFields.containsKey('AutoFill_Field_Count__c')) {
            loadRecord.put('AutoFill_Field_Count__c', savedToLoad.size());
        }

        update loadRecord;
    }

    @TestVisible
    private static Map<String, Object> parseDetectedFieldsAudit(String auditJson) {
        if (String.isBlank(auditJson) || auditJson == 'null') {
            return new Map<String, Object>();
        }

        try {
            Object parsed = JSON.deserializeUntyped(auditJson);
            return parsed instanceof Map<String, Object>
                ? (Map<String, Object>) parsed
                : new Map<String, Object>();
        } catch (Exception ignoredInvalidAudit) {
            return new Map<String, Object>();
        }
    }

    @TestVisible
    private static List<Object> getOrCreateAuditList(
        Map<String, Object> audit,
        String sectionName
    ) {
        if (audit != null && audit.get(sectionName) instanceof List<Object>) {
            return (List<Object>) audit.get(sectionName);
        }

        return new List<Object>();
    }

    @TestVisible
    private static Integer deleteAutoFillFilesForLoad(Id loadId) {
        if (loadId == null) {
            return 0;
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :loadId
        ];

        if (links.isEmpty()) {
            return 0;
        }

        Set<Id> linkedDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            linkedDocumentIds.add(link.ContentDocumentId);
        }

        Set<Id> autoFillDocumentIds =
            getAutoFillDocumentIdsFromAudit(loadId, linkedDocumentIds);

        for (ContentVersion version : [
            SELECT ContentDocumentId, Description
            FROM ContentVersion
            WHERE IsLatest = true
            AND ContentDocumentId IN :linkedDocumentIds
        ]) {
            if (!String.isBlank(version.Description) &&
                version.Description.startsWith(AUTOFILL_FILE_DESCRIPTION_PREFIX)) {
                autoFillDocumentIds.add(version.ContentDocumentId);
            }
        }

        if (autoFillDocumentIds.isEmpty()) {
            return 0;
        }

        List<ContentDocument> documents = [
            SELECT Id
            FROM ContentDocument
            WHERE Id IN :autoFillDocumentIds
        ];

        List<Database.DeleteResult> deleteResults = Database.delete(documents, false);
        List<String> errors = new List<String>();
        Integer deletedCount = 0;

        for (Database.DeleteResult deleteResult : deleteResults) {
            if (deleteResult.isSuccess()) {
                deletedCount++;
                continue;
            }

            for (Database.Error error : deleteResult.getErrors()) {
                errors.add(error.getMessage());
            }
        }

        if (!errors.isEmpty()) {
            throw new AutoFillFileException(
                'One or more AutoFill files could not be deleted. ' +
                String.join(errors, ' | ')
            );
        }

        return deletedCount;
    }

    @TestVisible
    private static Set<Id> getAutoFillDocumentIdsFromAudit(
        Id loadId,
        Set<Id> linkedDocumentIds
    ) {
        Set<Id> result = new Set<Id>();
        Schema.SObjectType loadType = Schema.getGlobalDescribe().get(LOAD_OBJECT_API_NAME);

        if (loadType == null || linkedDocumentIds == null || linkedDocumentIds.isEmpty()) {
            return result;
        }

        Map<String, Schema.SObjectField> loadFields =
            loadType.getDescribe().fields.getMap();

        if (!loadFields.containsKey('AutoFill_Detected_Fields__c')) {
            return result;
        }

        List<SObject> loads = Database.query(
            'SELECT AutoFill_Detected_Fields__c FROM ' +
            LOAD_OBJECT_API_NAME +
            ' WHERE Id = :loadId LIMIT 1'
        );

        if (loads.isEmpty()) {
            return result;
        }

        Map<String, Object> audit = parseDetectedFieldsAudit(
            String.valueOf(loads[0].get('AutoFill_Detected_Fields__c'))
        );
        List<Object> savedRows = getOrCreateAuditList(audit, 'savedToLoad');

        for (Object rowObject : savedRows) {
            if (!(rowObject instanceof Map<String, Object>)) {
                continue;
            }

            String rawDocumentId = String.valueOf(
                ((Map<String, Object>) rowObject).get('contentDocumentId')
            );

            if (String.isBlank(rawDocumentId) || rawDocumentId == 'null') {
                continue;
            }

            try {
                Id documentId = (Id) rawDocumentId;
                if (linkedDocumentIds.contains(documentId)) {
                    result.add(documentId);
                }
            } catch (Exception ignoredInvalidDocumentId) {
                // Ignore malformed audit rows. The file description fallback
                // below can still identify files created by AutoFill.
            }
        }

        return result;
    }

    @TestVisible
    private static String buildAutoFillFileDescription(String itemId) {
        return AUTOFILL_FILE_DESCRIPTION_PREFIX +
            (String.isBlank(itemId) ? '' : ' | ItemId: ' + itemId);
    }

    @TestVisible
    private static String sanitizeFileName(String fileName) {
        if (String.isBlank(fileName)) {
            return '';
        }

        String sanitized = fileName
            .replace('\\', '_')
            .replace('/', '_')
            .replace('\r', '')
            .replace('\n', '')
            .trim();

        return sanitized.length() > 255
            ? sanitized.substring(sanitized.length() - 255)
            : sanitized;
    }

    @TestVisible
    private static String removeFileExtension(String fileName) {
        if (String.isBlank(fileName)) {
            return 'AutoFill upload';
        }

        Integer lastDot = fileName.lastIndexOf('.');
        String title = lastDot > 0
            ? fileName.substring(0, lastDot)
            : fileName;

        return String.isBlank(title) ? 'AutoFill upload' : title;
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
                        'classificationConfidence'
                    }
                )
            )
        );
    }







    @TestVisible
    private static Decimal normalizeConfidenceForPercent(Decimal confidence) {
        if (confidence == null) {
            return null;
        }

        return confidence <= 1 ? confidence * 100 : confidence;
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
    private static void safePutByDescribe(
        SObject recordToUpdate,
        String fieldApiName,
        Object value
    ) {
        Map<String, Schema.SObjectField> fields = recordToUpdate
            .getSObjectType()
            .getDescribe()
            .fields
            .getMap();

        if (!fields.containsKey(fieldApiName) || value == null) {
            return;
        }

        Schema.DescribeFieldResult describe = fields.get(fieldApiName).getDescribe();

        if (!describe.isUpdateable() || describe.isCalculated() || describe.isAutoNumber()) {
            return;
        }

        Object valueToStore = value;

        // Some existing FTM orgs already have these audit fields as Text
        // instead of Lookup(User). Keep the current field type and store the
        // running User Id as text rather than attempting a metadata conversion.
        if (
            (
                fieldApiName == 'AutoFill_Approved_By__c' ||
                fieldApiName == 'AutoFill_Rejected_By__c'
            ) &&
            describe.getType() != Schema.DisplayType.Reference
        ) {
            valueToStore = String.valueOf(value);
        }

        recordToUpdate.put(fieldApiName, valueToStore);
    }


    @TestVisible
    private static SObject getAutoFillLoadForUpdate(Id loadId) {
        if (loadId == null) {
            throw new AuraHandledException('Load Id is required.');
        }

        Schema.SObjectType loadType = Schema.getGlobalDescribe().get(LOAD_OBJECT_API_NAME);

        if (loadType == null) {
            throw new AuraHandledException('Load object was not found.');
        }

        Map<String, Schema.SObjectField> fields = loadType.getDescribe().fields.getMap();
        List<String> selectedFields = new List<String>{ 'Id' };

        if (fields.containsKey('AutoFill_Status__c')) {
            selectedFields.add('AutoFill_Status__c');
        }

        if (!fields.containsKey('AutoFill_Status__c')) {
            throw new AuraHandledException(
                'AutoFill_Status__c is not installed on Load.'
            );
        }

        String soql =
            'SELECT ' +
            String.join(selectedFields, ',') +
            ' FROM ' +
            LOAD_OBJECT_API_NAME +
            ' WHERE Id = :loadId LIMIT 1 FOR UPDATE';

        List<SObject> records = Database.query(soql);

        if (records.isEmpty()) {
            throw new AuraHandledException('Load was not found.');
        }

        return records[0];
    }

    @TestVisible
    private static DocumentScanResult buildDocumentScanResult(
        Map<String, Object> body,
        String rawJson
    ) {
        DocumentScanResult result = new DocumentScanResult();

        result.id = getFirstStringValue(body, new List<String>{ 'Id', 'id' });
        result.itemId = getFirstStringValue(body, new List<String>{ 'ItemId', 'itemId' });
        result.fileName = getFirstStringValue(body, new List<String>{ 'FileName', 'fileName' });
        result.status = getFirstStringValue(body, new List<String>{ 'Status', 'status' });
        result.webhookStatus = getFirstStringValue(body, new List<String>{ 'WebhookStatus', 'webhookStatus' });
        result.detectedDocumentType = getFirstStringValue(
            body,
            new List<String>{ 'DetectedDocumentType', 'detectedDocumentType' }
        );
        result.confidence = normalizeConfidenceForPercent(
            toDecimalOrNull(
                getFirstValue(body, new List<String>{ 'Confidence', 'confidence', 'OverallConfidence', 'overallConfidence' })
            )
        );
        result.classificationConfidence = resolveClassificationConfidence(body);
        result.failureReason = getFirstStringValue(body, new List<String>{ 'FailureReason', 'failureReason' });
        result.processedAt = getFirstStringValue(body, new List<String>{ 'ProcessedAt', 'processedAt' });
        result.rawJson = rawJson;
        result.extractedFields = new List<ExtractedFieldRow>();

        Object extractedObj = getFirstValue(
            body,
            new List<String>{ 'ExtractedFields', 'extractedFields' }
        );

        if (extractedObj instanceof Map<String, Object>) {
            Map<String, Object> extractedMap = (Map<String, Object>) extractedObj;
            List<String> fieldNames = new List<String>();
            fieldNames.addAll(extractedMap.keySet());
            fieldNames.sort();

            for (String fieldName : fieldNames) {
                ExtractedFieldRow row = new ExtractedFieldRow();
                row.fieldName = fieldName;

                Object rawFieldValue = extractedMap.get(fieldName);

                if (rawFieldValue instanceof Map<String, Object>) {
                    Map<String, Object> fieldPayload = (Map<String, Object>) rawFieldValue;
                    Object valuePart = getFirstValue(fieldPayload, new List<String>{ 'Value', 'value', 'Text', 'text' });
                    Object confidencePart = getFirstValue(fieldPayload, new List<String>{ 'Confidence', 'confidence', 'Score', 'score' });

                    row.value = valuePart == null ? JSON.serialize(fieldPayload) : String.valueOf(valuePart);
                    row.confidence = normalizeConfidenceForPercent(toDecimalOrNull(confidencePart));
                } else {
                    row.value = rawFieldValue == null ? '' : String.valueOf(rawFieldValue);
                    row.confidence = null;
                }

                result.extractedFields.add(row);
            }
        }

        return result;
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

    private class AutoFillFileException extends Exception {}

    private class RecordCreationException extends Exception {}
    @TestVisible
    private static Time parseTime(String value) {
        String cleanedValue = value.trim().replace('Z', '');

        List<String> parts = cleanedValue.split(':');

        if (parts.size() < 2) {
            throw new RecordCreationException(
                'Invalid time value: ' + value
            );
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

        return Time.newInstance(
            hour,
            minute,
            second,
            millisecond
        );
    }

    @TestVisible
    private static String cleanNumericValue(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        String normalized = value.trim().toLowerCase();

        // Boolean text must not be converted into a numeric value.
        if (normalized == 'true' ||
            normalized == 'false' ||
            normalized == 'yes' ||
            normalized == 'no') {
                return null;
            }

        String cleaned = value
            .replace(',', '')
            .replace('$', '')
            .replace('€', '')
            .replace('£', '')
            .replace('%', '')
            .trim();

        return String.isBlank(cleaned)
            ? null
            : cleaned;
    }






    public class AutoFillFilePreviewRow {
        @AuraEnabled public Id contentDocumentId { get; set; }
        @AuraEnabled public Id contentVersionId { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String fileType { get; set; }
        @AuraEnabled public String fileExtension { get; set; }
        @AuraEnabled public Integer contentSize { get; set; }
        @AuraEnabled public Boolean isPdf { get; set; }
    }

    /**
     * Returns the original AutoFill-uploaded Salesforce Files linked to a Load.
     * The LWC uses the latest ContentVersion Id for an embedded PDF preview and
     * the ContentDocument Id for Salesforce's full file viewer.
     */
    @AuraEnabled(cacheable=false)
    public static List<AutoFillFilePreviewRow> getLoadFilePreviews(Id loadId) {
        if (loadId == null) {
            return new List<AutoFillFilePreviewRow>();
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :loadId
            ORDER BY SystemModstamp DESC
        ];

        if (links.isEmpty()) {
            return new List<AutoFillFilePreviewRow>();
        }

        Set<Id> documentIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            documentIds.add(link.ContentDocumentId);
        }

        Map<Id, ContentVersion> latestVersionByDocumentId =
            new Map<Id, ContentVersion>();

        for (ContentVersion version : [
            SELECT Id,
                   ContentDocumentId,
                   Title,
                   FileType,
                   FileExtension,
                   ContentSize,
                   Description
            FROM ContentVersion
            WHERE IsLatest = true
            AND ContentDocumentId IN :documentIds
        ]) {
            latestVersionByDocumentId.put(version.ContentDocumentId, version);
        }

        List<AutoFillFilePreviewRow> previews =
            new List<AutoFillFilePreviewRow>();

        for (ContentDocumentLink link : links) {
            ContentVersion version =
                latestVersionByDocumentId.get(link.ContentDocumentId);

            if (version == null ||
                String.isBlank(version.Description) ||
                !version.Description.startsWith(
                    AUTOFILL_FILE_DESCRIPTION_PREFIX
                )) {
                continue;
            }

            AutoFillFilePreviewRow row = new AutoFillFilePreviewRow();
            row.contentDocumentId = version.ContentDocumentId;
            row.contentVersionId = version.Id;
            row.title = buildContentDocumentDisplayName(
                version.Title,
                version.FileExtension
            );
            row.fileType = version.FileType;
            row.fileExtension = version.FileExtension;
            row.contentSize = version.ContentSize;
            row.isPdf =
                'PDF'.equalsIgnoreCase(version.FileType) ||
                'PDF'.equalsIgnoreCase(version.FileExtension);
            previews.add(row);
        }

        return previews;
    }

    @TestVisible
    private static String buildContentDocumentDisplayName(
        String title,
        String extension
    ) {
        String safeTitle = String.isBlank(title) ? 'Uploaded file' : title;
        String safeExtension = String.isBlank(extension) ? '' : extension;

        if (String.isBlank(safeExtension) ||
            safeTitle.toLowerCase().endsWith('.' + safeExtension.toLowerCase())) {
            return safeTitle;
        }

        return safeTitle + '.' + safeExtension.toLowerCase();
    }

    public class DraftAutoFillLoadRow {
        @AuraEnabled public Id loadId { get; set; }
        @AuraEnabled public String loadName { get; set; }
        @AuraEnabled public String autoFillStatus { get; set; }
        @AuraEnabled public Boolean createdByAutoFill { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public String route { get; set; }
        @AuraEnabled public String pickupCity { get; set; }
        @AuraEnabled public String pickupState { get; set; }
        @AuraEnabled public String deliveryCity { get; set; }
        @AuraEnabled public String deliveryState { get; set; }
        @AuraEnabled public Decimal totalAmount { get; set; }
        @AuraEnabled public String itemId { get; set; }
        @AuraEnabled public String documentType { get; set; }
        @AuraEnabled public Decimal confidence { get; set; }
        @AuraEnabled public Decimal classificationConfidence { get; set; }
        @AuraEnabled public Integer fieldCount { get; set; }
        @AuraEnabled public Boolean allFieldsDetected { get; set; }
        @AuraEnabled public String autoFillSource { get; set; }
        @AuraEnabled public String source { get; set; }
        @AuraEnabled public String detectedFieldsJson { get; set; }
        @AuraEnabled public String rawResponseJson { get; set; }
        @AuraEnabled public String sourceText { get; set; }
        @AuraEnabled public String createdDate { get; set; }
    }

    public class DraftAutoFillLoadsResult {
        @AuraEnabled public List<DraftAutoFillLoadRow> items { get; set; }
        @AuraEnabled public Integer page { get; set; }
        @AuraEnabled public Integer pageSize { get; set; }
        @AuraEnabled public Integer total { get; set; }
        @AuraEnabled public Integer totalPages { get; set; }
    }

    @AuraEnabled(cacheable=false)
    public static DraftAutoFillLoadsResult getDraftAutoFillLoads(
        Integer pageNumber,
        Integer pageSize,
        String searchTerm
    ) {
        if (pageNumber == null || pageNumber < 1) {
            pageNumber = 1;
        }

        if (pageSize == null || pageSize < 1) {
            pageSize = 10;
        }

        pageSize = Math.min(pageSize, 50);

        Schema.SObjectType loadType = Schema.getGlobalDescribe().get(LOAD_OBJECT_API_NAME);

        if (loadType == null) {
            throw new AuraHandledException('Load object was not found.');
        }

        Map<String, Schema.SObjectField> fields = loadType.getDescribe().fields.getMap();

        if (!fields.containsKey('AutoFill_Status__c')) {
            throw new AuraHandledException('AutoFill_Status__c is not installed on Load.');
        }

        List<String> selectedFields = new List<String>{
            'Id',
            'Name',
            'CreatedDate',
            'AutoFill_Status__c'
        };


        for (String fieldApiName : new List<String>{
            'FreightTM__Pickup_City__c',
            'FreightTM__Pickup_State__c',
            'FreightTM__Delivery_City__c',
            'FreightTM__Delivery_State__c',
            'FreightTM__Total__c',
            'AutoFill_Document_Type__c',
            'AutoFill_Confidence__c',
            'AutoFill_Field_Count__c',
            'AutoFill_All_Fields_Detected__c',
            'AutoFill_Source__c',
            'AutoFill_Detected_Fields__c',
            'AutoFill_Raw_Response__c'
        }) {
            String baseField = fieldApiName;
            Integer dotIndex = fieldApiName.indexOf('.');

            if (dotIndex > -1) {
                baseField = fieldApiName.substring(0, dotIndex);
            }

            if (fields.containsKey(baseField)) {
                selectedFields.add(fieldApiName);
            }
        }

        List<String> draftStatuses = new List<String>{ AUTOFILL_STATUS_DRAFT, AUTOFILL_STATUS_DIRECT };
        Map<String, Object> queryBinds = new Map<String, Object>{
            'draftStatuses' => draftStatuses
        };
        List<String> whereClauses = new List<String>{
            'AutoFill_Status__c IN :draftStatuses'
        };
        List<String> searchableFields = new List<String>{ 'Name' };

        for (String routeFieldApiName : new List<String>{
            'FreightTM__Pickup_City__c',
            'FreightTM__Pickup_State__c',
            'FreightTM__Delivery_City__c',
            'FreightTM__Delivery_State__c'
        }) {
            if (fields.containsKey(routeFieldApiName)) {
                searchableFields.add(routeFieldApiName);
            }
        }

        List<String> searchTokens = buildDraftSearchTokens(searchTerm);
        Integer searchTokenIndex = 0;

        for (String searchToken : searchTokens) {
            searchTokenIndex++;
            String bindName = 'draftSearchToken' + String.valueOf(searchTokenIndex);
            queryBinds.put(bindName, '%' + searchToken + '%');

            List<String> tokenConditions = new List<String>();
            for (String searchableField : searchableFields) {
                tokenConditions.add(searchableField + ' LIKE :' + bindName);
            }

            whereClauses.add('(' + String.join(tokenConditions, ' OR ') + ')');
        }

        String whereSoql = ' WHERE ' + String.join(whereClauses, ' AND ');
        String countSoql =
            'SELECT COUNT(Id) totalCount FROM ' + LOAD_OBJECT_API_NAME +
            whereSoql;

        List<SObject> countRows = Database.queryWithBinds(
            countSoql,
            queryBinds,
            AccessLevel.SYSTEM_MODE
        );
        AggregateResult countRow = countRows.isEmpty()
            ? null
            : (AggregateResult) countRows[0];
        Integer total = countRow == null
            ? 0
            : Integer.valueOf(String.valueOf(countRow.get('totalCount')));
        Integer totalPages = total == 0
            ? 1
            : (total + pageSize - 1) / pageSize;

        if (pageNumber > totalPages) {
            pageNumber = totalPages;
        }

        Integer rowOffset = (pageNumber - 1) * pageSize;

        String soql =
            'SELECT ' + String.join(selectedFields, ',') +
            ' FROM ' + LOAD_OBJECT_API_NAME +
            whereSoql +
            ' ORDER BY CreatedDate DESC, Id DESC' +
            ' LIMIT ' + String.valueOf(pageSize) +
            ' OFFSET ' + String.valueOf(rowOffset);

        List<SObject> records = Database.queryWithBinds(
            soql,
            queryBinds,
            AccessLevel.SYSTEM_MODE
        );
        List<DraftAutoFillLoadRow> rows = new List<DraftAutoFillLoadRow>();

        for (SObject record : records) {
            DraftAutoFillLoadRow row = new DraftAutoFillLoadRow();
            row.loadId = (Id) record.get('Id');
            row.loadName = String.valueOf(record.get('Name'));
            row.autoFillStatus = String.valueOf(record.get('AutoFill_Status__c'));
            row.createdByAutoFill = true;
            row.createdDate = String.valueOf(record.get('CreatedDate'));

            row.pickupCity = getOptionalString(record, fields, 'FreightTM__Pickup_City__c');
            row.pickupState = getOptionalString(record, fields, 'FreightTM__Pickup_State__c');
            row.deliveryCity = getOptionalString(record, fields, 'FreightTM__Delivery_City__c');
            row.deliveryState = getOptionalString(record, fields, 'FreightTM__Delivery_State__c');
            row.route = buildDraftRoute(row.pickupCity, row.pickupState, row.deliveryCity, row.deliveryState);

            if (fields.containsKey('FreightTM__Total__c')) {
                Object rawTotal = record.get('FreightTM__Total__c');
                row.totalAmount = rawTotal == null ? null : (Decimal) rawTotal;
            }

            row.itemId = '';
            row.documentType = getOptionalString(record, fields, 'AutoFill_Document_Type__c');
            row.confidence = getOptionalDecimal(record, fields, 'AutoFill_Confidence__c');
            // AutoFill_Confidence__c stores the overall score. If the API only
            // returns ClassificationConfidence, that value is stored here.
            row.classificationConfidence = row.confidence;
            row.fieldCount = getOptionalInteger(record, fields, 'AutoFill_Field_Count__c');
            row.allFieldsDetected = getOptionalBoolean(record, fields, 'AutoFill_All_Fields_Detected__c');
            row.detectedFieldsJson = getOptionalString(record, fields, 'AutoFill_Detected_Fields__c');
            row.rawResponseJson = getOptionalString(record, fields, 'AutoFill_Raw_Response__c');
            row.sourceText = resolveDraftSourceText(row.rawResponseJson);
            row.source = resolveDraftSourceLabel(
                getOptionalString(record, fields, 'AutoFill_Source__c'),
                row.rawResponseJson
            );
            row.autoFillSource = row.source;

            rows.add(row);
        }

        DraftAutoFillLoadsResult result = new DraftAutoFillLoadsResult();
        result.items = rows;
        result.page = pageNumber;
        result.pageSize = pageSize;
        result.total = total;
        result.totalPages = totalPages;
        return result;
    }

    @TestVisible
    private static String resolveDraftSourceLabel(
        String storedSource,
        String rawResponseJson
    ) {
        String sourceValue = String.isBlank(storedSource)
            ? null
            : storedSource.trim();

        if (String.isBlank(sourceValue) && !String.isBlank(rawResponseJson)) {
            try {
                Object parsed = JSON.deserializeUntyped(rawResponseJson);

                if (parsed instanceof Map<String, Object>) {
                    sourceValue = getFirstStringValue(
                        (Map<String, Object>) parsed,
                        new List<String>{
                            'AutoFillSource',
                            'autoFillSource',
                            'Source',
                            'source',
                            'UploadSource',
                            'uploadSource'
                        }
                    );
                }
            } catch (Exception ignored) {
                // A malformed historical response must not break the Draft queue.
            }
        }

        if (String.isBlank(sourceValue)) {
            return null;
        }

        String normalized = sourceValue
            .toLowerCase()
            .replaceAll('[^a-z0-9]', '');

        if (normalized.contains('webhook') || normalized.contains('email')) {
            return 'Email';
        }

        if (normalized.contains('manual')) {
            return 'Manual Upload';
        }

        if (normalized.contains('api')) {
            return 'API Upload';
        }

        return sourceValue.trim();
    }


    @TestVisible
    private static String resolveDraftSourceText(String rawResponseJson) {
        if (String.isBlank(rawResponseJson)) {
            return '';
        }

        try {
            Object parsed = JSON.deserializeUntyped(rawResponseJson);
            Object sourceText = findNestedSourceText(
                parsed,
                new Set<String>{
                    'autofillsourcetext',
                    'submittedemailcontent',
                    'emailcontent',
                    'emailbody',
                    'plaintextbody',
                    'textbody',
                    'sourcetext'
                }
            );
            String textValue = sourceText == null
                ? ''
                : String.valueOf(sourceText).trim();

            return normalize(textValue) == 'text' ? '' : textValue;
        } catch (Exception ignored) {
            return '';
        }
    }

    @TestVisible
    private static Object findNestedSourceText(
        Object source,
        Set<String> normalizedKeys
    ) {
        if (source == null || normalizedKeys == null || normalizedKeys.isEmpty()) {
            return null;
        }

        if (source instanceof Map<String, Object>) {
            Map<String, Object> sourceMap = (Map<String, Object>) source;

            for (String key : sourceMap.keySet()) {
                if (normalizedKeys.contains(normalize(key))) {
                    Object value = sourceMap.get(key);

                    if (value != null) {
                        return value;
                    }
                }
            }

            for (Object value : sourceMap.values()) {
                Object nestedValue = findNestedSourceText(value, normalizedKeys);

                if (nestedValue != null) {
                    return nestedValue;
                }
            }
        } else if (source instanceof List<Object>) {
            for (Object value : (List<Object>) source) {
                Object nestedValue = findNestedSourceText(value, normalizedKeys);

                if (nestedValue != null) {
                    return nestedValue;
                }
            }
        }

        return null;
    }

    @TestVisible
    private static List<String> buildDraftSearchTokens(String searchTerm) {
        List<String> tokens = new List<String>();

        if (String.isBlank(searchTerm)) {
            return tokens;
        }

        String normalizedSearch = searchTerm.trim();
        normalizedSearch = normalizedSearch.replace('→', ' ');
        normalizedSearch = normalizedSearch.replace('->', ' ');
        normalizedSearch = normalizedSearch.replaceAll('(?i)\\bto\\b', ' ');
        normalizedSearch = normalizedSearch.replaceAll('[,;|/]+', ' ');
        normalizedSearch = normalizedSearch.replaceAll('\\s+', ' ').trim();

        for (String token : normalizedSearch.split(' ')) {
            if (String.isBlank(token)) {
                continue;
            }

            tokens.add(token);

            if (tokens.size() == 5) {
                break;
            }
        }

        return tokens;
    }

    @TestVisible
    private static String getOptionalString(
        SObject record,
        Map<String, Schema.SObjectField> fields,
        String fieldApiName
    ) {
        if (record == null || fields == null || !fields.containsKey(fieldApiName)) {
            return '';
        }

        Object value = record.get(fieldApiName);
        return value == null ? '' : String.valueOf(value);
    }

    @TestVisible
    private static Decimal getOptionalDecimal(
        SObject record,
        Map<String, Schema.SObjectField> fields,
        String fieldApiName
    ) {
        if (record == null || fields == null || !fields.containsKey(fieldApiName)) {
            return null;
        }

        Object value = record.get(fieldApiName);
        return value == null ? null : (Decimal) value;
    }

    @TestVisible
    private static Integer getOptionalInteger(
        SObject record,
        Map<String, Schema.SObjectField> fields,
        String fieldApiName
    ) {
        Decimal value = getOptionalDecimal(record, fields, fieldApiName);
        return value == null ? null : value.intValue();
    }

    @TestVisible
    private static Boolean getOptionalBoolean(
        SObject record,
        Map<String, Schema.SObjectField> fields,
        String fieldApiName
    ) {
        if (record == null || fields == null || !fields.containsKey(fieldApiName)) {
            return false;
        }

        Object value = record.get(fieldApiName);
        return value == null ? false : (Boolean) value;
    }

    @TestVisible
    private static String buildDraftRoute(
        String pickupCity,
        String pickupState,
        String deliveryCity,
        String deliveryState
    ) {
        String origin = joinLocation(pickupCity, pickupState);
        String destination = joinLocation(deliveryCity, deliveryState);

        if (String.isBlank(origin) && String.isBlank(destination)) {
            return 'Route not available';
        }

        if (String.isBlank(origin)) {
            return destination;
        }

        if (String.isBlank(destination)) {
            return origin;
        }

        return origin + ' → ' + destination;
    }

    @TestVisible
    private static String joinLocation(String city, String state) {
        List<String> parts = new List<String>();

        if (!String.isBlank(city)) {
            parts.add(city);
        }

        if (!String.isBlank(state)) {
            parts.add(state);
        }

        return String.join(parts, ', ');
    }

    public class ExtractedItemsResult {
    @AuraEnabled public Integer page { get; set; }
    @AuraEnabled public Integer pageSize { get; set; }
    @AuraEnabled public Integer total { get; set; }
    @AuraEnabled public List<ExtractedItemRow> items { get; set; }
}

public class ExtractedItemRow {
    @AuraEnabled public String id { get; set; }
    @AuraEnabled public String tenantId { get; set; }
    @AuraEnabled public String extractedAt { get; set; }
    @AuraEnabled public String salesforceObjectType { get; set; }
    @AuraEnabled public String salesforceRecordId { get; set; }
    @AuraEnabled public String senderEmail { get; set; }
    @AuraEnabled public String extractedFieldsSummary { get; set; }
    @AuraEnabled public String extractedFieldsJson { get; set; }
}

@AuraEnabled(cacheable=false)
public static ExtractedItemsResult getExtractedItems(Integer pageNumber, Integer pageSize) {
    if (pageNumber == null || pageNumber < 1) {
        pageNumber = 1;
    }

    if (pageSize == null || pageSize < 1) {
        pageSize = 20;
    }

    String token = Test.isRunningTest() && !String.isBlank(testAccessToken)
        ? testAccessToken
        : FreightAuthApi.getStoredToken();

    if (String.isBlank(token)) {
        token = FreightAuthApi.authenticate();
    }

    String endpoint =
        BASE_URL +
        '/api/EmailExtractor/extracted-items?page=' +
        pageNumber +
        '&pageSize=' +
        pageSize;

    HttpRequest req = new HttpRequest();
    req.setEndpoint(endpoint);
    req.setMethod('GET');
    req.setTimeout(120000);
    req.setHeader('Authorization', 'Bearer ' + token);
    req.setHeader('Accept', 'application/json');

    HttpResponse res = new Http().send(req);

    if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
        throw new AuraHandledException(
            'Could not load extracted items. Status: ' +
            res.getStatusCode() +
            '. Response: ' +
            res.getBody()
        );
    }

    Map<String, Object> body =
        (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

    ExtractedItemsResult result = new ExtractedItemsResult();
    result.page = parseExtractedItemsInteger(body.get('Page'));
    result.pageSize = parseExtractedItemsInteger(body.get('PageSize'));
    result.total = parseExtractedItemsInteger(body.get('Total'));
    result.items = new List<ExtractedItemRow>();

    Object itemsObj = body.get('Items');

    if (itemsObj instanceof List<Object>) {
        for (Object itemObj : (List<Object>) itemsObj) {
            if (!(itemObj instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> item = (Map<String, Object>) itemObj;

            ExtractedItemRow row = new ExtractedItemRow();
            row.id = getExtractedItemsString(item, 'Id');
            row.tenantId = getExtractedItemsString(item, 'TenantId');
            row.extractedAt = getExtractedItemsString(item, 'ExtractedAt');
            row.salesforceObjectType = getExtractedItemsString(item, 'SalesforceObjectType');
            row.salesforceRecordId = getExtractedItemsString(item, 'SalesforceRecordId');
            row.senderEmail = getExtractedItemsString(item, 'SenderEmail');

            Object fieldsObj = item.get('ExtractedFields');

            if (fieldsObj instanceof Map<String, Object>) {
                Map<String, Object> fieldsMap =
                    (Map<String, Object>) fieldsObj;

                row.extractedFieldsJson = JSON.serialize(fieldsMap);
                row.extractedFieldsSummary =
                    buildExtractedItemsFieldSummary(fieldsMap);
            } else {
                row.extractedFieldsJson = '';
                row.extractedFieldsSummary = '';
            }

            result.items.add(row);
        }
    }

    return result;
}

@TestVisible
private static String getExtractedItemsString(Map<String, Object> source, String key) {
    if (source == null || String.isBlank(key) || !source.containsKey(key)) {
        return '';
    }

    Object value = source.get(key);
    return value == null ? '' : String.valueOf(value);
}

@TestVisible
private static Integer parseExtractedItemsInteger(Object value) {
    if (value == null) {
        return 0;
    }

    try {
        return Integer.valueOf(String.valueOf(value));
    } catch (Exception e) {
        return 0;
    }
}

@TestVisible
private static String buildExtractedItemsFieldSummary(Map<String, Object> fieldsMap) {
    if (fieldsMap == null || fieldsMap.isEmpty()) {
        return '';
    }

    List<String> parts = new List<String>();

    for (String key : fieldsMap.keySet()) {
        Object rawValue = fieldsMap.get(key);
        String value = rawValue == null ? '' : String.valueOf(rawValue);

        parts.add(key + ': ' + (String.isBlank(value) ? 'blank' : value));

        if (parts.size() >= 4) {
            break;
        }
    }

    return String.join(parts, ' | ');
}
}