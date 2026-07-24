@IsTest
private class CustomerPortalEventHandlerTest {
    @IsTest
    static void handlesPortalEventsAndCreatesTasks() {
        CustomerPortalTestDataFactory.registerFreightGraphCalloutMock();
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Event Success');
        FreightTM__Load__c deliveryLoad = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'At Receiving', 1400, 'EVENT-DELIVERY'
        );
        FreightTM__Load__c podLoad = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Delivered', 1500, 'EVENT-POD'
        );
        String rawToken = CustomerPortalTestDataFactory.createSession(
            accountRec.Id, null, true, System.now().addDays(1), 'event-session'
        );
        String eventTokenHash = CustomerPortalTokenService.hashToken(rawToken);
        Customer_Portal_Session__c sessionRec = [
            SELECT Id FROM Customer_Portal_Session__c
            WHERE Token_Hash__c = :eventTokenHash
        ];
        Datetime openedAt = System.now().addMinutes(-10);

        List<Customer_Portal_Action__e> events = new List<Customer_Portal_Action__e>{
            new Customer_Portal_Action__e(
                Session_Id__c = String.valueOf(sessionRec.Id),
                Account_Id__c = String.valueOf(accountRec.Id),
                Action_Name__c = 'PORTAL_OPENED',
                Event_Time__c = openedAt,
                User_Agent__c = 'Test Browser'
            ),
            new Customer_Portal_Action__e(
                Load_Id__c = String.valueOf(deliveryLoad.Id),
                Account_Id__c = String.valueOf(accountRec.Id),
                Action_Name__c = 'CONFIRM_DELIVERY',
                Message__c = 'Customer received shipment.',
                Source__c = 'Login'
            ),
            new Customer_Portal_Action__e(
                Load_Id__c = String.valueOf(podLoad.Id),
                Account_Id__c = String.valueOf(accountRec.Id),
                Action_Name__c = 'POD_UPLOADED',
                File_Name__c = 'POD.pdf',
                Source__c = 'Login'
            ),
            new Customer_Portal_Action__e(
                Account_Id__c = String.valueOf(accountRec.Id),
                Contact_Id__c = String.valueOf(accountRec.Id),
                Action_Name__c = 'DISPUTE_INVOICE',
                Message__c = 'Incorrect amount',
                File_Name__c = 'invoice.pdf',
                Source__c = 'Login'
            ),
            new Customer_Portal_Action__e(
                Account_Id__c = String.valueOf(accountRec.Id),
                Action_Name__c = 'STATUS_UPDATED',
                Message__c = 'Status changed',
                Source__c = 'Login'
            ),
            new Customer_Portal_Action__e(
                Load_Id__c = 'not-an-id',
                Account_Id__c = '',
                Session_Id__c = 'not-an-id',
                Action_Name__c = 'DOCUMENT_VIEWED'
            )
        };

        Test.startTest();
        CustomerPortalEventHandler.handleAfterInsert(null);
        CustomerPortalEventHandler.handleAfterInsert(new List<Customer_Portal_Action__e>());
        CustomerPortalEventHandler.handleAfterInsert(events);
        Test.stopTest();

        sessionRec = [
            SELECT Last_Opened__c, Last_User_Agent__c
            FROM Customer_Portal_Session__c
            WHERE Id = :sessionRec.Id
        ];
        System.assertEquals(openedAt, sessionRec.Last_Opened__c);
        System.assertEquals('Test Browser', sessionRec.Last_User_Agent__c);

        deliveryLoad = [
            SELECT FreightTM__Status__c, FreightTM__Delivery_Departure__c
            FROM FreightTM__Load__c
            WHERE Id = :deliveryLoad.Id
        ];
        System.assertEquals('Delivered', deliveryLoad.FreightTM__Status__c);
        System.assertNotEquals(null, deliveryLoad.FreightTM__Delivery_Departure__c);

        podLoad = [SELECT POD_Received__c FROM FreightTM__Load__c WHERE Id = :podLoad.Id];
        System.assertEquals(true, podLoad.POD_Received__c);

        List<Task> tasks = [
            SELECT Subject, Priority, WhatId, Description
            FROM Task
            WHERE Subject LIKE 'Customer Portal:%'
        ];
        System.assertEquals(4, tasks.size());
        Boolean foundHighPriority = false;
        Boolean foundAccountTask = false;
        for (Task taskRec : tasks) {
            if (taskRec.Subject == 'Customer Portal: DISPUTE_INVOICE') {
                foundHighPriority = taskRec.Priority == 'High';
                System.assert(taskRec.Description.contains('Incorrect amount'));
                System.assert(taskRec.Description.contains('invoice.pdf'));
            }
            if (taskRec.WhatId == accountRec.Id) foundAccountTask = true;
        }
        System.assertEquals(true, foundHighPriority);
        System.assertEquals(true, foundAccountTask);
    }

    @IsTest
    static void catchesFailedSessionLoadAndTaskDml() {
        CustomerPortalTestDataFactory.registerFreightGraphCalloutMock();
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Event Failure');
        Savepoint rollbackPoint = Database.setSavepoint();
        FreightTM__Load__c loadRec = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Assigned', 1000, 'EVENT-FAILURE'
        );
        String rawToken = CustomerPortalTestDataFactory.createSession(
            accountRec.Id, null, true, System.now().addDays(1), 'event-failure-session'
        );
        String failureTokenHash = CustomerPortalTokenService.hashToken(rawToken);
        Customer_Portal_Session__c sessionRec = [
            SELECT Id FROM Customer_Portal_Session__c
            WHERE Token_Hash__c = :failureTokenHash
        ];
        Id deletedLoadId = loadRec.Id;
        Id deletedSessionId = sessionRec.Id;
        Database.rollback(rollbackPoint);

        Customer_Portal_Action__e failureEvent = new Customer_Portal_Action__e(
            Session_Id__c = String.valueOf(deletedSessionId),
            Load_Id__c = String.valueOf(deletedLoadId),
            Account_Id__c = String.valueOf(accountRec.Id),
            Action_Name__c = 'CONFIRM_DELIVERY',
            Message__c = 'Expected DML failures'
        );

        Test.startTest();
        CustomerPortalEventHandler.handleAfterInsert(
            new List<Customer_Portal_Action__e>{ failureEvent }
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :deletedLoadId]);
    }
}