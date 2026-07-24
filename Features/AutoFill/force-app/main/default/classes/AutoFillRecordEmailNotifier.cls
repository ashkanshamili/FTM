public without sharing class AutoFillRecordEmailNotifier implements Queueable {

    private static final String LOAD_OBJECT_API_NAME = 'FreightTM__Load__c';
    private static final String SOURCE_FIELD_API_NAME = 'AutoFill_Source__c';
    private static final String EMAIL_WEBHOOK_SOURCE = 'Email';

    private Id recordId;

    @TestVisible
    private static Boolean forceBlankLoadNameForTests = false;

    @TestVisible
    private static Boolean forceEmptyEmailResultForTests = false;

    @TestVisible
    private static Boolean forceEmailExceptionForTests = false;

    @TestVisible
    private static String lastResolvedLoadNameForTests;

    public AutoFillRecordEmailNotifier(Id recordId) {
        this.recordId = recordId;
    }

    public void execute(QueueableContext context) {
        if (recordId == null) {
            logSkip('Record ID is null.');
            return;
        }

        if (recordId.getSObjectType() != FreightTM__Load__c.SObjectType) {
            logSkip('The created record is not a Load. Record ID: ' + recordId);
            return;
        }

        Map<String, Schema.SObjectField> loadFields =
            FreightTM__Load__c.SObjectType.getDescribe().fields.getMap();

        if (!loadFields.containsKey(SOURCE_FIELD_API_NAME)) {
            logSkip('The Load source field is not available.');
            return;
        }

        List<SObject> loadRecords = Database.query(
            'SELECT Id, Name, ' + SOURCE_FIELD_API_NAME +
            ' FROM ' + LOAD_OBJECT_API_NAME +
            ' WHERE Id = :recordId LIMIT 1'
        );

        if (loadRecords.isEmpty()) {
            logSkip('The Load record was not found. Record ID: ' + recordId);
            return;
        }

        SObject loadRecord = loadRecords[0];
        String source = String.valueOf(loadRecord.get(SOURCE_FIELD_API_NAME));

        if (!isWebhookSource(source)) {
            logSkip(
                'The Load source is not Webhook. Record ID: ' +
                recordId + '. Source: ' + source
            );
            return;
        }

        EmailAddressEmailExtractor__c emailSetting =
            EmailAddressEmailExtractor__c.getOrgDefaults();

        if (
            emailSetting == null ||
            String.isBlank(emailSetting.Email_Add__c)
        ) {
            logSkip('Email To Load address is not configured.');
            return;
        }

        String recipientEmail = emailSetting.Email_Add__c.trim();
        String loadName = String.valueOf(loadRecord.get('Name'));

        if (Test.isRunningTest() && forceBlankLoadNameForTests) {
            loadName = null;
        }

        if (String.isBlank(loadName) || loadName == 'null') {
            loadName = String.valueOf(recordId);
        }

        if (Test.isRunningTest()) {
            lastResolvedLoadNameForTests = loadName;
        }

        String loadUrl =
            URL.getOrgDomainUrl().toExternalForm() +
            '/lightning/r/' +
            LOAD_OBJECT_API_NAME +
            '/' +
            recordId +
            '/view';

        Messaging.SingleEmailMessage email =
            new Messaging.SingleEmailMessage();

        email.setToAddresses(new List<String>{ recipientEmail });
        email.setSubject('Email processed: Load ' + loadName + ' created');
        email.setPlainTextBody(
            'The email sent to Email To Load was received and processed successfully.\n\n' +
            'Load ' + loadName + ' was created in FTM.\n' +
            'Source: ' + EMAIL_WEBHOOK_SOURCE + '\n' +
            'Load ID: ' + recordId + '\n' +
            'Open Load: ' + loadUrl + '\n'
        );
        email.setSaveAsActivity(false);
        email.setUseSignature(false);

        try {
            if (Test.isRunningTest() && forceEmailExceptionForTests) {
                throw new ForcedEmailException('Forced email exception.');
            }

            Messaging.SendEmailResult[] results;

            if (Test.isRunningTest() && forceEmptyEmailResultForTests) {
                results = new List<Messaging.SendEmailResult>();
            } else {
                results = Messaging.sendEmail(
                    new List<Messaging.SingleEmailMessage>{ email }
                );
            }

            if (results.isEmpty() || !results[0].isSuccess()) {
                String errorMessage = results.isEmpty()
                    ? 'Salesforce returned no email result.'
                    : getEmailErrors(results[0]);

                System.debug(
                    LoggingLevel.ERROR,
                    'Webhook Load confirmation email failed. Load ID: ' +
                    recordId + '. Error: ' + errorMessage
                );
                return;
            }

            System.debug(
                LoggingLevel.INFO,
                'Webhook Load confirmation email sent. Load ID: ' +
                recordId + '. Recipient: ' + recipientEmail
            );
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Webhook Load confirmation email exception. Load ID: ' +
                recordId + '. Error: ' + e.getMessage()
            );
        }
    }

    @TestVisible
    private static Boolean isWebhookSource(String source) {
        if (String.isBlank(source) || source == 'null') {
            return false;
        }

        String normalized = source
            .trim()
            .toLowerCase()
            .replaceAll('[^a-z0-9]', '');

        return normalized == 'email' ||
            normalized == 'webhook' ||
            normalized == 'emailwebhook' ||
            normalized.contains('webhook') ||
            normalized.contains('email');
    }

    private static void logSkip(String reason) {
        System.debug(
            LoggingLevel.WARN,
            'Webhook Load confirmation email skipped: ' + reason
        );
    }

    private class ForcedEmailException extends Exception {
    }

    @TestVisible
    private static String getEmailErrors(
        Messaging.SendEmailResult result
    ) {
        List<String> messages = new List<String>();

        for (Messaging.SendEmailError error : result.getErrors()) {
            messages.add(
                String.valueOf(error.getStatusCode()) +
                ': ' +
                error.getMessage()
            );
        }

        return String.join(messages, '; ');
    }
}