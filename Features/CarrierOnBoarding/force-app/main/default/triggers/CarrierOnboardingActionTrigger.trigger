trigger CarrierOnboardingActionTrigger on Carrier_Onboarding_Action__e (after insert) {
    CarrierOnboardingActionHandler.handleAfterInsert(Trigger.new);
}