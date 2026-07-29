public with sharing class DATEquipmentMapper {
    @TestVisible
    private static Map<String, String> testMappings;

    public static String toDatCode(String ftmValue) {
        if (String.isBlank(ftmValue)) {
            throw new DATIntegrationException('Required Trailer is missing.');
        }

        Map<String, String> mappings = loadMappings();
        String code = mappings.get(ftmValue);
        if (String.isBlank(code)) {
            throw new DATIntegrationException(
                'No active DAT equipment mapping exists for Required Trailer: ' + ftmValue
            );
        }
        return code;
    }

    private static Map<String, String> loadMappings() {
        if (Test.isRunningTest() && testMappings != null) {
            return testMappings;
        }

        Map<String, String> result = new Map<String, String>();
        for (DAT_Equipment_Map__mdt row : [
            SELECT FTM_Value__c, DAT_Code__c
            FROM DAT_Equipment_Map__mdt
            WHERE Active__c = true
        ]) {
            if (!String.isBlank(row.FTM_Value__c) && !String.isBlank(row.DAT_Code__c)) {
                result.put(row.FTM_Value__c, row.DAT_Code__c);
            }
        }
        return result;
    }
}
