@IsTest
private class AutoFillRejectedLoadDeleteServiceTest {

    private static FreightTM__Load__c createDraftLoad() {
        FreightLoadSyncHandler.bypassForTests = true;
        Test.setMock(HttpCalloutMock.class, new AutoFillTestCalloutMock());

        Account customer = new Account(
            Name = 'Rejected AutoFill Test Customer ' + System.now().getTime()
        );
        insert customer;

        FreightTM__Load__c loadRecord = new FreightTM__Load__c(
            FreightTM__Customer__c = customer.Id,
            FreightTM__Pickup_City__c = 'Irvine',
            FreightTM__Delivery_City__c = 'Phoenix',
            FreightTM__Pickup_Date__c = Date.today(),
            FreightTM__Delivery_Date__c = Date.today().addDays(1),
            FreightTM__Status__c = 'Assigned'
        );

        Map<String, Schema.SObjectField> fields =
            FreightTM__Load__c.SObjectType.getDescribe().fields.getMap();
        if (fields.containsKey('AutoFill_Status__c')) {
            loadRecord.put('AutoFill_Status__c', 'Draft');
        }
        if (fields.containsKey('AutoFill_Source__c')) {
            loadRecord.put('AutoFill_Source__c', 'Manual Upload');
        }

        AutoFillSafeDml.insertRecord(loadRecord);
        return loadRecord;
    }

    @IsTest
    static void guardClausesDoNotQueueWork() {
        FreightLoadSyncHandler.bypassForTests = true;
        AutoFillRejectedLoadDeleteService.alreadyQueued = false;

        AutoFillRejectedLoadDeleteService.enqueueRejectedLoads(null, null);
        AutoFillRejectedLoadDeleteService.enqueueRejectedLoads(
            new List<FreightTM__Load__c>(),
            null
        );
        AutoFillRejectedLoadDeleteService.enqueueRejectedLoads(
            new List<FreightTM__Load__c>{
                null,
                new FreightTM__Load__c(AutoFill_Status__c = 'Rejected')
            },
            null
        );

        FreightTM__Load__c storedLoad = createDraftLoad();
        FreightTM__Load__c unchanged = new FreightTM__Load__c(
            Id = storedLoad.Id,
            AutoFill_Status__c = 'Rejected'
        );
        AutoFillRejectedLoadDeleteService.enqueueRejectedLoads(
            new List<FreightTM__Load__c>{ unchanged },
            new Map<Id, FreightTM__Load__c>{
                unchanged.Id => new FreightTM__Load__c(
                    Id = unchanged.Id,
                    AutoFill_Status__c = 'Rejected'
                )
            }
        );

        Integer queueableCountBeforeGuard = Limits.getQueueableJobs();
        AutoFillRejectedLoadDeleteService.alreadyQueued = true;
        AutoFillRejectedLoadDeleteService.enqueueRejectedLoads(
            new List<FreightTM__Load__c>{ unchanged },
            null
        );

        System.assertEquals(
            queueableCountBeforeGuard,
            Limits.getQueueableJobs()
        );
    }

    @IsTest
    static void transitionToRejectedQueuesAndDeletesLoad() {
        FreightTM__Load__c loadRecord = createDraftLoad();
        AutoFillRejectedLoadDeleteService.alreadyQueued = false;

        FreightTM__Load__c oldLoad = new FreightTM__Load__c(Id = loadRecord.Id);
        oldLoad.put('AutoFill_Status__c', 'Draft');
        FreightTM__Load__c rejectedLoad = new FreightTM__Load__c(Id = loadRecord.Id);
        rejectedLoad.put('AutoFill_Status__c', 'Rejected');

        // Persist the rejected status without allowing the update trigger to
        // queue the same deletion before this method is exercised directly.
        AutoFillRejectedLoadDeleteService.alreadyQueued = true;
        loadRecord.put('AutoFill_Status__c', 'Rejected');
        update loadRecord;
        AutoFillRejectedLoadDeleteService.alreadyQueued = false;

        Test.startTest();
        AutoFillRejectedLoadDeleteService.enqueueRejectedLoads(
            new List<FreightTM__Load__c>{ rejectedLoad },
            new Map<Id, FreightTM__Load__c>{ loadRecord.Id => oldLoad }
        );
        System.assertEquals(1, Limits.getQueueableJobs());
        Test.stopTest();

        List<FreightTM__Load__c> deletedLoads = [
            SELECT Id, IsDeleted
            FROM FreightTM__Load__c
            WHERE Id = :loadRecord.Id
            ALL ROWS
        ];
        System.assertEquals(1, deletedLoads.size());
        System.assertEquals(true, deletedLoads[0].IsDeleted);
    }

    @IsTest
    static void queueableHandlesNullEmptyMissingAndRejectedRecords() {
        FreightTM__Load__c draftLoad = createDraftLoad();

        new AutoFillRejectedLoadDeleteService.DeleteRejectedAutoFillLoadsQueueable(
            null
        ).execute(null);
        new AutoFillRejectedLoadDeleteService.DeleteRejectedAutoFillLoadsQueueable(
            new Set<Id>()
        ).execute(null);
        new AutoFillRejectedLoadDeleteService.DeleteRejectedAutoFillLoadsQueueable(
            new Set<Id>{ draftLoad.Id }
        ).execute(null);

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM FreightTM__Load__c
                WHERE Id = :draftLoad.Id
            ]
        );

        AutoFillRejectedLoadDeleteService.alreadyQueued = true;
        draftLoad.put('AutoFill_Status__c', 'Rejected');
        update draftLoad;
        AutoFillRejectedLoadDeleteService.alreadyQueued = false;

        new AutoFillRejectedLoadDeleteService.DeleteRejectedAutoFillLoadsQueueable(
            new Set<Id>{ draftLoad.Id }
        ).execute(null);

        List<FreightTM__Load__c> deletedLoads = [
            SELECT Id, IsDeleted
            FROM FreightTM__Load__c
            WHERE Id = :draftLoad.Id
            ALL ROWS
        ];
        System.assertEquals(true, deletedLoads[0].IsDeleted);
    }
}