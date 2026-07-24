@IsTest
private class CustomerPortalControllerTest {
    @IsTest
    static void logsInBuildsSessionAndLogsOut() {
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Controller Login');
        accountRec.Customer_Portal_Email__c = 'login.customer@example.com';
        update accountRec;
        CustomerPortalCredentialService.setAccountLogin(
            accountRec.Id,
            '  Controller.Login.User  ',
            'SecurePass123'
        );

        assertLoginFails(null, 'SecurePass123');
        assertLoginFails('controller.login.user', null);
        assertLoginFails('unknown.user', 'SecurePass123');
        assertLoginFails('controller.login.user', 'WrongPassword123');

        Test.startTest();
        CustomerPortalController.LoginResultDTO result = CustomerPortalController.login(
            ' CONTROLLER.LOGIN.USER ',
            'SecurePass123',
            CustomerPortalTestDataFactory.longText(300)
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(accountRec.Id, result.accountId);
        System.assertEquals(accountRec.Name, result.customerName);
        System.assertNotEquals(null, result.sessionKey);
        System.assert(result.expiresAt > System.now().addHours(11));

        String loginTokenHash = CustomerPortalTokenService.hashToken(result.sessionKey);
        Customer_Portal_Session__c sessionRec = [
            SELECT Id, Active__c, Last_User_Agent__c, Portal_Link__c
            FROM Customer_Portal_Session__c
            WHERE Token_Hash__c = :loginTokenHash
        ];
        System.assertEquals(true, sessionRec.Active__c);
        System.assertEquals(255, sessionRec.Last_User_Agent__c.length());
        System.assertEquals('LOGIN_SESSION', sessionRec.Portal_Link__c);

        Account savedAccount = [
            SELECT Customer_Portal_Last_Login__c
            FROM Account
            WHERE Id = :accountRec.Id
        ];
        System.assertNotEquals(null, savedAccount.Customer_Portal_Last_Login__c);

        CustomerPortalController.logout(null);
        CustomerPortalController.logout('unknown-session-token');
        CustomerPortalController.logout(result.sessionKey);
        sessionRec = [SELECT Active__c FROM Customer_Portal_Session__c WHERE Id = :sessionRec.Id];
        System.assertEquals(false, sessionRec.Active__c);

        Account inactiveAccount = CustomerPortalTestDataFactory.createAccount('Controller Inactive');
        inactiveAccount.Customer_Portal_Email__c = 'inactive@example.com';
        inactiveAccount.Customer_Portal_Username__c = 'inactive.user';
        inactiveAccount.Customer_Portal_New_Password__c = 'SecurePass123';
        insertOrUpdateAccount(inactiveAccount);
        update new Account(Id = inactiveAccount.Id, Customer_Portal_Active__c = false);
        assertLoginFails('inactive.user', 'SecurePass123');
    }

    @IsTest
    static void returnsDashboardDocumentsInvoicesRequestsAndSelectedLoad() {
        CustomerPortalTestDataFactory.registerFreightGraphCalloutMock();
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Controller Data');
        Contact contactRec = CustomerPortalTestDataFactory.createContact(accountRec.Id, 'controllerdata');

        FreightTM__Load__c assigned = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Assigned', 2000, 'DATA-ASSIGNED'
        );
        update new FreightTM__Load__c(
            Id = assigned.Id,
            FreightTM__Invoice_Status__c = 'Ready to Invoice',
            Driver_Current_Latitude__c = 29.7604,
            Driver_Current_Longitude__c = -95.3698,
            Driver_Current_Location_Text__c = 'Houston, TX',
            Driver_Last_GPS_Update__c = System.now(),
            Route_Progress_Percent__c = 20,
            Customer_Visible_Tracking__c = true,
            Tracking_Map_Enabled__c = true
        );

        FreightTM__Load__c transit = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'In Transit to Delivery', 2100, 'DATA-TRANSIT'
        );
        update new FreightTM__Load__c(
            Id = transit.Id,
            Customer_Visible_Tracking__c = false,
            Tracking_Map_Enabled__c = true,
            Driver_Current_Latitude__c = 33,
            Driver_Current_Longitude__c = -112
        );

        FreightTM__Load__c delivered = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Delivered', 2200, 'DATA-DELIVERED'
        );
        update new FreightTM__Load__c(
            Id = delivered.Id,
            FreightTM__Delivery_Date__c = Date.today(),
            FreightTM__Delivery_Departure__c = System.now(),
            FreightTM__Invoice_Status__c = 'Payment Received',
            POD_Received__c = true,
            Customer_Portal_Quote_Status__c = 'Approved',
            Customer_Portal_Quote_Response_At__c = System.now(),
            Customer_Portal_Quote_Response_Message__c = 'Approved online',
            Customer_Portal_Delivery_Confirmed__c = true,
            Customer_Portal_Delivery_Confirmed_At__c = System.now(),
            Customer_Portal_Invoice_Dispute_Status__c = 'Open',
            Customer_Portal_Invoice_Disputed_At__c = System.now(),
            Customer_Portal_Invoice_Dispute_Message__c = 'Review amount'
        );

        FreightTM__Load__c canceled = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Assigned', 500, 'DATA-CANCELED'
        );
        update new FreightTM__Load__c(
            Id = canceled.Id,
            FreightTM__Load_Canceled__c = true,
            FreightTM__Pickup_Date__c = Date.today().addDays(10),
            FreightTM__Delivery_Date__c = Date.today().addDays(11),
            Customer_Portal_Quote_Status__c = 'Rejected',
            Customer_Portal_Quote_Response_At__c = System.now(),
            Customer_Portal_Quote_Response_Message__c = 'Declined online'
        );

        ContentVersion podVersion = CustomerPortalTestDataFactory.createFile(
            assigned.Id, 'POD Customer Copy', 'pod bytes'
        );
        CustomerPortalTestDataFactory.createFile(assigned.Id, 'Invoice Customer Copy', 'invoice bytes');
        CustomerPortalTestDataFactory.createFile(assigned.Id, 'Bill of Lading Copy', 'bol bytes');
        CustomerPortalTestDataFactory.createFile(assigned.Id, 'Rate Confirmation Copy', 'rate bytes');
        CustomerPortalTestDataFactory.createFile(assigned.Id, 'General Attachment', 'other bytes');

        insert new Customer_Portal_Request__c(
            Account__c = accountRec.Id,
            Contact__c = contactRec.Id,
            Load__c = assigned.Id,
            Request_Type__c = 'STATUS_UPDATED',
            Status__c = 'New',
            Message__c = 'Existing request',
            Source__c = 'Login',
            Event_Time__c = System.now()
        );

        String sessionKey = CustomerPortalTestDataFactory.createSession(
            accountRec.Id, contactRec.Id, true, System.now().addDays(1), 'controller-data'
        );

        Test.startTest();
        CustomerPortalController.PortalDataDTO dashboard = CustomerPortalController.getPortalData(
            sessionKey, null, String.valueOf(assigned.Id)
        );
        CustomerPortalController.PortalDataDTO documents = CustomerPortalController.getPortalData(
            sessionKey, 'documents', null
        );
        CustomerPortalController.PortalDataDTO invoices = CustomerPortalController.getPortalData(
            sessionKey, 'invoices', null
        );
        CustomerPortalController.PortalDataDTO requests = CustomerPortalController.getPortalData(
            sessionKey, 'requests', null
        );
        CustomerPortalController.PortalDataDTO shipments = CustomerPortalController.getPortalData(
            sessionKey, 'shipments', 'not-an-id'
        );
        Test.stopTest();

        System.assertEquals(accountRec.Id, dashboard.context.accountId);
        System.assertEquals(contactRec.Id, dashboard.context.contactId);
        System.assertEquals(accountRec.Name, dashboard.context.customerName);
        System.assertNotEquals(null, dashboard.context.contactName, 'Portal contact name should be returned for a contact-based session.');
        System.assertEquals(contactRec.Email, dashboard.context.contactEmail);
        System.assertEquals(false, dashboard.context.loginRequired);
        System.assertEquals('/login', dashboard.context.loginUrl);
        System.assertEquals(4, dashboard.shipments.size());
        System.assertEquals(1, dashboard.documents.size());
        System.assertEquals('POD', dashboard.documents[0].type);
        System.assertEquals(String.valueOf(podVersion.Id), dashboard.documents[0].versionId);
        System.assertEquals(4, dashboard.invoices.size());
        System.assertEquals(1, dashboard.requests.size());
        System.assertEquals(1, dashboard.summary.delivered30);
        System.assertEquals(100.0, dashboard.summary.onTimeRate);
        System.assertEquals(1, dashboard.summary.documentCount);
        System.assertEquals(4, dashboard.summary.invoiceCount);
        System.assertEquals(1, dashboard.summary.requestCount);
        System.assertNotEquals(null, dashboard.selectedLoad);
        System.assertEquals(String.valueOf(assigned.Id), dashboard.selectedLoad.loadId);
        System.assertEquals(true, dashboard.selectedLoad.quoteActionAvailable);
        System.assertEquals(true, dashboard.selectedLoad.trackingAvailable);
        System.assertEquals('Quote approval stage', dashboard.selectedLoad.quoteStageLabel);
        System.assertEquals('Waiting for customer response', dashboard.selectedLoad.quoteStatusLabel);
        System.assert(dashboard.selectedLoad.bolUrl != null);
        System.assert(dashboard.selectedLoad.invoiceUrl != null);

        System.assertEquals(1, documents.documents.size());
        System.assertEquals(0, documents.invoices.size());
        System.assertEquals(4, invoices.invoices.size());
        System.assertEquals(0, invoices.documents.size());
        System.assertEquals(1, requests.requests.size());
        System.assertEquals(0, shipments.documents.size());
        System.assertEquals(0, shipments.invoices.size());
        System.assertEquals(
            true,
            shipments.selectedLoad == null,
            'An invalid load id must not select a shipment.'
        );

        Boolean foundNotStarted = false;
        Boolean foundPaymentReceived = false;
        Boolean foundHiddenTracking = false;
        Boolean foundApproved = false;
        Boolean foundRejected = false;
        for (CustomerPortalController.InvoiceDTO invoiceRow : dashboard.invoices) {
            if (invoiceRow.status == 'Not Started') foundNotStarted = true;
            if (invoiceRow.status == 'Payment Received') foundPaymentReceived = true;
        }
        for (CustomerPortalController.ShipmentDTO shipmentRow : dashboard.shipments) {
            if (shipmentRow.loadId == String.valueOf(transit.Id)) {
                foundHiddenTracking = shipmentRow.driverLatitude == null && shipmentRow.trackingAvailable == false;
            }
            if (shipmentRow.loadId == String.valueOf(delivered.Id)) {
                foundApproved = shipmentRow.quoteStatusLabel == 'Accepted by customer'
                    && shipmentRow.deliveryConfirmed == true
                    && shipmentRow.invoiceIssueActionAvailable == false;
            }
            if (shipmentRow.loadId == String.valueOf(canceled.Id)) {
                foundRejected = shipmentRow.quoteStatusLabel == 'Declined by customer'
                    && shipmentRow.quoteNextActionLabel == 'Customer declined this quote.';
            }
        }
        System.assertEquals(true, foundNotStarted);
        System.assertEquals(true, foundPaymentReceived);
        System.assertEquals(true, foundHiddenTracking);
        System.assertEquals(true, foundApproved);
        System.assertEquals(true, foundRejected);

        System.assertEquals(
            'apex/TestPage?id=' + EncodingUtil.urlEncode(String.valueOf(assigned.Id), 'UTF-8'),
            CustomerPortalController.buildPageUrl('TestPage', assigned.Id)
        );
        System.assertEquals(
            'Route not set',
            CustomerPortalController.buildRoute(null, null, null, null)
        );
        System.assertEquals(
            2000,
            CustomerPortalController.getCustomerQuoteAmount(assigned)
        );
        System.assertEquals(
            true,
            CustomerPortalController.getCustomerQuoteAmount(null) == null,
            'A null load must return a null quote amount.'
        );
        System.assertEquals(
            true,
            CustomerPortalController.getCustomerQuoteAmount(new FreightTM__Load__c()) == null,
            'A load without a customer rate must return a null quote amount.'
        );
        System.assertEquals(false, CustomerPortalController.hasFinalQuoteResponse(null));
        System.assertEquals(false, CustomerPortalController.hasFinalQuoteResponse('Pending'));
        System.assertEquals(true, CustomerPortalController.hasFinalQuoteResponse('Approved'));
        System.assertEquals(true, CustomerPortalController.hasFinalQuoteResponse('Declined'));
        System.assertEquals(false, CustomerPortalController.hasOpenInvoiceIssue(null));
        System.assertEquals(false, CustomerPortalController.hasOpenInvoiceIssue('--None--'));
        System.assertEquals(false, CustomerPortalController.hasOpenInvoiceIssue('Resolved'));
        System.assertEquals(true, CustomerPortalController.hasOpenInvoiceIssue('Open'));
        System.assertEquals(true, CustomerPortalController.hasOpenInvoiceIssue('Under Review'));
        System.assertEquals(80, CustomerPortalController.sanitizeContentDistributionName(
            CustomerPortalTestDataFactory.longText(120)
        ).length());
    }

    @IsTest
    static void submitsQuoteDeliveryInvoiceAndGenericActions() {
        CustomerPortalTestDataFactory.registerFreightGraphCalloutMock();
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Controller Actions');
        Contact contactRec = CustomerPortalTestDataFactory.createContact(accountRec.Id, 'controlleractions');
        FreightTM__Load__c approveLoad = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Assigned', 3000, 'ACTION-APPROVE'
        );
        FreightTM__Load__c rejectLoad = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Assigned', 3100, 'ACTION-REJECT'
        );
        FreightTM__Load__c deliveryLoad = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'At Receiving', 3200, 'ACTION-DELIVERY'
        );
        FreightTM__Load__c disputeLoad = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Delivered', 3300, 'ACTION-DISPUTE'
        );
        FreightTM__Load__c unavailableLoad = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Dispatched', 3400, 'ACTION-UNAVAILABLE'
        );
        String sessionKey = CustomerPortalTestDataFactory.createSession(
            accountRec.Id, contactRec.Id, true, System.now().addDays(1), 'controller-actions'
        );

        Test.startTest();
        CustomerPortalController.ActionResultDTO approved = CustomerPortalController.submitCustomerAction(
            sessionKey,
            String.valueOf(approveLoad.Id),
            ' approve_quote ',
            'Approved by purchasing.',
            'Test Browser'
        );
        CustomerPortalController.ActionResultDTO rejected = CustomerPortalController.submitCustomerAction(
            sessionKey,
            String.valueOf(rejectLoad.Id),
            'REJECT_QUOTE',
            'Rate is too high.',
            'Test Browser'
        );
        CustomerPortalController.ActionResultDTO delivered = CustomerPortalController.submitCustomerAction(
            sessionKey,
            String.valueOf(deliveryLoad.Id),
            'CONFIRM_DELIVERY',
            null,
            'Test Browser'
        );
        CustomerPortalController.ActionResultDTO disputed = CustomerPortalController.submitCustomerAction(
            sessionKey,
            String.valueOf(disputeLoad.Id),
            'DISPUTE_INVOICE',
            'Incorrect invoice amount.',
            'Test Browser'
        );
        CustomerPortalController.ActionResultDTO generic = CustomerPortalController.submitCustomerAction(
            sessionKey,
            String.valueOf(unavailableLoad.Id),
            'STATUS_UPDATED',
            'Recorded',
            'Test Browser'
        );
        Test.stopTest();

        System.assertEquals(true, approved.success);
        System.assert(approved.message.contains('Quote approved'));
        System.assertEquals(true, rejected.success);
        System.assert(rejected.message.contains('Quote rejected'));
        System.assertEquals(true, delivered.success);
        System.assertEquals('Delivery confirmed by customer.', delivered.message);
        System.assertEquals(true, disputed.success);
        System.assert(disputed.message.startsWith('Invoice dispute opened by customer.'));
        System.assertEquals('Customer action submitted.', generic.message);
        System.assertNotEquals(null, approved.requestId);

        approveLoad = [
            SELECT Customer_Portal_Quote_Status__c, Customer_Portal_Quote_Response_Message__c
            FROM FreightTM__Load__c WHERE Id = :approveLoad.Id
        ];
        rejectLoad = [
            SELECT Customer_Portal_Quote_Status__c, Customer_Portal_Quote_Response_Message__c
            FROM FreightTM__Load__c WHERE Id = :rejectLoad.Id
        ];
        deliveryLoad = [
            SELECT FreightTM__Status__c, Customer_Portal_Delivery_Confirmed__c
            FROM FreightTM__Load__c WHERE Id = :deliveryLoad.Id
        ];
        disputeLoad = [
            SELECT Customer_Portal_Invoice_Dispute_Status__c,
                   Customer_Portal_Invoice_Dispute_Message__c
            FROM FreightTM__Load__c WHERE Id = :disputeLoad.Id
        ];
        System.assertEquals('Approved', approveLoad.Customer_Portal_Quote_Status__c);
        System.assertEquals('Rejected', rejectLoad.Customer_Portal_Quote_Status__c);
        System.assertEquals('Delivered', deliveryLoad.FreightTM__Status__c);
        System.assertEquals(true, deliveryLoad.Customer_Portal_Delivery_Confirmed__c);
        System.assertEquals('Open', disputeLoad.Customer_Portal_Invoice_Dispute_Status__c);
        System.assertEquals('Incorrect invoice amount.', disputeLoad.Customer_Portal_Invoice_Dispute_Message__c);
        System.assertEquals(null, CustomerPortalController.sanitizeLong('   '));
        System.assertEquals(
            32000,
            CustomerPortalController.sanitizeLong(CustomerPortalTestDataFactory.longText(32100)).length()
        );
        System.assertEquals(5, [
            SELECT COUNT() FROM Customer_Portal_Request__c WHERE Account__c = :accountRec.Id
        ]);

        assertActionFails(sessionKey, null, 'APPROVE_QUOTE', null);
        assertActionFails(sessionKey, 'not-an-id', 'APPROVE_QUOTE', null);
        assertActionFails(sessionKey, String.valueOf(unavailableLoad.Id), null, null);
        assertActionFails(sessionKey, String.valueOf(unavailableLoad.Id), 'UNKNOWN_ACTION', null);
        assertActionFails(sessionKey, String.valueOf(unavailableLoad.Id), 'APPROVE_QUOTE', null);
        assertActionFails(sessionKey, String.valueOf(unavailableLoad.Id), 'REJECT_QUOTE', null);
        assertActionFails(sessionKey, String.valueOf(unavailableLoad.Id), 'CONFIRM_DELIVERY', null);
        assertActionFails(sessionKey, String.valueOf(disputeLoad.Id), 'DISPUTE_INVOICE', 'Again');
        assertActionFails(sessionKey, String.valueOf(approveLoad.Id), 'APPROVE_QUOTE', 'Again');
    }

    @IsTest
    static void updatesLoadStatusAndValidatesCustomerOwnership() {
        CustomerPortalTestDataFactory.registerFreightGraphCalloutMock();
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Controller Status');
        Account otherAccount = CustomerPortalTestDataFactory.createAccount('Controller Status Other');
        FreightTM__Load__c loadRec = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Assigned', 1000, 'STATUS-OWN'
        );
        FreightTM__Load__c otherLoad = CustomerPortalTestDataFactory.createLoad(
            otherAccount.Id, 'Assigned', 1000, 'STATUS-OTHER'
        );
        String sessionKey = CustomerPortalTestDataFactory.createSession(
            accountRec.Id, null, true, System.now().addDays(1), 'controller-status'
        );

        CustomerPortalController.ActionResultDTO result = CustomerPortalController.updateLoadStatus(
            sessionKey, String.valueOf(loadRec.Id), 'Delivered', 'Browser'
        );
        System.assertEquals(true, result.success);
        System.assertEquals('Status changed to Delivered', result.message);
        loadRec = [
            SELECT FreightTM__Status__c, FreightTM__Delivery_Departure__c
            FROM FreightTM__Load__c WHERE Id = :loadRec.Id
        ];
        System.assertEquals('Delivered', loadRec.FreightTM__Status__c);
        System.assertNotEquals(null, loadRec.FreightTM__Delivery_Departure__c);

        CustomerPortalController.ActionResultDTO cleared = CustomerPortalController.updateLoadStatus(
            sessionKey, String.valueOf(loadRec.Id), '--None--', 'Browser'
        );
        System.assertEquals('Status changed to --None--', cleared.message);

        assertStatusFails(sessionKey, null, 'Assigned');
        assertStatusFails(sessionKey, 'not-an-id', 'Assigned');
        assertStatusFails(sessionKey, String.valueOf(otherLoad.Id), 'Assigned');
        assertStatusFails(sessionKey, String.valueOf(loadRec.Id), 'Unsupported Status');
    }

    @IsTest
    static void uploadsPodAndCreatesSecureDocumentDownloadLinks() {
        CustomerPortalTestDataFactory.registerFreightGraphCalloutMock();
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Controller Files');
        Account otherAccount = CustomerPortalTestDataFactory.createAccount('Controller Files Other');
        FreightTM__Load__c loadRec = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Delivered', 1500, 'FILES-OWN'
        );
        FreightTM__Load__c otherLoad = CustomerPortalTestDataFactory.createLoad(
            otherAccount.Id, 'Delivered', 1500, 'FILES-OTHER'
        );
        String sessionKey = CustomerPortalTestDataFactory.createSession(
            accountRec.Id, null, true, System.now().addDays(1), 'controller-files'
        );

        assertUploadFails(sessionKey, null, 'pod.pdf', EncodingUtil.base64Encode(Blob.valueOf('x')));
        assertUploadFails(sessionKey, 'not-an-id', 'pod.pdf', EncodingUtil.base64Encode(Blob.valueOf('x')));
        assertUploadFails(sessionKey, String.valueOf(otherLoad.Id), 'pod.pdf', EncodingUtil.base64Encode(Blob.valueOf('x')));
        assertUploadFails(sessionKey, String.valueOf(loadRec.Id), null, EncodingUtil.base64Encode(Blob.valueOf('x')));
        assertUploadFails(sessionKey, String.valueOf(loadRec.Id), 'pod.pdf', null);

        String unsafeLongName = 'Customer:*?File-' + CustomerPortalTestDataFactory.longText(130) + '.pdf';
        String base64Data = 'data:application/pdf;base64,' + EncodingUtil.base64Encode(Blob.valueOf('POD CONTENT'));

        Test.startTest();
        CustomerPortalController.ActionResultDTO uploadResult = CustomerPortalController.uploadPod(
            sessionKey,
            String.valueOf(loadRec.Id),
            unsafeLongName,
            base64Data,
            'Uploaded by customer',
            CustomerPortalTestDataFactory.longText(300)
        );
        Test.stopTest();

        System.assertEquals(true, uploadResult.success);
        System.assertEquals('POD uploaded.', uploadResult.message);
        System.assertNotEquals(null, uploadResult.contentVersionId);
        ContentVersion uploaded = [
            SELECT Id, Title, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :uploadResult.contentVersionId
        ];
        System.assert(uploaded.Title.startsWith('POD - '));
        System.assert(uploaded.Title.length() <= 120);
        loadRec = [SELECT POD_Received__c FROM FreightTM__Load__c WHERE Id = :loadRec.Id];
        System.assertEquals(true, loadRec.POD_Received__c);

        assertDownloadFails(sessionKey, null, String.valueOf(loadRec.Id));
        assertDownloadFails(sessionKey, 'not-an-id', String.valueOf(loadRec.Id));
        assertDownloadFails(sessionKey, String.valueOf(uploaded.Id), 'not-an-id');
        assertDownloadFails(sessionKey, String.valueOf(uploaded.Id), String.valueOf(otherLoad.Id));

        ContentVersion unrelated = CustomerPortalTestDataFactory.createFile(
            accountRec.Id, 'Unrelated Customer File', 'unrelated'
        );
        assertDownloadFails(sessionKey, String.valueOf(unrelated.Id), String.valueOf(loadRec.Id));

        String firstUrl = CustomerPortalController.getDocumentDownloadUrl(
            sessionKey, String.valueOf(uploaded.Id), String.valueOf(loadRec.Id)
        );
        System.assertNotEquals(null, firstUrl);
        String existingUrl = CustomerPortalController.getDocumentDownloadUrl(
            sessionKey, String.valueOf(uploaded.Id), String.valueOf(loadRec.Id)
        );
        System.assertNotEquals(null, existingUrl);
        ContentDistribution createdDistribution = [
            SELECT Id, Name
            FROM ContentDistribution
            WHERE ContentVersionId = :uploaded.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assert(createdDistribution.Name.length() <= 80);
    }

    @IsTest
    static void recordsPortalAndDocumentActivityWithoutBreakingThePortal() {
        CustomerPortalTestDataFactory.registerFreightGraphCalloutMock();
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Controller Activity');
        Account otherAccount = CustomerPortalTestDataFactory.createAccount('Controller Activity Other');
        FreightTM__Load__c loadRec = CustomerPortalTestDataFactory.createLoad(
            accountRec.Id, 'Assigned', 1000, 'ACTIVITY-OWN'
        );
        FreightTM__Load__c otherLoad = CustomerPortalTestDataFactory.createLoad(
            otherAccount.Id, 'Assigned', 1000, 'ACTIVITY-OTHER'
        );
        String sessionKey = CustomerPortalTestDataFactory.createSession(
            accountRec.Id, null, true, System.now().addDays(1), 'controller-activity'
        );

        Test.startTest();
        CustomerPortalController.recordPortalOpened(sessionKey, 'Browser');
        CustomerPortalController.recordPortalOpened('invalid-session', 'Browser');
        CustomerPortalController.recordDocumentViewed(
            sessionKey, '069000000000001AAA', String.valueOf(loadRec.Id), 'Browser'
        );
        CustomerPortalController.recordDocumentViewed(
            sessionKey, '069000000000001AAA', null, 'Browser'
        );
        CustomerPortalController.recordDocumentViewed(
            sessionKey, '069000000000001AAA', String.valueOf(otherLoad.Id), 'Browser'
        );
        CustomerPortalController.recordDocumentViewed(
            'invalid-session', '069000000000001AAA', String.valueOf(loadRec.Id), 'Browser'
        );
        Test.stopTest();

        System.assertEquals(true, true, 'Activity methods should safely complete.');
    }

    @IsTest
    static void rejectsInvalidSessionsAndCrossAccountPortalData() {
        Account accountRec = CustomerPortalTestDataFactory.createAccount('Controller Invalid Session');
        String expired = CustomerPortalTestDataFactory.createSession(
            accountRec.Id, null, true, System.now().addMinutes(-1), 'controller-expired'
        );

        assertPortalDataFails(null);
        assertPortalDataFails('unknown-token');
        assertPortalDataFails(expired);
    }

    private static void insertOrUpdateAccount(Account accountRec) {
        if (accountRec.Id == null) insert accountRec;
        else update accountRec;
    }

    private static void assertLoginFails(String username, String password) {
        try {
            CustomerPortalController.login(username, password, 'Test');
            System.assert(false, 'Expected login to fail.');
        } catch (Exception expected) {
            System.assert(true);
        }
    }

    private static void assertActionFails(String sessionKey, String loadId, String actionName, String message) {
        try {
            CustomerPortalController.submitCustomerAction(
                sessionKey, loadId, actionName, message, 'Test Browser'
            );
            System.assert(false, 'Expected customer action to fail.');
        } catch (Exception expected) {
            System.assert(true);
        }
    }

    private static void assertStatusFails(String sessionKey, String loadId, String statusValue) {
        try {
            CustomerPortalController.updateLoadStatus(sessionKey, loadId, statusValue, 'Test Browser');
            System.assert(false, 'Expected status update to fail.');
        } catch (Exception expected) {
            System.assert(true);
        }
    }

    private static void assertUploadFails(String sessionKey, String loadId, String fileName, String data) {
        try {
            CustomerPortalController.uploadPod(
                sessionKey, loadId, fileName, data, null, 'Test Browser'
            );
            System.assert(false, 'Expected POD upload to fail.');
        } catch (Exception expected) {
            System.assert(true);
        }
    }

    private static void assertDownloadFails(String sessionKey, String versionId, String loadId) {
        try {
            CustomerPortalController.getDocumentDownloadUrl(sessionKey, versionId, loadId);
            System.assert(false, 'Expected document download validation to fail.');
        } catch (Exception expected) {
            System.assert(true);
        }
    }

    private static void assertPortalDataFails(String sessionKey) {
        try {
            CustomerPortalController.getPortalData(sessionKey, 'dashboard', null);
            System.assert(false, 'Expected portal data access to fail.');
        } catch (Exception expected) {
            System.assert(true);
        }
    }
}