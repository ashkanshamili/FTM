trigger DriverPortalLoadTrigger on FreightTM__Load__c (
    before insert,
    before update,
    after insert,
    after update
) {
    if (Trigger.isBefore) {
        DriverLoadPortalTriggerHandler.handleBefore(
            Trigger.new,
            Trigger.oldMap,
            Trigger.isInsert,
            Trigger.isUpdate
        );
    }

    if (Trigger.isAfter) {
        DriverLoadPortalTriggerHandler.handleAfter(
            Trigger.new,
            Trigger.oldMap,
            Trigger.isInsert,
            Trigger.isUpdate
        );
    }
}
