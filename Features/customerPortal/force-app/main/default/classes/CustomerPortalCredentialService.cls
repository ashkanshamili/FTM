public without sharing class CustomerPortalCredentialService {
    public static void setAccountLogin(Id accountId, String username, String password) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }
        String cleanUsername = normalizeUsername(username);
        validateUsernameAndPassword(cleanUsername, password);

        String salt = generateSalt();
        Account accountRec = new Account(
            Id = accountId,
            Customer_Portal_Username__c = cleanUsername,
            Customer_Portal_New_Password__c = password,
            Customer_Portal_Password_Salt__c = salt,
            Customer_Portal_Password_Hash__c = hashPassword(salt, password),
            Customer_Portal_Active__c = true,
            Customer_Portal_Password_Set_At__c = System.now()
        );
        update accountRec;
    }

    public static void deactivateAccountLogin(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }
        update new Account(Id = accountId, Customer_Portal_Active__c = false);
    }

    public static void applyAccountLoginFields(List<Account> records) {
        applyAccountLoginFields(records, null);
    }

    public static void applyAccountLoginFields(List<Account> records, Map<Id, Account> oldMap) {
        if (records == null || records.isEmpty()) {
            return;
        }

        for (Account accountRec : records) {
            if (!String.isBlank(accountRec.Customer_Portal_Username__c)) {
                accountRec.Customer_Portal_Username__c = normalizeUsername(accountRec.Customer_Portal_Username__c);
            }

            Account oldRec = oldMap == null || accountRec.Id == null
                ? null
                : oldMap.get(accountRec.Id);
            Boolean passwordChanged = !String.isBlank(accountRec.Customer_Portal_New_Password__c)
                && (oldRec == null || accountRec.Customer_Portal_New_Password__c != oldRec.Customer_Portal_New_Password__c);
            if (!passwordChanged) {
                continue;
            }

            String cleanUsername = normalizeUsername(accountRec.Customer_Portal_Username__c);
            validateUsernameAndPassword(cleanUsername, accountRec.Customer_Portal_New_Password__c);

            String salt = generateSalt();
            accountRec.Customer_Portal_Username__c = cleanUsername;
            accountRec.Customer_Portal_Password_Salt__c = salt;
            accountRec.Customer_Portal_Password_Hash__c = hashPassword(salt, accountRec.Customer_Portal_New_Password__c);
            accountRec.Customer_Portal_Active__c = true;
            accountRec.Customer_Portal_Password_Set_At__c = System.now();
        }
    }

    public static String normalizeUsername(String username) {
        return String.isBlank(username) ? null : username.trim().toLowerCase();
    }

    public static String hashPassword(String salt, String password) {
        if (String.isBlank(salt) || String.isBlank(password)) {
            return null;
        }
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(salt + ':' + password));
        return EncodingUtil.convertToHex(digest);
    }

    private static void validateUsernameAndPassword(String username, String password) {
        if (String.isBlank(username) || String.isBlank(password)) {
            throw new AuraHandledException('Customer Portal Username and Customer Portal Password are required.');
        }
        if (password.length() < 8) {
            throw new AuraHandledException('Use a password with at least 8 characters.');
        }
    }

    private static String generateSalt() {
        String salt = EncodingUtil.base64Encode(Crypto.generateAesKey(128));
        salt = salt.replace('+', '-');
        salt = salt.replace('/', '_');
        salt = salt.replace('=', '');
        return salt;
    }
}