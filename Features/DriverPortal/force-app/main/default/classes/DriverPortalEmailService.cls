public without sharing class DriverPortalEmailService {
    public static void sendDriverEmails(Set<Id> loadIds) {
        if (loadIds == null || loadIds.isEmpty()) {
            return;
        }
        
        List<FreightTM__Load__c> loads = [
            SELECT
            Id,
            Name,
            FreightTM__Driver__c,
            FreightTM__Driver__r.Name,
            FreightTM__Driver_Email__c,
            Driver_Portal_Link__c
            FROM FreightTM__Load__c
            WHERE Id IN :loadIds
        ];
        
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        
        for (FreightTM__Load__c load : loads) {
            if (
                load.FreightTM__Driver__c == null ||
                String.isBlank(load.FreightTM__Driver_Email__c) ||
                String.isBlank(load.Driver_Portal_Link__c)
            ) {
                continue;
            }
            
            String driverName = load.FreightTM__Driver__r != null
                ? load.FreightTM__Driver__r.Name
                : 'Driver';
            
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            
            email.setToAddresses(new List<String>{
                load.FreightTM__Driver_Email__c
                    });
            
            email.setSubject('Driver app link from Dev17.');
            
            email.setPlainTextBody(
                'Hi ' + driverName + '\n\n' +
                'The ' + load.Name + ' has been assigned. Please update us.\n\n' +
                'Load : ' + load.Name + '\n' +
                'App Link: ' + load.Driver_Portal_Link__c + '\n\n' +
                'Thanks for choosing us,\n' +
                'Dev 17.'
            );
            
            emails.add(email);
        }
        
        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails);
        }
    }
}