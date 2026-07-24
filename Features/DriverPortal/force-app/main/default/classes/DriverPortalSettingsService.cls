public without sharing class DriverPortalSettingsService {
    private static final String DEFAULT_RECORD = 'Default';

    @TestVisible private static Driver_Portal_Settings__mdt testSettings;

    public static Driver_Portal_Settings__mdt getSettings() {
        if (Test.isRunningTest() && testSettings != null) {
            return testSettings;
        }
        return Driver_Portal_Settings__mdt.getInstance(DEFAULT_RECORD);
    }

    public static String getPortalPageUrl() {
        Driver_Portal_Settings__mdt settings = getSettings();
        if (settings == null || String.isBlank(settings.Portal_Page_URL__c)) {
            return null;
        }
        return normalizeUrl(settings.Portal_Page_URL__c);
    }

    public static Integer getTokenValidityDays() {
        Driver_Portal_Settings__mdt settings = getSettings();
        if (settings == null || settings.Token_Validity_Days__c == null) {
            return 14;
        }
        Integer value = settings.Token_Validity_Days__c.intValue();
        return value > 0 ? value : 14;
    }

    public static Boolean isAutoEmailEnabled() {
        Driver_Portal_Settings__mdt settings = getSettings();
        return settings != null && settings.Auto_Send_Email__c == true;
    }

    public static Boolean isAutoSmsEnabled() {
        Driver_Portal_Settings__mdt settings = getSettings();
        return settings != null && settings.Auto_Send_SMS__c == true;
    }

    public static Boolean shouldSyncDriverContact() {
        Driver_Portal_Settings__mdt settings = getSettings();
        return settings == null || settings.Sync_Driver_Contact__c != false;
    }

    public static String getCompanyName() {
        Driver_Portal_Settings__mdt settings = getSettings();
        return settings != null && String.isNotBlank(settings.Company_Name__c)
            ? settings.Company_Name__c.trim()
            : 'FTM';
    }

    public static String getEmailSubject(String loadName) {
        Driver_Portal_Settings__mdt settings = getSettings();
        String subject = settings != null && String.isNotBlank(settings.Email_Subject__c)
            ? settings.Email_Subject__c.trim()
            : 'New load assignment: {LOAD_NAME}';
        return subject.replace('{LOAD_NAME}', String.isBlank(loadName) ? 'Load' : loadName);
    }

    private static String normalizeUrl(String value) {
        String result = value == null ? null : value.trim();
        while (String.isNotBlank(result) && result.endsWith('/')) {
            result = result.substring(0, result.length() - 1);
        }
        return result;
    }
}
