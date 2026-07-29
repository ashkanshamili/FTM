public with sharing class DATIntegrationConfig {
    public class Settings {
        public Boolean enabled;
        public String partnerId;
        public String environmentLabel;
        public Integer orgTokenTtlSeconds;
        public Integer userTokenTtlSeconds;
    }

    @TestVisible
    private static Settings testSettings;

    public static Settings getSettings() {
        if (Test.isRunningTest() && testSettings != null) {
            return testSettings;
        }

        DAT_Integration_Config__mdt row = DAT_Integration_Config__mdt.getInstance('Default');
        Settings settings = new Settings();
        settings.enabled = row != null && row.Enabled__c;
        settings.partnerId = row == null ? null : row.Partner_Id__c;
        settings.environmentLabel = row == null ? 'Not configured' : row.Environment_Label__c;
        settings.orgTokenTtlSeconds = normalizeTtl(row == null ? null : row.Org_Token_TTL_Seconds__c);
        settings.userTokenTtlSeconds = normalizeTtl(row == null ? null : row.User_Token_TTL_Seconds__c);
        return settings;
    }

    public static Settings requireEnabled() {
        Settings settings = getSettings();
        if (settings == null || settings.enabled != true) {
            throw new DATIntegrationException('DAT integration is disabled. Enable the Default DAT configuration record first.');
        }
        if (String.isBlank(settings.partnerId)) {
            throw new DATIntegrationException('DAT Partner ID is not configured.');
        }
        return settings;
    }

    private static Integer normalizeTtl(Decimal rawValue) {
        Integer defaultValue = 1680;
        if (rawValue == null) {
            return defaultValue;
        }
        Integer value = rawValue.intValue();
        return value < 300 ? 300 : value;
    }
}
