public without sharing class DriverPortalSmsQueueable implements Queueable {
    private Set<Id> loadIds;
    
    public DriverPortalSmsQueueable(Set<Id> loadIds) {
        this.loadIds = loadIds;
    }
    
    public void execute(QueueableContext context) {
        if (loadIds == null || loadIds.isEmpty()) {
            return;
        }
        
        List<FreightTM__Load__c> loads = [
            SELECT Id,
                   Name,
                   Driver_Portal_Link__c,
                   FreightTM__Driver__c,
                   Driver_Phone_Number__c,
                   Driver_Phone_Carrier__c
            FROM FreightTM__Load__c
            WHERE Id IN :loadIds
        ];
        
        for (FreightTM__Load__c loadRec : loads) {
            if (String.isBlank(loadRec.Driver_Portal_Link__c)) {
                continue;
            }
            
            if (String.isBlank(loadRec.Driver_Phone_Number__c)) {
                System.debug('SMS skipped. Missing driver phone number for Load: ' + loadRec.Id);
                continue;
            }
            
            if (String.isBlank(loadRec.Driver_Phone_Carrier__c)) {
                System.debug('SMS skipped. Missing driver phone carrier for Load: ' + loadRec.Id);
                continue;
            }
            
            String cleanPhone = cleanPhoneNumber(loadRec.Driver_Phone_Number__c);
            String message = loadRec.Driver_Portal_Link__c;
            
            // Prevent external SMS/web-service callout during Apex tests
            if (Test.isRunningTest()) {
                System.debug(
                    'SMS skipped during test. Phone=' + cleanPhone +
                    ', Carrier=' + loadRec.Driver_Phone_Carrier__c +
                    ', Message=' + message
                );
                continue;
            }

            
            SendSMSToDriver.sendSMS(
                cleanPhone,
                loadRec.Driver_Phone_Carrier__c,
                message
            );
        }
    }
    
    private static String cleanPhoneNumber(String phoneNumber) {
        if (String.isBlank(phoneNumber)) {
            return null;
        }
        
        return phoneNumber.replaceAll('[^0-9]', '');
    }
}