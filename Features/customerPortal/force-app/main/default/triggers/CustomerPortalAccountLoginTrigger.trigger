trigger CustomerPortalAccountLoginTrigger on Account (
    before insert,
    before update,
    after insert,
    after update
) {
    if (Trigger.isBefore) {
        CustomerPortalCredentialService.applyAccountLoginFields(
            Trigger.new,
            Trigger.isUpdate ? Trigger.oldMap : null
        );
    }

    if (Trigger.isAfter) {
        CustomerPortalCredentialEmailService.sendWhenCredentialsChanged(
            Trigger.new,
            Trigger.isUpdate ? Trigger.oldMap : null
        );
    }
}