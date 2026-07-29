public without sharing class HighwaySendRateConVFController {
    public Id loadId { get; set; }
    public String message { get; set; }
    public Boolean success { get; set; }

    public String selectedTargetEmail { get; set; }
    public List<SelectOption> carrierEmailOptions { get; set; }

    public HighwaySendRateConVFController() {
        loadId = ApexPages.currentPage().getParameters().get('id');
        success = false;
        message = null;
        selectedTargetEmail = null;
        carrierEmailOptions = new List<SelectOption>();

        loadCarrierEmails();
    }

    private void loadCarrierEmails() {
        carrierEmailOptions.clear();

        carrierEmailOptions.add(
            new SelectOption('', '-- Send without target email --')
        );

        if (loadId == null) {
            return;
        }

        List<FreightTM__Load__c> loads = [
            SELECT Id, Highway_Carrier_Contact_Emails__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];

        if (loads.isEmpty()) {
            return;
        }

        String emailsText = loads[0].Highway_Carrier_Contact_Emails__c;

        if (String.isBlank(emailsText)) {
            return;
        }

        Set<String> seenLower = new Set<String>();

        for (String rawEmail : emailsText.split(',')) {
            String email = rawEmail == null ? null : rawEmail.trim();

            if (String.isBlank(email)) {
                continue;
            }

            String emailLower = email.toLowerCase();

            if (seenLower.contains(emailLower)) {
                continue;
            }

            seenLower.add(emailLower);
            carrierEmailOptions.add(new SelectOption(email, email));
        }
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

            message = HighwayLoadService.sendRateConfirmationFromVF(
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

            System.debug('VF send error: ' + e.getMessage());
            System.debug('VF send stack: ' + e.getStackTraceString());
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
