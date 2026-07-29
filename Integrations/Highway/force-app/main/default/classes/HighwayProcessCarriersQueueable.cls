public class HighwayProcessCarriersQueueable implements Queueable, Database.AllowsCallouts {
    private List<Integer> carrierIds;       // IDs for fetching carrier details
    private List<Integer> objectIds;        // IDs for marking as processed
    private Boolean isOnboarding;           // True if processing onboarding packets
    private Boolean shouldMarkProcessed;    // True if marking is needed

    public HighwayProcessCarriersQueueable(List<Integer> carrierIds, List<Integer> objectIds, Boolean isOnboarding, Boolean shouldMarkProcessed) {
        this.carrierIds = carrierIds;
        this.objectIds = objectIds;
        this.isOnboarding = isOnboarding;
        this.shouldMarkProcessed = shouldMarkProcessed;
    }

    public void execute(QueueableContext context) {
        try {
            if (!carrierIds.isEmpty()) {
                // Process all carriers in bulk
                HighwayAPIService.processCarriersBulk(carrierIds, objectIds, isOnboarding);

                // Mark as processed if required
                if (shouldMarkProcessed && objectIds != null && !objectIds.isEmpty()) {
                    System.enqueueJob(new HighwayMarkProcessedQueueable(objectIds, isOnboarding));
                }
            } else {
                System.debug('No carriers to process in HighwayProcessCarriersQueueable');
            }
        } catch (Exception e) {
            System.debug('Error in HighwayProcessCarriersQueueable: ' + e.getMessage());
        }
    }
}
