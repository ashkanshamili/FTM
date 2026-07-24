@IsTest
private class FtmLaneQuoteWorkspaceControllerTest {
    private class FreightGraphSyncMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            String endpoint = request == null ? null : request.getEndpoint();
            if (endpoint != null && (endpoint.endsWith('/api/auth/login') || endpoint.endsWith('/api/auth/refresh'))) {
                response.setStatusCode(200);
                response.setBody('{"token":"quote-test-token","expiresIn":3600}');
                return response;
            }

            // Load creation only needs a successful response. Omitting an Id prevents
            // the sync job from updating the Load and enqueueing a second sync job.
            response.setStatusCode(201);
            response.setBody('{}');
            return response;
        }
    }

    private static String validLoadStatus() {
        String firstActiveValue;
        for (Schema.PicklistEntry entry : FreightTM__Load__c.FreightTM__Status__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) continue;
            if (firstActiveValue == null) firstActiveValue = entry.getValue();
            if (entry.getValue() == 'Assigned') return entry.getValue();
        }
        System.assertNotEquals(null, firstActiveValue, 'FreightTM__Load__c.FreightTM__Status__c must have an active picklist value.');
        return firstActiveValue;
    }

    private static Account createAccount(String name) {
        Account accountRec = new Account(Name = name);
        insert accountRec;
        return accountRec;
    }

    private static FreightTM__Lane_Quote__c createCompleteQuote(Account accountRec, Decimal customerRate, Decimal carrierCost) {
        FreightTM__Lane_Quote__c quoteRec = new FreightTM__Lane_Quote__c(
            FreightTM__Customer__c = accountRec.Id,
            FreightTM__Pickup_City__c = 'Chicago',
            FreightTM__Pickup_State__c = 'IL',
            FreightTM__Delivery_City__c = 'Detroit',
            FreightTM__Delivery_State__c = 'MI',
            FreightTM__Estimated_Pickup_Time__c = System.now().addDays(2),
            FreightTM__Estimated_Delivery_Time__c = System.now().addDays(3),
            FreightTM__Customer_Rate__c = customerRate,
            FreightTM__Rate_to_Carrier__c = carrierCost,
            FreightTM__Weight__c = 12000,
            Equipment_Type__c = 'Dry Van',
            Pallet_Count__c = 12,
            Commodity__c = 'General freight',
            Minimum_Margin_Percent__c = 15,
            Target_Margin_Percent__c = 20
        );
        insert quoteRec;
        return quoteRec;
    }

    private static void assertAuraFailure(String expectedText, Boolean actionFailed) {
        System.assertEquals(true, actionFailed, expectedText);
    }

    @IsTest
    static void quoteLifecycleHappyPathAndDuplicateConversion() {
        Account accountRec = createAccount('FTM Quote Test Customer');
        FreightTM__Lane_Quote__c quoteRec = createCompleteQuote(accountRec, 2500, 1900);
        Test.setMock(HttpCalloutMock.class, new FreightGraphSyncMock());

        Test.startTest();
        FtmLaneQuoteWorkspaceController.QuoteDataDTO initialData = FtmLaneQuoteWorkspaceController.getQuoteData(quoteRec.Id);
        System.assertEquals(quoteRec.Id, Id.valueOf(initialData.quoteId));
        System.assertEquals('Draft', initialData.workflowStatus);

        FtmLaneQuoteWorkspaceController.ActionResultDTO calc = FtmLaneQuoteWorkspaceController.calculateQuote(quoteRec.Id);
        System.assertEquals(true, calc.success);
        System.assertNotEquals(null, calc.data.estimatedMarginPercent);
        System.assertEquals(true, calc.data.canMarkSent);
        System.assertEquals(false, calc.data.pricingLocked);

        FtmLaneQuoteWorkspaceController.ActionResultDTO sent = FtmLaneQuoteWorkspaceController.markSent(quoteRec.Id);
        System.assertEquals(true, sent.success);
        System.assertEquals('Sent', sent.data.workflowStatus);
        System.assertEquals(true, sent.data.pricingLocked);

        FtmLaneQuoteWorkspaceController.ActionResultDTO accepted = FtmLaneQuoteWorkspaceController.markAccepted(quoteRec.Id, 'Customer approved in test.');
        System.assertEquals(true, accepted.success);
        System.assertEquals(true, accepted.data.canConvertToLoad);

        FtmLaneQuoteWorkspaceController.ActionResultDTO converted = FtmLaneQuoteWorkspaceController.convertToLoad(quoteRec.Id);
        System.assertEquals(true, converted.success);
        FtmLaneQuoteWorkspaceController.ActionResultDTO duplicateConvert = FtmLaneQuoteWorkspaceController.convertToLoad(quoteRec.Id);
        System.assertEquals(true, duplicateConvert.success);
        Test.stopTest();

        FreightTM__Lane_Quote__c afterQuote = [
            SELECT Quote_Workflow_Status__c, Converted_Load__c, Estimated_Margin_Percent__c
            FROM FreightTM__Lane_Quote__c
            WHERE Id = :quoteRec.Id
        ];
        System.assertEquals('Converted to Load', afterQuote.Quote_Workflow_Status__c);
        System.assertNotEquals(null, afterQuote.Converted_Load__c);

        FreightTM__Load__c loadRec = [
            SELECT FreightTM__Lane_Quote__c, Original_Quoted_Rate__c, Original_Estimated_Cost__c, Original_Estimated_Margin__c
            FROM FreightTM__Load__c
            WHERE Id = :afterQuote.Converted_Load__c
        ];
        System.assertEquals(quoteRec.Id, loadRec.FreightTM__Lane_Quote__c);
        System.assertEquals(2500, loadRec.Original_Quoted_Rate__c);
        System.assertEquals(1900, loadRec.Original_Estimated_Cost__c);
        System.assertNotEquals(null, loadRec.Original_Estimated_Margin__c);
    }

    @IsTest
    static void approvalMovesToReadyToSendThenSent() {
        Account accountRec = createAccount('FTM Quote Approval Customer');
        FreightTM__Lane_Quote__c quoteRec = createCompleteQuote(accountRec, 1000, 950);

        Test.startTest();
        FtmLaneQuoteWorkspaceController.ActionResultDTO calc = FtmLaneQuoteWorkspaceController.calculateQuote(quoteRec.Id);
        System.assertEquals('Approval Required', calc.data.workflowStatus);
        System.assertEquals(true, calc.data.canRequestApproval);

        FtmLaneQuoteWorkspaceController.ActionResultDTO approval = FtmLaneQuoteWorkspaceController.requestApproval(quoteRec.Id, 'Low margin approval test.');
        System.assertEquals('Pending Approval', approval.data.workflowStatus);
        System.assertEquals(true, approval.data.canApprove);
        System.assertEquals(true, approval.data.pricingLocked);

        FtmLaneQuoteWorkspaceController.ActionResultDTO approved = FtmLaneQuoteWorkspaceController.approveQuote(quoteRec.Id, 'Approved in unit test.');
        System.assertEquals('Approved', approved.data.approvalStatus);
        System.assertEquals('Ready to Send', approved.data.workflowStatus);
        System.assertEquals(true, approved.data.canMarkSent);
        System.assertEquals(true, approved.data.pricingLocked);
        System.assert(approved.data.nextAction.contains('Mark'));

        FtmLaneQuoteWorkspaceController.ActionResultDTO sent = FtmLaneQuoteWorkspaceController.markSent(quoteRec.Id);
        System.assertEquals('Sent', sent.data.workflowStatus);
        Test.stopTest();

        FreightTM__Lane_Quote__c afterQuote = [
            SELECT Approval_Status__c, Approval_Required__c, Quote_Workflow_Status__c, Sent_At__c
            FROM FreightTM__Lane_Quote__c
            WHERE Id = :quoteRec.Id
        ];
        System.assertEquals('Approved', afterQuote.Approval_Status__c);
        System.assertEquals(true, afterQuote.Approval_Required__c);
        System.assertEquals('Sent', afterQuote.Quote_Workflow_Status__c);
        System.assertNotEquals(null, afterQuote.Sent_At__c);
    }

    @IsTest
    static void approvedQuoteCannotFallBackIntoApproval() {
        Account accountRec = createAccount('FTM Quote Approval Lock Customer');
        FreightTM__Lane_Quote__c quoteRec = createCompleteQuote(accountRec, 1000, 900);

        Test.startTest();
        FtmLaneQuoteWorkspaceController.calculateQuote(quoteRec.Id);
        FtmLaneQuoteWorkspaceController.requestApproval(quoteRec.Id, 'Initial approval.');
        FtmLaneQuoteWorkspaceController.approveQuote(quoteRec.Id, 'Approved once.');
        Boolean failed = false;
        try {
            FtmLaneQuoteWorkspaceController.calculateQuote(quoteRec.Id);
        } catch (AuraHandledException expected) {
            failed = true;
        }
        Test.stopTest();

        assertAuraFailure('Approved pricing should be locked.', failed);
        FreightTM__Lane_Quote__c afterQuote = [
            SELECT Approval_Status__c, Quote_Workflow_Status__c
            FROM FreightTM__Lane_Quote__c
            WHERE Id = :quoteRec.Id
        ];
        System.assertEquals('Approved', afterQuote.Approval_Status__c);
        System.assertEquals('Ready to Send', afterQuote.Quote_Workflow_Status__c);
    }

    @IsTest
    static void approvedQuoteWithMissingRequiredFieldExplainsWhySendIsBlocked() {
        Account accountRec = createAccount('FTM Approved Quote Blocker Customer');
        FreightTM__Lane_Quote__c quoteRec = createCompleteQuote(accountRec, 1000, 900);

        Test.startTest();
        FtmLaneQuoteWorkspaceController.calculateQuote(quoteRec.Id);
        FtmLaneQuoteWorkspaceController.requestApproval(quoteRec.Id, 'Approval before legacy data test.');
        FtmLaneQuoteWorkspaceController.approveQuote(quoteRec.Id, 'Approved before a required field was cleared.');

        // Simulate an older or externally edited record that is approved but no longer send-ready.
        update new FreightTM__Lane_Quote__c(
            Id = quoteRec.Id,
            Equipment_Type__c = null,
            FreightTM__Mode__c = null
        );

        FtmLaneQuoteWorkspaceController.QuoteDataDTO blocked = FtmLaneQuoteWorkspaceController.getQuoteData(quoteRec.Id);
        System.assertEquals('Approved', blocked.approvalStatus);
        System.assertEquals('Ready to Send', blocked.workflowStatus);
        System.assertEquals(false, blocked.canMarkSent);
        System.assert(blocked.blockingMessages.contains('Equipment type or mode is required.'));
        System.assert(blocked.nextAction.contains('Mark Sent is blocked'));
        System.assert(blocked.nextAction.contains('Equipment type or mode is required.'));

        Boolean sendFailed = false;
        try {
            FtmLaneQuoteWorkspaceController.markSent(quoteRec.Id);
        } catch (AuraHandledException expected) {
            sendFailed = true;
        }
        System.assertEquals(true, sendFailed, 'Approved quotes must still satisfy required send fields.');

        update new FreightTM__Lane_Quote__c(Id = quoteRec.Id, Equipment_Type__c = 'Dry Van');
        FtmLaneQuoteWorkspaceController.QuoteDataDTO repaired = FtmLaneQuoteWorkspaceController.getQuoteData(quoteRec.Id);
        System.assertEquals(true, repaired.canMarkSent);
        FtmLaneQuoteWorkspaceController.ActionResultDTO sent = FtmLaneQuoteWorkspaceController.markSent(quoteRec.Id);
        System.assertEquals('Sent', sent.data.workflowStatus);
        Test.stopTest();
    }

    @IsTest
    static void rejectedApprovalCanBeRevisedAndRecalculated() {
        Account accountRec = createAccount('FTM Quote Rejection Customer');
        FreightTM__Lane_Quote__c quoteRec = createCompleteQuote(accountRec, 1000, 900);

        Test.startTest();
        FtmLaneQuoteWorkspaceController.calculateQuote(quoteRec.Id);
        FtmLaneQuoteWorkspaceController.requestApproval(quoteRec.Id, 'Please review.');
        FtmLaneQuoteWorkspaceController.ActionResultDTO rejected = FtmLaneQuoteWorkspaceController.rejectApproval(quoteRec.Id, 'Margin is too low.');
        System.assertEquals('Approval Rejected', rejected.data.workflowStatus);
        System.assertEquals(true, rejected.data.canCalculate);

        update new FreightTM__Lane_Quote__c(Id = quoteRec.Id, FreightTM__Customer_Rate__c = 2000, FreightTM__Rate_to_Carrier__c = 1000);
        FtmLaneQuoteWorkspaceController.ActionResultDTO recalculated = FtmLaneQuoteWorkspaceController.calculateQuote(quoteRec.Id);
        Test.stopTest();

        System.assertEquals('Calculated', recalculated.data.workflowStatus);
        System.assertEquals('Not Required', recalculated.data.approvalStatus);
        System.assertEquals(true, recalculated.data.canMarkSent);
    }

    @IsTest
    static void pendingApprovalLocksCalculation() {
        Account accountRec = createAccount('FTM Quote Pending Lock Customer');
        FreightTM__Lane_Quote__c quoteRec = createCompleteQuote(accountRec, 1000, 950);

        Test.startTest();
        FtmLaneQuoteWorkspaceController.calculateQuote(quoteRec.Id);
        FtmLaneQuoteWorkspaceController.requestApproval(quoteRec.Id, 'Pending lock test.');
        Boolean failed = false;
        try {
            FtmLaneQuoteWorkspaceController.calculateQuote(quoteRec.Id);
        } catch (AuraHandledException expected) {
            failed = true;
        }
        Test.stopTest();

        assertAuraFailure('Pending approval should lock recalculation.', failed);
    }

    @IsTest
    static void blockersAreReturnedBeforeSendOrApproval() {
        Account accountRec = createAccount('FTM Incomplete Quote Customer');
        FreightTM__Lane_Quote__c quoteRec = new FreightTM__Lane_Quote__c(
            FreightTM__Customer__c = accountRec.Id,
            FreightTM__Customer_Rate__c = 1200
        );
        insert quoteRec;

        Test.startTest();
        FtmLaneQuoteWorkspaceController.QuoteDataDTO data = FtmLaneQuoteWorkspaceController.getQuoteData(quoteRec.Id);
        System.assert(data.blockingMessages.size() >= 4);
        System.assertEquals(false, data.canMarkSent);

        Boolean sendFailed = false;
        try {
            FtmLaneQuoteWorkspaceController.markSent(quoteRec.Id);
        } catch (AuraHandledException expected) {
            sendFailed = true;
        }

        Boolean approvalFailed = false;
        try {
            FtmLaneQuoteWorkspaceController.requestApproval(quoteRec.Id, 'Should fail.');
        } catch (AuraHandledException expected) {
            approvalFailed = true;
        }
        Test.stopTest();

        assertAuraFailure('Incomplete quote should not send.', sendFailed);
        assertAuraFailure('Uncalculated quote should not request approval.', approvalFailed);
    }

    @IsTest
    static void declinedQuoteRequiresSentStateAndReason() {
        Account accountRec = createAccount('FTM Quote Decline Customer');
        FreightTM__Lane_Quote__c quoteRec = createCompleteQuote(accountRec, 1500, 1000);

        Test.startTest();
        Boolean reasonFailed = false;
        try {
            FtmLaneQuoteWorkspaceController.markDeclined(quoteRec.Id, null);
        } catch (AuraHandledException expected) {
            reasonFailed = true;
        }

        FtmLaneQuoteWorkspaceController.calculateQuote(quoteRec.Id);
        Boolean stateFailed = false;
        try {
            FtmLaneQuoteWorkspaceController.markAccepted(quoteRec.Id, 'Should fail before send.');
        } catch (AuraHandledException expected) {
            stateFailed = true;
        }

        FtmLaneQuoteWorkspaceController.markSent(quoteRec.Id);
        FtmLaneQuoteWorkspaceController.ActionResultDTO declined = FtmLaneQuoteWorkspaceController.markDeclined(quoteRec.Id, 'Rate too high.');
        Test.stopTest();

        assertAuraFailure('A decline reason is required.', reasonFailed);
        assertAuraFailure('Acceptance requires Sent state.', stateFailed);
        System.assertEquals('Declined', declined.data.customerResponse);

        FreightTM__Lane_Quote__c afterQuote = [
            SELECT Customer_Response__c, Win_Loss_Reason__c
            FROM FreightTM__Lane_Quote__c
            WHERE Id = :quoteRec.Id
        ];
        System.assertEquals('Declined', afterQuote.Customer_Response__c);
        System.assertEquals('Rate too high.', afterQuote.Win_Loss_Reason__c);
    }

    @IsTest
    static void predictsRateFromExactLaneHistory() {
        Account accountRec = createAccount('FTM Quote Prediction Customer');
        Test.setMock(HttpCalloutMock.class, new FreightGraphSyncMock());
        List<FreightTM__Load__c> loads = new List<FreightTM__Load__c>();
        for (Integer i = 0; i < 3; i++) {
            loads.add(new FreightTM__Load__c(
                FreightTM__Customer__c = accountRec.Id,
                FreightTM__Pickup_City__c = 'Houston',
                FreightTM__Pickup_State__c = 'TX',
                FreightTM__Delivery_City__c = 'Dallas',
                FreightTM__Delivery_State__c = 'TX',
                FreightTM__Pickup_Date__c = Date.today().addDays(-20 - i),
                FreightTM__Delivery_Date__c = Date.today().addDays(-19 - i),
                FreightTM__Status__c = validLoadStatus(),
                FreightTM__Rate__c = 3000 + (i * 100),
                FreightTM__Rate_to_Carrier__c = 2200 + (i * 100)
            ));
        }
        insert loads;

        FreightTM__Lane_Quote__c quoteRec = new FreightTM__Lane_Quote__c(
            FreightTM__Customer__c = accountRec.Id,
            FreightTM__Pickup_City__c = 'Houston',
            FreightTM__Pickup_State__c = 'TX',
            FreightTM__Delivery_City__c = 'Dallas',
            FreightTM__Delivery_State__c = 'TX',
            FreightTM__Estimated_Pickup_Time__c = System.now().addDays(2),
            FreightTM__Weight__c = 42000,
            Equipment_Type__c = 'Dry Van',
            Minimum_Margin_Percent__c = 15,
            Target_Margin_Percent__c = 20
        );
        insert quoteRec;

        Test.startTest();
        FtmLaneQuoteWorkspaceController.ActionResultDTO calc = FtmLaneQuoteWorkspaceController.calculateQuote(quoteRec.Id);
        Test.stopTest();

        System.assertEquals('Exact Lane History', calc.data.pricingSource);
        System.assert(calc.data.priorLoadCount >= 3);
        System.assertNotEquals(null, calc.data.suggestedRate);
        System.assertNotEquals(null, calc.data.customerRate);
        System.assertNotEquals(null, calc.data.estimatedCarrierCost);
        System.assertNotEquals(null, calc.data.estimatedMarginPercent);
        System.assertEquals(true, calc.data.historyRows.size() >= 3);
    }

    @IsTest
    static void predictsRateFromSimilarShipmentHistory() {
        Account accountRec = createAccount('FTM Similar Shipment Customer');
        Test.setMock(HttpCalloutMock.class, new FreightGraphSyncMock());
        insert new FreightTM__Load__c(
            FreightTM__Customer__c = accountRec.Id,
            FreightTM__Pickup_City__c = 'Houston',
            FreightTM__Pickup_State__c = 'TX',
            FreightTM__Delivery_City__c = 'Dallas',
            FreightTM__Delivery_State__c = 'TX',
            FreightTM__Pickup_Date__c = Date.today().addDays(-15),
            FreightTM__Delivery_Date__c = Date.today().addDays(-14),
            FreightTM__Status__c = validLoadStatus(),
            FreightTM__Rate__c = 2400,
            FreightTM__Rate_to_Carrier__c = 1800
        );

        FreightTM__Lane_Quote__c quoteRec = new FreightTM__Lane_Quote__c(
            FreightTM__Customer__c = accountRec.Id,
            FreightTM__Pickup_City__c = 'Austin',
            FreightTM__Pickup_State__c = 'TX',
            FreightTM__Delivery_City__c = 'Fort Worth',
            FreightTM__Delivery_State__c = 'TX',
            FreightTM__Estimated_Pickup_Time__c = System.now().addDays(2),
            Equipment_Type__c = 'Dry Van'
        );
        insert quoteRec;

        Test.startTest();
        FtmLaneQuoteWorkspaceController.ActionResultDTO calc = FtmLaneQuoteWorkspaceController.calculateQuote(quoteRec.Id);
        Test.stopTest();

        System.assertEquals('Similar Shipment History', calc.data.pricingSource);
        System.assert(calc.data.similarShipmentCount >= 1);
        System.assertNotEquals(null, calc.data.averageSimilarRate);
    }

    @IsTest
    static void fallbackPricingAndContractTermsAreCaptured() {
        Account accountRec = createAccount('FTM Contract Customer');
        Contract contractRec = new Contract(
            AccountId = accountRec.Id,
            StartDate = Date.today().addDays(-5),
            ContractTerm = 12,
            Status = 'Draft',
            SpecialTerms = 'Discount 5%. Target margin 22%. Minimum margin 16%.'
        );
        insert contractRec;

        FreightTM__Lane_Quote__c quoteRec = new FreightTM__Lane_Quote__c(
            FreightTM__Customer__c = accountRec.Id,
            FreightTM__Contract__c = contractRec.Id,
            FreightTM__Pickup_City__c = 'Boise',
            FreightTM__Pickup_State__c = 'ID',
            FreightTM__Delivery_City__c = 'Reno',
            FreightTM__Delivery_State__c = 'NV',
            FreightTM__Estimated_Pickup_Time__c = System.now().addDays(2),
            FreightTM__Weight__c = 10000,
            Pallet_Count__c = 4,
            Equipment_Type__c = 'Reefer',
            Service_Level__c = 'Expedited'
        );
        insert quoteRec;

        Test.startTest();
        FtmLaneQuoteWorkspaceController.ActionResultDTO calc = FtmLaneQuoteWorkspaceController.calculateQuote(quoteRec.Id);
        Test.stopTest();

        System.assert(calc.data.pricingSource.contains('Fallback Rule'));
        System.assert(calc.data.pricingSource.contains('Contract'));
        System.assertEquals(5, calc.data.contractAdjustmentPercent);
        System.assertEquals(16, calc.data.minimumMarginPercent);
        System.assertEquals(22, calc.data.targetMarginPercent);
        System.assertEquals(true, calc.data.approvalRequired);
        System.assertNotEquals(null, calc.data.pricingLog);
        System.assertNotEquals(null, calc.data.customerContextSummary);
    }

    @IsTest
    static void invalidQuoteIdsAreRejected() {
        Account accountRec = createAccount('FTM Invalid Id Customer');

        Test.startTest();
        Boolean nullFailed = false;
        try {
            FtmLaneQuoteWorkspaceController.getQuoteData(null);
        } catch (AuraHandledException expected) {
            nullFailed = true;
        }

        Boolean typeFailed = false;
        try {
            FtmLaneQuoteWorkspaceController.getQuoteData(accountRec.Id);
        } catch (AuraHandledException expected) {
            typeFailed = true;
        }
        Test.stopTest();

        assertAuraFailure('Null quote Id should fail.', nullFailed);
        assertAuraFailure('Non-quote Id should fail.', typeFailed);
    }
}