public with sharing class DriverPortalGenerateLinkController {
    private final ApexPages.StandardController standardController;
    public String generatedLink { get; private set; }

    public DriverPortalGenerateLinkController(
        ApexPages.StandardController standardController
    ) {
        this.standardController = standardController;
    }

    public PageReference generateAndReturn() {
        Id loadId = standardController.getId();

        try {
            DriverPortalLinkAdminController.LinkResponse response =
                DriverPortalLinkAdminController.generateOrRefreshInternal(loadId);

            generatedLink = response != null
                ? response.portalLink
                : null;

            ApexPages.addMessage(
                new ApexPages.Message(
                    ApexPages.Severity.CONFIRM,
                    'Driver Portal link generated successfully.'
                )
            );

            PageReference returnPage = new PageReference('/' + loadId);
            returnPage.setRedirect(true);
            return returnPage;
        } catch (Exception errorValue) {
            ApexPages.addMessage(
                new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    errorValue.getMessage()
                )
            );
            return null;
        }
    }
}
