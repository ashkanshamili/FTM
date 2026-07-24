public without sharing class CustomerPortalCredentialEmailService {
    @TestVisible
    private static final String DEFAULT_PORTAL_PATH = '/apex/CustomerPortal';

    public static void sendWhenCredentialsChanged(
        List<Account> newRecords,
        Map<Id, Account> oldMap
    ) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }

        List<Account> candidates = new List<Account>();
        Set<Id> accountIdsNeedingContactEmail = new Set<Id>();

        for (Account accountRec : newRecords) {
            Account oldRec = oldMap == null ? null : oldMap.get(accountRec.Id);
            if (!shouldSend(accountRec, oldRec)) {
                continue;
            }

            candidates.add(accountRec);
            if (String.isBlank(resolveDirectEmail(accountRec)) && accountRec.Id != null) {
                accountIdsNeedingContactEmail.add(accountRec.Id);
            }
        }

        if (candidates.isEmpty()) {
            return;
        }

        Map<Id, String> contactEmailByAccountId = findFallbackContactEmails(accountIdsNeedingContactEmail);
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();

        for (Account accountRec : candidates) {
            String recipientEmail = resolveDirectEmail(accountRec);
            if (String.isBlank(recipientEmail)) {
                recipientEmail = contactEmailByAccountId.get(accountRec.Id);
            }
            if (String.isBlank(recipientEmail)) {
                System.debug(LoggingLevel.WARN,
                    'Customer Portal credential email skipped for Account ' + accountRec.Id +
                    ' because no customer email address was available.');
                continue;
            }

            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setToAddresses(new List<String>{ recipientEmail });
            message.setSubject('Your FTM Customer Portal Access');
            message.setSenderDisplayName('FTM Customer Portal');
            message.setSaveAsActivity(false);
            message.setPlainTextBody(buildPlainTextBody(accountRec));
            message.setHtmlBody(buildHtmlBody(accountRec));
            messages.add(message);
        }

        if (messages.isEmpty()) {
            return;
        }

        try {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(messages, false);
            for (Integer index = 0; index < results.size(); index++) {
                if (!results[index].isSuccess()) {
                    for (Messaging.SendEmailError emailError : results[index].getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'Customer Portal credential email failed: ' + emailError.getMessage());
                    }
                }
            }
        } catch (Exception emailException) {
            System.debug(LoggingLevel.ERROR,
                'Customer Portal credential email could not be sent: ' + emailException.getMessage());
        }
    }

    @TestVisible
    private static Boolean shouldSend(Account newRec, Account oldRec) {
        if (newRec == null || newRec.Customer_Portal_Active__c != true) {
            return false;
        }
        if (String.isBlank(newRec.Customer_Portal_Username__c) ||
            String.isBlank(newRec.Customer_Portal_New_Password__c)) {
            return false;
        }

        if (oldRec == null) {
            return true;
        }

        return newRec.Customer_Portal_Username__c != oldRec.Customer_Portal_Username__c ||
            newRec.Customer_Portal_New_Password__c != oldRec.Customer_Portal_New_Password__c ||
            newRec.Customer_Portal_Email__c != oldRec.Customer_Portal_Email__c ||
            (oldRec.Customer_Portal_Active__c != true && newRec.Customer_Portal_Active__c == true);
    }

    private static String resolveDirectEmail(Account accountRec) {
        if (!String.isBlank(accountRec.Customer_Portal_Email__c)) {
            return accountRec.Customer_Portal_Email__c.trim();
        }
        if (isValidEmail(accountRec.Customer_Portal_Username__c)) {
            return accountRec.Customer_Portal_Username__c.trim();
        }
        return null;
    }

    private static Map<Id, String> findFallbackContactEmails(Set<Id> accountIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (accountIds == null || accountIds.isEmpty()) {
            return result;
        }

        for (Contact contactRec : [
            SELECT AccountId, Email
            FROM Contact
            WHERE AccountId IN :accountIds
              AND Email != null
            ORDER BY AccountId, CreatedDate ASC
        ]) {
            if (!result.containsKey(contactRec.AccountId)) {
                result.put(contactRec.AccountId, contactRec.Email);
            }
        }
        return result;
    }

    private static Boolean isValidEmail(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        return Pattern.matches('^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$', value.trim());
    }

    private static String getPortalUrl() {
        String configuredUrl = System.Label.Customer_Portal_URL;
        return String.isBlank(configuredUrl)
            ? URL.getOrgDomainUrl().toExternalForm() + DEFAULT_PORTAL_PATH
            : configuredUrl.trim();
    }

    private static String buildPlainTextBody(Account accountRec) {
        String greetingName = String.isBlank(accountRec.Name) ? 'Customer' : accountRec.Name;
        return 'Hello ' + greetingName + ' Team,\n\n' +
            'Your access to the FTM Customer Portal has been created or updated. ' +
            'You can use the information below to sign in and review your shipments, documents, tracking, and invoices.\n\n' +
            'Customer Portal: ' + getPortalUrl() + '\n' +
            'Username: ' + accountRec.Customer_Portal_Username__c + '\n' +
            'Password: ' + accountRec.Customer_Portal_New_Password__c + '\n\n' +
            'Please keep these login details secure and do not share them with unauthorized users. ' +
            'If you did not expect this message or need assistance, please contact your transportation team.\n\n' +
            'Best regards,\nFTM Customer Portal Team';
    }

    private static String buildHtmlBody(Account accountRec) {
        String greetingName = String.isBlank(accountRec.Name) ? 'Customer' : accountRec.Name;
        String safeName = greetingName.escapeHtml4();
        String safeUrl = getPortalUrl().escapeHtml4();
        String safeUsername = accountRec.Customer_Portal_Username__c.escapeHtml4();
        String safePassword = accountRec.Customer_Portal_New_Password__c.escapeHtml4();

        return '<div style="font-family:Arial,sans-serif;color:#0B1220;line-height:1.6;max-width:640px">' +
            '<p>Hello ' + safeName + ' Team,</p>' +
            '<p>Your access to the <strong>FTM Customer Portal</strong> has been created or updated. ' +
            'You can use the information below to sign in and review your shipments, documents, tracking, and invoices.</p>' +
            '<div style="background:#F6F8FB;border:1px solid #E2E8F0;border-radius:10px;padding:18px;margin:20px 0">' +
            '<p style="margin:0 0 10px"><strong>Portal:</strong> ' +
            '<a href="' + safeUrl + '" style="color:#0A74C0">' + safeUrl + '</a></p>' +
            '<p style="margin:0 0 10px"><strong>Username:</strong> ' + safeUsername + '</p>' +
            '<p style="margin:0"><strong>Password:</strong> ' + safePassword + '</p>' +
            '</div>' +
            '<p>Please keep these login details secure and do not share them with unauthorized users. ' +
            'If you did not expect this message or need assistance, please contact your transportation team.</p>' +
            '<p>Best regards,<br><strong>FTM Customer Portal Team</strong></p>' +
            '</div>';
    }
}