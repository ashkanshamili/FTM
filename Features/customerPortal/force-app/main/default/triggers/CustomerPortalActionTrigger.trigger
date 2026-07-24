trigger CustomerPortalActionTrigger on Customer_Portal_Action__e (after insert) {
    CustomerPortalEventHandler.handleAfterInsert(Trigger.new);
}