trigger DriverPortalActionTrigger on Driver_Portal_Action__e (after insert) {
    DriverPortalActionHandler.handleAfterInsert(Trigger.new);
}