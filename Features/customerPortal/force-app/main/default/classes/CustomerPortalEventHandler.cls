public without sharing class CustomerPortalEventHandler {
    public static void handleAfterInsert(List<Customer_Portal_Action__e> events) {
        if (events == null || events.isEmpty()) return;

        Map<Id, Customer_Portal_Session__c> sessionsToUpdate = new Map<Id, Customer_Portal_Session__c>();
        List<FreightTM__Load__c> loadsToUpdate = new List<FreightTM__Load__c>();
        List<Task> tasksToInsert = new List<Task>();

        for (Customer_Portal_Action__e evt : events) {
            Id sessionId = safeId(evt.Session_Id__c);
            Id loadId = safeId(evt.Load_Id__c);
            Id accountId = safeId(evt.Account_Id__c);

            if (sessionId != null && evt.Action_Name__c == 'PORTAL_OPENED') {
                Customer_Portal_Session__c sessionUpdate = new Customer_Portal_Session__c(Id = sessionId);
                sessionUpdate.Last_Opened__c = evt.Event_Time__c == null ? System.now() : evt.Event_Time__c;
                sessionUpdate.Last_User_Agent__c = evt.User_Agent__c;
                sessionsToUpdate.put(sessionId, sessionUpdate);
            }

            if (loadId != null && evt.Action_Name__c == 'CONFIRM_DELIVERY') {
                loadsToUpdate.add(new FreightTM__Load__c(
                    Id = loadId,
                    FreightTM__Status__c = 'Delivered',
                    FreightTM__Delivery_Departure__c = System.now()
                ));
            }

            if (loadId != null && evt.Action_Name__c == 'POD_UPLOADED') {
                loadsToUpdate.add(new FreightTM__Load__c(
                    Id = loadId,
                    POD_Received__c = true
                ));
            }

            if (evt.Action_Name__c != 'DOCUMENT_VIEWED' && evt.Action_Name__c != 'PORTAL_OPENED') {
                Task task = new Task();
                task.Subject = 'Customer Portal: ' + evt.Action_Name__c;
                task.Status = 'Not Started';
                task.Priority = evt.Action_Name__c == 'DISPUTE_INVOICE' ? 'High' : 'Normal';
                task.ActivityDate = Date.today();
                task.Description = buildTaskDescription(evt);
                if (loadId != null) task.WhatId = loadId;
                else if (accountId != null) task.WhatId = accountId;
                tasksToInsert.add(task);
            }
        }

        if (!sessionsToUpdate.isEmpty()) {
            try { update sessionsToUpdate.values(); } catch (Exception ex) { System.debug('Session update failed: ' + ex.getMessage()); }
        }
        if (!loadsToUpdate.isEmpty()) {
            try { update loadsToUpdate; } catch (Exception ex) { System.debug('Load update failed: ' + ex.getMessage()); }
        }
        if (!tasksToInsert.isEmpty()) {
            try { insert tasksToInsert; } catch (Exception ex) { System.debug('Task insert failed: ' + ex.getMessage()); }
        }
    }

    private static String buildTaskDescription(Customer_Portal_Action__e evt) {
        List<String> lines = new List<String>();
        lines.add('Action: ' + evt.Action_Name__c);
        if (!String.isBlank(evt.Account_Id__c)) lines.add('Account Id: ' + evt.Account_Id__c);
        if (!String.isBlank(evt.Contact_Id__c)) lines.add('Contact Id: ' + evt.Contact_Id__c);
        if (!String.isBlank(evt.Load_Id__c)) lines.add('Load Id: ' + evt.Load_Id__c);
        if (!String.isBlank(evt.Message__c)) lines.add('Message: ' + evt.Message__c);
        if (!String.isBlank(evt.File_Name__c)) lines.add('File: ' + evt.File_Name__c);
        if (!String.isBlank(evt.Source__c)) lines.add('Source: ' + evt.Source__c);
        return String.join(lines, '\n');
    }

    private static Id safeId(String value) {
        if (String.isBlank(value)) return null;
        try { return (Id)value; } catch (Exception ex) { return null; }
    }
}