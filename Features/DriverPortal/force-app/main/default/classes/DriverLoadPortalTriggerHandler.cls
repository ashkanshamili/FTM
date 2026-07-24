public without sharing class DriverLoadPortalTriggerHandler {
    private static final String SITE_BASE_URL =
        'https://wise-koala-63tngo-dev-ed.trailblaze.my.salesforce-sites.com/DriverPortal';
    
    public static void handleBefore(
        List<FreightTM__Load__c> newLoads,
        Map<Id, FreightTM__Load__c> oldMap,
        Boolean isInsert,
        Boolean isUpdate
    ) {
        for (FreightTM__Load__c newLoad : newLoads) {
            if (isInsert) {
                handleBeforeInsert(newLoad);
            }
            
            if (isUpdate) {
                FreightTM__Load__c oldLoad = oldMap.get(newLoad.Id);
                handleBeforeUpdate(newLoad, oldLoad);
            }
        }
    }
    
    /*public static void handleAfter(
        List<FreightTM__Load__c> newLoads,
        Map<Id, FreightTM__Load__c> oldMap,
        Boolean isInsert,
        Boolean isUpdate
    ) {
        Set<Id> loadIdsToSendSms = new Set<Id>();
        
        for (FreightTM__Load__c newLoad : newLoads) {
            String newPortalLink = newLoad.Driver_Portal_Link__c;
            
            if (String.isBlank(newPortalLink)) {
                continue;
            }
            
            if (isInsert) {
                loadIdsToSendSms.add(newLoad.Id);
            }
            
            if (isUpdate) {
                FreightTM__Load__c oldLoad = oldMap.get(newLoad.Id);
                
                String oldPortalLink = oldLoad != null
                    ? oldLoad.Driver_Portal_Link__c
                    : null;
                
                Boolean portalLinkWasCreated =
                    String.isBlank(oldPortalLink) &&
                    !String.isBlank(newPortalLink);
                
                Boolean portalLinkWasChanged =
                    !String.isBlank(oldPortalLink) &&
                    oldPortalLink != newPortalLink;
                
                if (portalLinkWasCreated || portalLinkWasChanged) {
                    loadIdsToSendSms.add(newLoad.Id);
                }
            }
        }
        
        if (!loadIdsToSendSms.isEmpty()) {
            System.enqueueJob(new DriverPortalSmsQueueable(loadIdsToSendSms));
        }
    }*/
  public static void handleAfter(
    List<FreightTM__Load__c> newLoads,
    Map<Id, FreightTM__Load__c> oldMap,
    Boolean isInsert,
    Boolean isUpdate
) {
    // This handler is only for insert/update notification logic.
    // In after delete, Trigger.new is null, so do not run this logic.
    if (isInsert != true && isUpdate != true) {
        return;
    }

    if (newLoads == null || newLoads.isEmpty()) {
        return;
    }

    Set<Id> loadIdsToSendSms = new Set<Id>();
    Set<Id> loadIdsToSendDriverEmail = new Set<Id>();

    for (FreightTM__Load__c newLoad : newLoads) {
        if (newLoad == null) {
            continue;
        }

        String newPortalLink = newLoad.Driver_Portal_Link__c;

        Boolean hasDriver =
            newLoad.FreightTM__Driver__c != null;

        Boolean hasDriverEmail =
            String.isNotBlank(newLoad.FreightTM__Driver_Email__c);

        Boolean hasPortalLink =
            String.isNotBlank(newPortalLink);

        if (isInsert) {
            if (hasPortalLink) {
                loadIdsToSendSms.add(newLoad.Id);
            }

            if (hasDriver && hasDriverEmail && hasPortalLink) {
                loadIdsToSendDriverEmail.add(newLoad.Id);
            }
        }

        if (isUpdate) {
            FreightTM__Load__c oldLoad = oldMap != null
                ? oldMap.get(newLoad.Id)
                : null;

            String oldPortalLink = oldLoad != null
                ? oldLoad.Driver_Portal_Link__c
                : null;

            Boolean portalLinkWasCreated =
                String.isBlank(oldPortalLink) &&
                !String.isBlank(newPortalLink);

            Boolean portalLinkWasChanged =
                !String.isBlank(oldPortalLink) &&
                oldPortalLink != newPortalLink;

            if (hasPortalLink && (portalLinkWasCreated || portalLinkWasChanged)) {
                loadIdsToSendSms.add(newLoad.Id);
            }

            Id oldDriverId = oldLoad != null
                ? oldLoad.FreightTM__Driver__c
                : null;

            Id newDriverId = newLoad.FreightTM__Driver__c;

            Boolean driverWasAssignedOrChanged =
                newDriverId != null &&
                oldDriverId != newDriverId;

            if (driverWasAssignedOrChanged && hasDriverEmail && hasPortalLink) {
                loadIdsToSendDriverEmail.add(newLoad.Id);
            }
        }
    }

    if (Test.isRunningTest()) {
        System.debug(
            'Driver portal notification queueables skipped during test. ' +
            'SMS Load Ids=' + loadIdsToSendSms +
            ', Email Load Ids=' + loadIdsToSendDriverEmail
        );
        return;
    }

    if (!loadIdsToSendSms.isEmpty()) {
        System.enqueueJob(new DriverPortalSmsQueueable(loadIdsToSendSms));
    }

    if (!loadIdsToSendDriverEmail.isEmpty()) {
        System.enqueueJob(new DriverPortalEmailQueueable(loadIdsToSendDriverEmail));
    }
}
    
    private static void handleBeforeInsert(FreightTM__Load__c newLoad) {
        if (newLoad.FreightTM__Driver__c != null) {
            DriverLoadPortalTokenService.populatePortalFields(
                newLoad,
                SITE_BASE_URL
            );
        }
    }
    
    private static void handleBeforeUpdate(
        FreightTM__Load__c newLoad,
        FreightTM__Load__c oldLoad
    ) {
        if (oldLoad == null) {
            return;
        }
        
        Id oldDriverId = oldLoad.FreightTM__Driver__c;
        Id newDriverId = newLoad.FreightTM__Driver__c;
        
        Boolean driverWasAssigned =
            oldDriverId == null &&
            newDriverId != null;
        
        Boolean driverWasChanged =
            oldDriverId != null &&
            newDriverId != null &&
            oldDriverId != newDriverId;
        
        Boolean driverWasRemoved =
            oldDriverId != null &&
            newDriverId == null;
        
        if (driverWasAssigned || driverWasChanged) {
            DriverLoadPortalTokenService.populatePortalFields(
                newLoad,
                SITE_BASE_URL
            );
        }
        
        if (driverWasRemoved) {
            newLoad.Driver_Portal_Active__c = false;
            newLoad.Driver_Portal_Link__c = null;
        }
    }
}