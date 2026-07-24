public with sharing class DriverPortalSmsController {
    private ApexPages.StandardController standardController;
    
    public FreightTM__Load__c loadRecord { get; set; }
    
    public DriverPortalSmsController(
        ApexPages.StandardController standardController
    ) {
        this.standardController = standardController;
        
        Id loadId = standardController.getId();
        
        if (loadId == null) {
            ApexPages.addMessage(
                new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    'A Load record is required.'
                )
            );
            return;
        }
        
        loadRecord = [
            SELECT Id,
            Name,
            Driver_Portal_Link__c,
            FreightTM__Driver__c,
            Driver_Phone_Number__c,
            Driver_Phone_Carrier__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];
    }
    
    public PageReference sendPortalLink() {
        if (loadRecord == null) {
            ApexPages.addMessage(
                new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    'The Load record could not be loaded.'
                )
            );
            return null;
        }
        
        if (loadRecord.FreightTM__Driver__c == null) {
            ApexPages.addMessage(
                new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    'Please select a driver.'
                )
            );
            return null;
        }
        
        if (String.isBlank(loadRecord.Driver_Phone_Number__c)) {
            ApexPages.addMessage(
                new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    'Please enter the driver phone number.'
                )
            );
            return null;
        }
        
        if (String.isBlank(loadRecord.Driver_Phone_Carrier__c)) {
            ApexPages.addMessage(
                new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    'Please select the driver phone carrier.'
                )
            );
            return null;
        }
        
        if (String.isBlank(loadRecord.Driver_Portal_Link__c)) {
            ApexPages.addMessage(
                new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    'The Driver Portal Link is blank. The message was not sent.'
                )
            );
            return null;
        }
        
        String cleanPhone = loadRecord.Driver_Phone_Number__c.replaceAll(
            '[^0-9]',
            ''
        );
        
        if (String.isBlank(cleanPhone)) {
            ApexPages.addMessage(
                new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    'Please enter a valid driver phone number.'
                )
            );
            return null;
        }
        
        try {
            // Save the values entered on the Visualforce page.
            update loadRecord;
            
            // Send asynchronously using your existing queueable class.
            System.enqueueJob(
                new DriverPortalSmsQueueable(
                    new Set<Id>{ loadRecord.Id }
                )
            );
            
            ApexPages.addMessage(
                new ApexPages.Message(
                    ApexPages.Severity.CONFIRM,
                    'The driver information was saved and the portal link was queued for sending.'
                )
            );
            
            PageReference loadPage = new PageReference(
                '/' + loadRecord.Id
            );
            loadPage.setRedirect(true);
            return loadPage;
        } catch (DmlException exceptionRecord) {
            for (Integer i = 0; i < exceptionRecord.getNumDml(); i++) {
                ApexPages.addMessage(
                    new ApexPages.Message(
                        ApexPages.Severity.ERROR,
                        exceptionRecord.getDmlMessage(i)
                    )
                );
            }
            
            return null;
        } catch (Exception exceptionRecord) {
            ApexPages.addMessage(
                new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    'The portal link could not be sent: ' +
                    exceptionRecord.getMessage()
                )
            );
            
            return null;
        }
    }
    
    public PageReference cancel() {
        String returnUrl = ApexPages.currentPage()
            .getParameters()
            .get('retURL');
        
        PageReference destination;
        
        if (String.isNotBlank(returnUrl)) {
            destination = new PageReference(returnUrl);
        } else if (loadRecord != null && loadRecord.Id != null) {
            destination = new PageReference('/' + loadRecord.Id);
        } else {
            destination = new PageReference('/');
        }
        
        destination.setRedirect(true);
        return destination;
    }
}