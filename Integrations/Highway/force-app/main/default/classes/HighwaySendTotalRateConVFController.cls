public without sharing class HighwaySendTotalRateConVFController {
    public Id loadId { get; set; }
    public String message { get; set; }
    public Boolean success { get; set; }

    public String selectedTargetEmail { get; set; }

    public HighwaySendTotalRateConVFController() {
        loadId = ApexPages.currentPage().getParameters().get('id');
        success = false;
        message = null;
        selectedTargetEmail = null;

        loadTargetEmail();
    }

    private void loadTargetEmail() {
        if (loadId == null) {
            return;
        }

        List<FreightTM__Load__c> loads = [
            SELECT Id, Highway_Target_Email__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];

        if (loads.isEmpty()) {
            return;
        }

        selectedTargetEmail = loads[0].Highway_Target_Email__c;
    }

    public PageReference send() {
        try {
            if (loadId == null) {
                message = 'Load Id is missing.';
                success = false;

                ApexPages.addMessage(
                    new ApexPages.Message(ApexPages.Severity.ERROR, message)
                );

                return null;
            }

            if (String.isBlank(selectedTargetEmail)) {
                message = 'Target email is required for Total Rate Confirmation.';
                success = false;

                ApexPages.addMessage(
                    new ApexPages.Message(ApexPages.Severity.ERROR, message)
                );

                return null;
            }

            message = HighwayLoadService.sendTotalRateConfirmationFromVF(
                loadId,
                selectedTargetEmail
            );

            success = true;

            ApexPages.addMessage(
                new ApexPages.Message(ApexPages.Severity.CONFIRM, message)
            );

        } catch (Exception e) {
            success = false;
            message = e.getMessage();

            if (String.isBlank(message)) {
                message = 'Unexpected error. Check debug logs.';
            }

            ApexPages.addMessage(
                new ApexPages.Message(ApexPages.Severity.ERROR, message)
            );

            System.debug('Total RC VF send error: ' + e.getMessage());
            System.debug('Total RC VF send stack: ' + e.getStackTraceString());
        }

        return null;
    }

    public PageReference goBack() {
        if (loadId == null) {
            PageReference pr = new PageReference('/lightning/o/FreightTM__Load__c/list');
            pr.setRedirect(true);
            return pr;
        }

        PageReference pr = new PageReference('/' + loadId);
        pr.setRedirect(true);
        return pr;
    }
}
