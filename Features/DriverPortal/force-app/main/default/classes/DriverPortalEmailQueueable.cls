public without sharing class DriverPortalEmailQueueable implements Queueable {
    private Set<Id> loadIds;

    public DriverPortalEmailQueueable(Set<Id> loadIds) {
        this.loadIds = loadIds;
    }

    public void execute(QueueableContext context) {
        
        if (loadIds == null || loadIds.isEmpty()) {
            return;
        }
        
        // Prevent external/email service logic during Apex tests
        if (Test.isRunningTest()) {
            System.debug('Driver portal email skipped during test for Load Ids: ' + loadIds);
            return;
        }
        
        DriverPortalEmailService.sendDriverEmails(loadIds);
    }
}