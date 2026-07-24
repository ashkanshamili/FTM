public without sharing class FreightLoadSyncHandler {

    private static final Integer MAX_ITEMS_PER_JOB = 90;

    @TestVisible
    private static Boolean bypassForTests = false;

    public static void syncCreated(List<FreightTM__Load__c> loads) {
        enqueue(loads, 'POST');
    }

    public static void syncUpdated(List<FreightTM__Load__c> loads) {
        enqueue(loads, 'PATCH');
    }

    public static void syncDeleted(List<FreightTM__Load__c> loads) {
        enqueue(loads, 'DELETE');
    }

    private static void enqueue(List<FreightTM__Load__c> loads, String method) {
        if (Test.isRunningTest() && bypassForTests) {
            return;
        }

        System.debug('🔥 FreightLoadSyncHandler.enqueue START. Method=' + method);

        if (loads == null || loads.isEmpty()) {
            System.debug('⚠ No loads passed to handler.');
            return;
        }

        List<FreightLoadSyncRequest> requests = new List<FreightLoadSyncRequest>();

        for (FreightTM__Load__c loadRecord : loads) {
            System.debug('🔥 Processing Load Id=' + loadRecord.Id);
            System.debug('🔥 Current Freight_Id__c=' + loadRecord.Freight_Id__c);

            String freightGraphId = String.valueOf(loadRecord.Freight_Id__c);
            String bodyJson = null;

            if (method == 'POST' || method == 'PATCH') {
                Map<String, Object> body = FreightLoadPayloadBuilder.build(loadRecord);
                bodyJson = JSON.serialize(body);
            }

            if ((method == 'PATCH' || method == 'DELETE') && String.isBlank(freightGraphId)) {
                System.debug(
                    '❌ Skipping ' + method +
                    ' because Freight_Id__c is blank. Load Id=' + loadRecord.Id
                );
                continue;
            }

            FreightLoadSyncRequest req = new FreightLoadSyncRequest(
                method,
                loadRecord.Id,
                freightGraphId,
                bodyJson
            );

            requests.add(req);
        }

        System.debug('🔥 Total FreightGraph requests built=' + requests.size());

        if (requests.isEmpty()) {
            System.debug('⚠ No requests to enqueue.');
            return;
        }

        List<FreightLoadSyncRequest> chunk = new List<FreightLoadSyncRequest>();

        for (FreightLoadSyncRequest req : requests) {
            chunk.add(req);

            if (chunk.size() == MAX_ITEMS_PER_JOB) {
                System.enqueueJob(new FreightLoadSyncQueueable(chunk));
                chunk = new List<FreightLoadSyncRequest>();
            }
        }

        if (!chunk.isEmpty()) {
            System.debug('🔥 Enqueuing FreightLoadSyncQueueable. Count=' + chunk.size());
            System.enqueueJob(new FreightLoadSyncQueueable(chunk));
        }
    }
}