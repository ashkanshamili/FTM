public without sharing class AutoFillRejectedLoadDeleteService {
    @TestVisible
    private static Boolean alreadyQueued = false;

    public static void enqueueRejectedLoads(
        List<FreightTM__Load__c> newLoads,
        Map<Id, FreightTM__Load__c> oldMap
    ) {
        if (alreadyQueued) {
            return;
        }

        if (newLoads == null || newLoads.isEmpty()) {
            return;
        }

        Set<Id> loadIdsToDelete = new Set<Id>();

        for (FreightTM__Load__c newLoad : newLoads) {
            if (newLoad == null || newLoad.Id == null) {
                continue;
            }

            FreightTM__Load__c oldLoad = oldMap != null
                ? oldMap.get(newLoad.Id)
                : null;

            String newStatus = String.valueOf(newLoad.get('AutoFill_Status__c'));
            String oldStatus = oldLoad != null
                ? String.valueOf(oldLoad.get('AutoFill_Status__c'))
                : null;

            Boolean changedToRejected =
                newStatus == 'Rejected' &&
                oldStatus != 'Rejected';

            if (changedToRejected) {
                loadIdsToDelete.add(newLoad.Id);
            }
        }

        if (loadIdsToDelete.isEmpty()) {
            return;
        }

        alreadyQueued = true;
        System.enqueueJob(new DeleteRejectedAutoFillLoadsQueueable(loadIdsToDelete));
    }

    public class DeleteRejectedAutoFillLoadsQueueable implements Queueable {
        private Set<Id> loadIds;

        public DeleteRejectedAutoFillLoadsQueueable(Set<Id> loadIds) {
            this.loadIds = loadIds;
        }

        public void execute(QueueableContext context) {
            if (loadIds == null || loadIds.isEmpty()) {
                return;
            }

            List<FreightTM__Load__c> loadsToDelete = [
                SELECT Id
                FROM FreightTM__Load__c
                WHERE Id IN :loadIds
                AND AutoFill_Status__c = 'Rejected'
            ];

            if (loadsToDelete.isEmpty()) {
                return;
            }

            Database.DeleteResult[] results = Database.delete(loadsToDelete, false);

            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    System.debug('Rejected AutoFill Load deleted: ' + loadsToDelete[i].Id);
                } else {
                    for (Database.Error err : results[i].getErrors()) {
                        System.debug(
                            'Rejected AutoFill Load delete failed for ' +
                            loadsToDelete[i].Id +
                            ': ' +
                            err.getStatusCode() +
                            ' - ' +
                            err.getMessage()
                        );
                    }
                }
            }
        }
    }
}