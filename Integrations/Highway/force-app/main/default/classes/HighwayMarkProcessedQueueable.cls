public class HighwayMarkProcessedQueueable implements Queueable, Database.AllowsCallouts {
    private List<Integer> ids;
    private Boolean isOnboarding;

    public HighwayMarkProcessedQueueable(List<Integer> ids, Boolean isOnboarding) {
        this.ids = ids;
        this.isOnboarding = isOnboarding;
    }

    public void execute(QueueableContext context) {
        try {
            HttpResponse response = HighwayAPIService.markAsProcessed(ids, isOnboarding);
            if (response.getStatusCode() != 200) {
                System.debug('Error marking as processed: ' + response.getBody());
            } else {
                System.debug('Successfully marked as processed: ' + response.getBody());
            }
        } catch (Exception e) {
            System.debug('Exception in HighwayMarkProcessedQueueable: ' + e.getMessage());
        }
    }
}
