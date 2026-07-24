public with sharing class FtmLaneQuoteWorkspaceController {
    private static final Decimal DEFAULT_MIN_MARGIN = 15;
    private static final Decimal DEFAULT_TARGET_MARGIN = 20;
    private static final Integer HISTORY_LIMIT = 50;
    private static final String READY_TO_SEND = 'Ready to Send';

    public class QuoteDataDTO {
        @AuraEnabled public String quoteId;
        @AuraEnabled public String quoteNumber;
        @AuraEnabled public String customerName;
        @AuraEnabled public String customerTier;
        @AuraEnabled public String customerSinceYear;
        @AuraEnabled public String carrierName;
        @AuraEnabled public String contractName;
        @AuraEnabled public String orderName;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String route;
        @AuraEnabled public String nativeStatus;
        @AuraEnabled public String workflowStatus;
        @AuraEnabled public String approvalStatus;
        @AuraEnabled public Boolean approvalRequired;
        @AuraEnabled public String customerResponse;
        @AuraEnabled public String customerResponseAt;
        @AuraEnabled public String sentAt;
        @AuraEnabled public String convertedAt;
        @AuraEnabled public String convertedLoadId;
        @AuraEnabled public String convertedLoadName;
        @AuraEnabled public String lastCalculatedAt;
        @AuraEnabled public String marginStatus;
        @AuraEnabled public Decimal customerRate;
        @AuraEnabled public Decimal suggestedRate;
        @AuraEnabled public Decimal estimatedCarrierCost;
        @AuraEnabled public Decimal estimatedGrossProfit;
        @AuraEnabled public Decimal estimatedMarginPercent;
        @AuraEnabled public Decimal minimumMarginPercent;
        @AuraEnabled public Decimal targetMarginPercent;
        @AuraEnabled public Decimal priorLoadCount;
        @AuraEnabled public Decimal averageLaneRate;
        @AuraEnabled public Decimal averageLaneCost;
        @AuraEnabled public Decimal averageLaneMargin;
        @AuraEnabled public String laneOutlierWarning;
        @AuraEnabled public String equipmentType;
        @AuraEnabled public Decimal weight;
        @AuraEnabled public Decimal palletCount;
        @AuraEnabled public String commodity;
        @AuraEnabled public String serviceLevel;
        @AuraEnabled public String pricingConfidence;
        @AuraEnabled public String pricingSource;
        @AuraEnabled public String pricingExplanation;
        @AuraEnabled public Decimal similarShipmentCount;
        @AuraEnabled public Decimal averageSimilarRate;
        @AuraEnabled public Decimal averageSimilarCost;
        @AuraEnabled public Decimal averageSimilarMargin;
        @AuraEnabled public Decimal lastLaneRate;
        @AuraEnabled public Decimal lastLaneCost;
        @AuraEnabled public String customerContextSummary;
        @AuraEnabled public String shipmentContextSummary;
        @AuraEnabled public String pricingLog;
        @AuraEnabled public String overrideReason;
        @AuraEnabled public String approvalComments;
        @AuraEnabled public String winLossReason;
        @AuraEnabled public Decimal tariffRate;
        @AuraEnabled public String tariffSource;
        @AuraEnabled public String tariffMatchDetail;
        @AuraEnabled public String contractContext;
        @AuraEnabled public Decimal contractAdjustmentPercent;
        @AuraEnabled public String accessorialRisk;
        @AuraEnabled public String accessorialRiskSummary;
        @AuraEnabled public String serviceIssueRisk;
        @AuraEnabled public String serviceIssueSummary;
        @AuraEnabled public String quoteHistorySummary;
        @AuraEnabled public Decimal priorQuoteCount;
        @AuraEnabled public Decimal quoteWinRate;
        @AuraEnabled public String recommendedAction;
        @AuraEnabled public List<String> blockingMessages;
        @AuraEnabled public List<String> warningMessages;
        @AuraEnabled public Boolean canCalculate;
        @AuraEnabled public Boolean canRequestApproval;
        @AuraEnabled public Boolean canApprove;
        @AuraEnabled public Boolean canMarkSent;
        @AuraEnabled public Boolean canMarkAccepted;
        @AuraEnabled public Boolean canMarkDeclined;
        @AuraEnabled public Boolean canConvertToLoad;
        @AuraEnabled public Boolean pricingLocked;
        @AuraEnabled public String nextAction;
        @AuraEnabled public List<HistoryRowDTO> historyRows;
    }

    public class HistoryRowDTO {
        @AuraEnabled public String loadId;
        @AuraEnabled public String loadNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String pickupDate;
        @AuraEnabled public String deliveryDate;
        @AuraEnabled public Decimal rate;
        @AuraEnabled public Decimal carrierCost;
        @AuraEnabled public Decimal marginPercent;
    }

    public class ActionResultDTO {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public QuoteDataDTO data;
    }

    private class HistorySummary {
        Integer loadCount = 0;
        Set<Id> loadIds = new Set<Id>();
        Decimal avgRate;
        Decimal avgCost;
        Decimal avgMargin;
        Decimal lastRate;
        Decimal lastCost;
        Integer accessorialSignalCount = 0;
        Integer serviceIssueCount = 0;
        Integer lateCount = 0;
        Integer podMissingCount = 0;
        String warning;
        List<HistoryRowDTO> rows = new List<HistoryRowDTO>();
    }

    private class TariffMatch {
        Decimal rate;
        String source;
        String detail;
        Integer score = 0;
    }

    private class ContractContext {
        Decimal discountPercent;
        Decimal targetMarginPercent;
        Decimal minimumMarginPercent;
        String summary;
        Boolean active = false;
    }

    private class QuoteHistorySummary {
        Integer priorQuoteCount = 0;
        Integer wonCount = 0;
        Integer lostCount = 0;
        Decimal winRate;
        Decimal avgMargin;
        String summary;
    }

    private class CalculationResult {
        Decimal suggestedRate;
        Decimal carrierCost;
        Decimal grossProfit;
        Decimal marginPercent;
        Decimal minMargin;
        Decimal targetMargin;
        Boolean approvalRequired = false;
        String marginStatus;
        String confidence;
        String pricingSource;
        String pricingExplanation;
        String pricingLog;
        String recommendedAction;
        HistorySummary history;
        HistorySummary similarHistory;
        TariffMatch tariff;
        ContractContext contractContext;
        QuoteHistorySummary quoteHistory;
        Decimal quotePayCost;
        Decimal quoteLegPayCost;
        Decimal rateUsedForMargin;
        String accessorialRisk;
        String accessorialSummary;
        String serviceRisk;
        String serviceSummary;
    }

    @AuraEnabled(cacheable=true)
    public static QuoteDataDTO getQuoteData(Id quoteId) {
        validateQuoteId(quoteId);
        return buildQuoteData(queryQuote(quoteId, false), true);
    }

    @AuraEnabled
    public static ActionResultDTO calculateQuote(Id quoteId) {
        validateQuoteId(quoteId);
        FreightTM__Lane_Quote__c quoteRec = queryQuote(quoteId, true);
        ensurePricingEditable(quoteRec);
        CalculationResult calc = calculateQuoteValues(quoteRec);

        FreightTM__Lane_Quote__c updateRec = new FreightTM__Lane_Quote__c(Id = quoteRec.Id);
        updateRec.Suggested_Rate__c = calc.suggestedRate;
        updateRec.Estimated_Gross_Profit__c = calc.grossProfit;
        updateRec.Estimated_Margin_Percent__c = calc.marginPercent;
        updateRec.Margin_Status__c = calc.marginStatus;
        updateRec.Approval_Required__c = calc.approvalRequired;
        updateRec.Last_Calculated_At__c = System.now();
        updateRec.Pricing_Confidence__c = calc.confidence;
        updateRec.Pricing_Source__c = calc.pricingSource;
        updateRec.Pricing_Explanation__c = calc.pricingExplanation;
        updateRec.Pricing_Log__c = calc.pricingLog;
        updateRec.Recommended_Action__c = calc.recommendedAction;

        if (quoteRec.Minimum_Margin_Percent__c == null || calc.minMargin != quoteRec.Minimum_Margin_Percent__c) updateRec.Minimum_Margin_Percent__c = calc.minMargin;
        if (quoteRec.Target_Margin_Percent__c == null || calc.targetMargin != quoteRec.Target_Margin_Percent__c) updateRec.Target_Margin_Percent__c = calc.targetMargin;
        if (quoteRec.FreightTM__Customer_Rate__c == null && calc.suggestedRate != null) updateRec.FreightTM__Customer_Rate__c = calc.suggestedRate;
        if (quoteRec.FreightTM__Rate_to_Carrier__c == null && calc.carrierCost != null) updateRec.FreightTM__Rate_to_Carrier__c = calc.carrierCost;

        updateRec.Prior_Load_Count__c = calc.history == null ? 0 : calc.history.loadCount;
        updateRec.Average_Lane_Rate__c = calc.history == null ? null : calc.history.avgRate;
        updateRec.Average_Lane_Cost__c = calc.history == null ? null : calc.history.avgCost;
        updateRec.Average_Lane_Margin__c = calc.history == null ? null : calc.history.avgMargin;
        updateRec.Last_Lane_Rate__c = calc.history == null ? null : calc.history.lastRate;
        updateRec.Last_Lane_Cost__c = calc.history == null ? null : calc.history.lastCost;
        updateRec.Similar_Shipment_Count__c = calc.similarHistory == null ? 0 : calc.similarHistory.loadCount;
        updateRec.Average_Similar_Rate__c = calc.similarHistory == null ? null : calc.similarHistory.avgRate;
        updateRec.Average_Similar_Cost__c = calc.similarHistory == null ? null : calc.similarHistory.avgCost;
        updateRec.Average_Similar_Margin__c = calc.similarHistory == null ? null : calc.similarHistory.avgMargin;
        updateRec.Lane_Outlier_Warning__c = calc.history == null ? null : calc.history.warning;

        updateRec.Tariff_Rate__c = calc.tariff == null ? null : calc.tariff.rate;
        updateRec.Tariff_Source__c = calc.tariff == null ? null : calc.tariff.source;
        updateRec.Tariff_Match_Detail__c = calc.tariff == null ? null : calc.tariff.detail;
        updateRec.Contract_Context__c = calc.contractContext == null ? null : calc.contractContext.summary;
        updateRec.Contract_Adjustment_Percent__c = calc.contractContext == null ? null : calc.contractContext.discountPercent;
        updateRec.Accessorial_Risk__c = calc.accessorialRisk;
        updateRec.Accessorial_Risk_Summary__c = calc.accessorialSummary;
        updateRec.Service_Issue_Risk__c = calc.serviceRisk;
        updateRec.Service_Issue_Summary__c = calc.serviceSummary;
        updateRec.Prior_Quote_Count__c = calc.quoteHistory == null ? 0 : calc.quoteHistory.priorQuoteCount;
        updateRec.Quote_Win_Rate__c = calc.quoteHistory == null ? null : calc.quoteHistory.winRate;
        updateRec.Quote_History_Summary__c = calc.quoteHistory == null ? null : calc.quoteHistory.summary;
        updateRec.Customer_Context_Summary__c = buildCustomerContext(quoteRec, calc.contractContext, calc.quoteHistory);
        updateRec.Shipment_Context_Summary__c = buildShipmentContext(quoteRec, calc.history, calc.similarHistory);

        if (calc.approvalRequired) {
            // Any recalculation can change the commercial decision. Reset prior approval so
            // a previously approved quote cannot be changed and sent without a fresh review.
            updateRec.Quote_Workflow_Status__c = 'Approval Required';
            updateRec.Approval_Status__c = 'Not Requested';
            updateRec.Approval_Requested_At__c = null;
            updateRec.Approval_Decision_At__c = null;
            updateRec.Approver__c = null;
        } else {
            updateRec.Quote_Workflow_Status__c = 'Calculated';
            updateRec.Approval_Status__c = 'Not Required';
            updateRec.Approval_Requested_At__c = null;
            updateRec.Approval_Decision_At__c = null;
            updateRec.Approver__c = null;
        }

        update updateRec;
        return result(true, 'Quote calculated from tariff, contract/customer context, lane history, shipment history, carrier cost, risk signals, and approval rules.', quoteRec.Id);
    }

    @AuraEnabled
    public static ActionResultDTO requestApproval(Id quoteId, String note) {
        validateQuoteId(quoteId);
        FreightTM__Lane_Quote__c quoteRec = queryQuote(quoteId, true);
        if (quoteRec.Approval_Status__c == 'Pending') return result(true, 'Approval is already pending.', quoteRec.Id);
        if (quoteRec.Approval_Status__c == 'Rejected') throw new AuraHandledException('Revise and recalculate the quote before requesting approval again.');
        ensurePricingEditable(quoteRec);
        if (quoteRec.Estimated_Margin_Percent__c == null) throw new AuraHandledException('Calculate the quote before requesting approval.');
        List<String> approvalBlockers = getApprovalRequestBlockers(quoteRec);
        if (!approvalBlockers.isEmpty()) {
            throw new AuraHandledException('Approval cannot be requested yet: ' + String.join(approvalBlockers, ' | '));
        }
        FreightTM__Lane_Quote__c updateRec = new FreightTM__Lane_Quote__c(Id = quoteRec.Id);
        updateRec.Approval_Required__c = true;
        updateRec.Approval_Status__c = 'Pending';
        updateRec.Approval_Requested_At__c = System.now();
        updateRec.Approval_Decision_At__c = null;
        updateRec.Approver__c = null;
        updateRec.Approval_Comments__c = appendNote(quoteRec.Approval_Comments__c, 'Approval requested', note);
        updateRec.Quote_Workflow_Status__c = 'Pending Approval';
        update updateRec;
        return result(true, 'Approval requested. Pricing is locked until the request is approved or rejected.', quoteRec.Id);
    }

    @AuraEnabled
    public static ActionResultDTO approveQuote(Id quoteId, String note) {
        validateQuoteId(quoteId);
        FreightTM__Lane_Quote__c quoteRec = queryQuote(quoteId, true);
        if (quoteRec.Approval_Status__c != 'Pending') throw new AuraHandledException('Only a pending approval request can be approved.');
        List<String> approvalBlockers = getApprovalRequestBlockers(quoteRec);
        if (!approvalBlockers.isEmpty()) throw new AuraHandledException('Quote cannot be approved: ' + String.join(approvalBlockers, ' | '));
        FreightTM__Lane_Quote__c updateRec = new FreightTM__Lane_Quote__c(Id = quoteRec.Id);
        updateRec.Approval_Status__c = 'Approved';
        // Keep Approval Required = true as an audit signal. The approved status clears the send blocker.
        updateRec.Approval_Required__c = true;
        updateRec.Approver__c = UserInfo.getUserId();
        updateRec.Approval_Decision_At__c = System.now();
        updateRec.Approval_Comments__c = appendNote(quoteRec.Approval_Comments__c, 'Approved', note);
        updateRec.Quote_Workflow_Status__c = READY_TO_SEND;
        update updateRec;
        return result(true, 'Quote approved and moved to Ready to Send.', quoteRec.Id);
    }

    @AuraEnabled
    public static ActionResultDTO rejectApproval(Id quoteId, String note) {
        validateQuoteId(quoteId);
        FreightTM__Lane_Quote__c quoteRec = queryQuote(quoteId, true);
        if (quoteRec.Approval_Status__c != 'Pending') throw new AuraHandledException('Only a pending approval request can be rejected.');
        FreightTM__Lane_Quote__c updateRec = new FreightTM__Lane_Quote__c(Id = quoteRec.Id);
        updateRec.Approval_Status__c = 'Rejected';
        updateRec.Approval_Required__c = true;
        updateRec.Approver__c = UserInfo.getUserId();
        updateRec.Approval_Decision_At__c = System.now();
        updateRec.Approval_Comments__c = appendNote(quoteRec.Approval_Comments__c, 'Rejected', note);
        updateRec.Quote_Workflow_Status__c = 'Approval Rejected';
        update updateRec;
        return result(true, 'Approval rejected and logged. Revise the quote before sending.', quoteRec.Id);
    }

    @AuraEnabled
    public static ActionResultDTO markSent(Id quoteId) {
        validateQuoteId(quoteId);
        FreightTM__Lane_Quote__c quoteRec = queryQuote(quoteId, true);
        List<String> blockers = getSendBlockers(quoteRec);
        if (!blockers.isEmpty()) throw new AuraHandledException('Quote cannot be sent: ' + String.join(blockers, ' | '));
        if (quoteRec.Quote_Workflow_Status__c == 'Sent') return result(true, 'Quote is already marked sent.', quoteRec.Id);
        FreightTM__Lane_Quote__c updateRec = new FreightTM__Lane_Quote__c(Id = quoteRec.Id);
        updateRec.Quote_Workflow_Status__c = 'Sent';
        updateRec.Sent_At__c = System.now();
        updateRec.Customer_Response__c = 'No Response';
        update updateRec;
        return result(true, 'Quote marked sent. Internal cost, margin, approval comments, and pricing logic stay internal.', quoteRec.Id);
    }

    @AuraEnabled
    public static ActionResultDTO markAccepted(Id quoteId, String note) {
        validateQuoteId(quoteId);
        FreightTM__Lane_Quote__c quoteRec = queryQuote(quoteId, true);
        if (quoteRec.Quote_Workflow_Status__c != 'Sent') throw new AuraHandledException('Only a sent quote can be marked accepted.');
        if (quoteRec.FreightTM__Customer_Rate__c == null && quoteRec.Suggested_Rate__c == null) throw new AuraHandledException('A quote amount is required before acceptance.');
        FreightTM__Lane_Quote__c updateRec = new FreightTM__Lane_Quote__c(Id = quoteRec.Id);
        updateRec.Quote_Workflow_Status__c = 'Accepted';
        updateRec.Customer_Response__c = 'Accepted';
        updateRec.Customer_Response_At__c = System.now();
        updateRec.Customer_Response_Message__c = appendNote(quoteRec.Customer_Response_Message__c, 'Accepted', note);
        update updateRec;
        return result(true, 'Quote marked accepted. It is ready to convert to a Load.', quoteRec.Id);
    }

    @AuraEnabled
    public static ActionResultDTO markDeclined(Id quoteId, String reason) {
        validateQuoteId(quoteId);
        if (String.isBlank(reason)) throw new AuraHandledException('A win/loss reason is required.');
        FreightTM__Lane_Quote__c quoteRec = queryQuote(quoteId, true);
        if (quoteRec.Quote_Workflow_Status__c != 'Sent') throw new AuraHandledException('Only a sent quote can be marked declined.');
        FreightTM__Lane_Quote__c updateRec = new FreightTM__Lane_Quote__c(Id = quoteRec.Id);
        updateRec.Quote_Workflow_Status__c = 'Declined';
        updateRec.Customer_Response__c = 'Declined';
        updateRec.Customer_Response_At__c = System.now();
        updateRec.Customer_Response_Message__c = appendNote(quoteRec.Customer_Response_Message__c, 'Declined', reason);
        updateRec.Win_Loss_Reason__c = reason.left(255);
        update updateRec;
        return result(true, 'Quote declined and the reason was saved for future pricing intelligence.', quoteRec.Id);
    }

    @AuraEnabled
    public static ActionResultDTO convertToLoad(Id quoteId) {
        validateQuoteId(quoteId);
        FreightTM__Lane_Quote__c quoteRec = queryQuote(quoteId, true);
        if (quoteRec.Converted_Load__c != null) return result(true, 'Quote was already converted to Load ' + quoteRec.Converted_Load__r.Name + '.', quoteRec.Id);
        if (quoteRec.Customer_Response__c != 'Accepted' && quoteRec.Quote_Workflow_Status__c != 'Accepted') throw new AuraHandledException('Only accepted quotes can be converted to a Load.');
        List<String> blockers = getConversionBlockers(quoteRec);
        if (!blockers.isEmpty()) throw new AuraHandledException('Quote cannot be converted: ' + String.join(blockers, ' | '));

        FreightTM__Load__c loadRec = new FreightTM__Load__c();
        loadRec.FreightTM__Customer__c = quoteRec.FreightTM__Customer__c;
        loadRec.FreightTM__Lane_Quote__c = quoteRec.Id;
        if (quoteRec.FreightTM__Carrier__c != null) loadRec.FreightTM__Carrier_Obj__c = quoteRec.FreightTM__Carrier__c;
        loadRec.FreightTM__Pickup_City__c = quoteRec.FreightTM__Pickup_City__c;
        loadRec.FreightTM__Pickup_State__c = quoteRec.FreightTM__Pickup_State__c;
        loadRec.FreightTM__Pickup_Zip_Code__c = quoteRec.FreightTM__Pickup_Zip_Code__c;
        loadRec.FreightTM__Pickup_Country__c = quoteRec.FreightTM__Pickup_Country__c;
        loadRec.FreightTM__Delivery_City__c = quoteRec.FreightTM__Delivery_City__c;
        loadRec.FreightTM__Delivery_State__c = quoteRec.FreightTM__Delivery_State__c;
        loadRec.FreightTM__Delivery_Zip_Code__c = quoteRec.FreightTM__Delivery_Zip_Code__c;
        loadRec.FreightTM__Delivery_Country__c = quoteRec.FreightTM__Delivery_Country__c;
        loadRec.FreightTM__Pickup_Date__c = quoteRec.FreightTM__Estimated_Pickup_Time__c == null ? null : quoteRec.FreightTM__Estimated_Pickup_Time__c.date();
        loadRec.FreightTM__Delivery_Date__c = quoteRec.FreightTM__Estimated_Delivery_Time__c == null ? null : quoteRec.FreightTM__Estimated_Delivery_Time__c.date();
        loadRec.FreightTM__Weight__c = quoteRec.FreightTM__Weight__c;
        loadRec.FreightTM__Rate__c = quoteRec.FreightTM__Customer_Rate__c == null ? quoteRec.Suggested_Rate__c : quoteRec.FreightTM__Customer_Rate__c;
        loadRec.FreightTM__Rate_to_Carrier__c = quoteRec.FreightTM__Rate_to_Carrier__c;
        loadRec.FreightTM__Quote__c = true;
        if (!String.isBlank(quoteRec.Equipment_Type__c) && isAllowedPicklistValue(FreightTM__Load__c.FreightTM__Trailer__c, quoteRec.Equipment_Type__c)) loadRec.FreightTM__Trailer__c = quoteRec.Equipment_Type__c;
        if (isAllowedPicklistValue(FreightTM__Load__c.FreightTM__Status__c, 'Assigned')) loadRec.FreightTM__Status__c = 'Assigned';
        loadRec.Original_Quoted_Rate__c = loadRec.FreightTM__Rate__c;
        loadRec.Original_Estimated_Cost__c = quoteRec.FreightTM__Rate_to_Carrier__c;
        loadRec.Original_Estimated_Margin__c = quoteRec.Estimated_Margin_Percent__c;
        loadRec.Original_Quote_Workflow_Status__c = quoteRec.Quote_Workflow_Status__c;
        loadRec.Original_Lane_Quote_Calculated_At__c = quoteRec.Last_Calculated_At__c;
        loadRec.FreightTM__Remarks__c = buildLoadRemarks(quoteRec);
        insert loadRec;

        update new FreightTM__Lane_Quote__c(Id = quoteRec.Id, Converted_Load__c = loadRec.Id, Converted_At__c = System.now(), Quote_Workflow_Status__c = 'Converted to Load');
        return result(true, 'Quote converted to Load ' + loadRec.Name + '. Original rate, cost, margin, and pricing context were copied.', quoteRec.Id);
    }

    private static FreightTM__Lane_Quote__c queryQuote(Id quoteId, Boolean forUpdate) {
        String q = 'SELECT Id, Name, OwnerId, Owner.Name, FreightTM__Customer__c, FreightTM__Customer__r.Name, FreightTM__Customer__r.CreatedDate, FreightTM__Customer__r.Industry, FreightTM__Customer__r.Type, FreightTM__Customer__r.Rating, FreightTM__Carrier__c, FreightTM__Carrier__r.Name, FreightTM__Contract__c, FreightTM__Contract__r.Name, FreightTM__Order__c, FreightTM__Order__r.Name, FreightTM__Customer_Rate__c, FreightTM__Rate_to_Carrier__c, FreightTM__Pickup_City__c, FreightTM__Pickup_State__c, FreightTM__Pickup_Zip_Code__c, FreightTM__Pickup_3_Zip__c, FreightTM__Pickup_Country__c, FreightTM__Pickup_Street__c, FreightTM__Delivery_City__c, FreightTM__Delivery_State__c, FreightTM__Delivery_Zip_Code__c, FreightTM__Delivery_3_Zip__c, FreightTM__Delivery_Country__c, FreightTM__Delivery_Street__c, FreightTM__Estimated_Pickup_Time__c, FreightTM__Estimated_Delivery_Time__c, FreightTM__Weight__c, FreightTM__Mode__c, FreightTM__Status__c, FreightTM__Priority__c, FreightTM__Description__c, Equipment_Type__c, Pallet_Count__c, Commodity__c, Service_Level__c, Suggested_Rate__c, Estimated_Gross_Profit__c, Estimated_Margin_Percent__c, Minimum_Margin_Percent__c, Target_Margin_Percent__c, Margin_Status__c, Approval_Required__c, Approval_Status__c, Approval_Requested_At__c, Approval_Decision_At__c, Approver__c, Approval_Comments__c, Customer_Response__c, Customer_Response_At__c, Customer_Response_Message__c, Sent_At__c, Win_Loss_Reason__c, Converted_Load__c, Converted_Load__r.Name, Converted_At__c, Quote_Workflow_Status__c, Prior_Load_Count__c, Average_Lane_Rate__c, Average_Lane_Cost__c, Average_Lane_Margin__c, Last_Lane_Rate__c, Last_Lane_Cost__c, Lane_Outlier_Warning__c, Similar_Shipment_Count__c, Average_Similar_Rate__c, Average_Similar_Cost__c, Average_Similar_Margin__c, Pricing_Confidence__c, Pricing_Source__c, Pricing_Explanation__c, Pricing_Log__c, Override_Reason__c, Customer_Context_Summary__c, Shipment_Context_Summary__c, Last_Calculated_At__c, Internal_Quote_Notes__c, Tariff_Rate__c, Tariff_Source__c, Tariff_Match_Detail__c, Contract_Context__c, Contract_Adjustment_Percent__c, Accessorial_Risk__c, Accessorial_Risk_Summary__c, Service_Issue_Risk__c, Service_Issue_Summary__c, Quote_History_Summary__c, Prior_Quote_Count__c, Quote_Win_Rate__c, Recommended_Action__c FROM FreightTM__Lane_Quote__c WHERE Id = :quoteId';
        if (forUpdate) q += ' FOR UPDATE';
        return (FreightTM__Lane_Quote__c) Database.query(q);
    }

    private static QuoteDataDTO buildQuoteData(FreightTM__Lane_Quote__c q, Boolean includeFreshHistory) {
        HistorySummary hist = includeFreshHistory ? buildHistory(q) : new HistorySummary();
        QuoteDataDTO d = new QuoteDataDTO();
        d.quoteId = String.valueOf(q.Id); d.quoteNumber = q.Name;
        d.customerName = q.FreightTM__Customer__r == null ? null : q.FreightTM__Customer__r.Name;
        d.customerTier = q.FreightTM__Customer__r == null ? null : q.FreightTM__Customer__r.Type;
        d.customerSinceYear = q.FreightTM__Customer__r == null || q.FreightTM__Customer__r.CreatedDate == null ? null : q.FreightTM__Customer__r.CreatedDate.format('yyyy');
        d.carrierName = q.FreightTM__Carrier__r == null ? null : q.FreightTM__Carrier__r.Name;
        d.contractName = q.FreightTM__Contract__r == null ? null : q.FreightTM__Contract__r.Name;
        d.orderName = q.FreightTM__Order__r == null ? null : q.FreightTM__Order__r.Name;
        d.ownerName = q.Owner == null ? null : q.Owner.Name;
        d.route = buildRoute(q); d.nativeStatus = q.FreightTM__Status__c;
        d.workflowStatus = String.isBlank(q.Quote_Workflow_Status__c) ? 'Draft' : q.Quote_Workflow_Status__c;
        d.approvalStatus = String.isBlank(q.Approval_Status__c) ? 'Not Requested' : q.Approval_Status__c;
        d.approvalRequired = q.Approval_Required__c == true;
        d.customerResponse = String.isBlank(q.Customer_Response__c) ? 'No Response' : q.Customer_Response__c;
        d.customerResponseAt = formatDateTime(q.Customer_Response_At__c); d.sentAt = formatDateTime(q.Sent_At__c); d.convertedAt = formatDateTime(q.Converted_At__c); d.lastCalculatedAt = formatDateTime(q.Last_Calculated_At__c);
        d.convertedLoadId = q.Converted_Load__c == null ? null : String.valueOf(q.Converted_Load__c); d.convertedLoadName = q.Converted_Load__r == null ? null : q.Converted_Load__r.Name;
        d.marginStatus = q.Margin_Status__c; d.customerRate = q.FreightTM__Customer_Rate__c; d.suggestedRate = q.Suggested_Rate__c; d.estimatedCarrierCost = q.FreightTM__Rate_to_Carrier__c; d.estimatedGrossProfit = q.Estimated_Gross_Profit__c; d.estimatedMarginPercent = q.Estimated_Margin_Percent__c;
        d.minimumMarginPercent = q.Minimum_Margin_Percent__c == null ? DEFAULT_MIN_MARGIN : q.Minimum_Margin_Percent__c; d.targetMarginPercent = q.Target_Margin_Percent__c == null ? DEFAULT_TARGET_MARGIN : q.Target_Margin_Percent__c;
        d.priorLoadCount = q.Prior_Load_Count__c == null ? hist.loadCount : q.Prior_Load_Count__c; d.averageLaneRate = q.Average_Lane_Rate__c == null ? hist.avgRate : q.Average_Lane_Rate__c; d.averageLaneCost = q.Average_Lane_Cost__c == null ? hist.avgCost : q.Average_Lane_Cost__c; d.averageLaneMargin = q.Average_Lane_Margin__c == null ? hist.avgMargin : q.Average_Lane_Margin__c;
        d.laneOutlierWarning = String.isBlank(q.Lane_Outlier_Warning__c) ? hist.warning : q.Lane_Outlier_Warning__c;
        d.equipmentType = q.Equipment_Type__c; d.weight = q.FreightTM__Weight__c; d.palletCount = q.Pallet_Count__c; d.commodity = q.Commodity__c; d.serviceLevel = q.Service_Level__c;
        d.pricingConfidence = q.Pricing_Confidence__c; d.pricingSource = q.Pricing_Source__c; d.pricingExplanation = q.Pricing_Explanation__c;
        d.similarShipmentCount = q.Similar_Shipment_Count__c; d.averageSimilarRate = q.Average_Similar_Rate__c; d.averageSimilarCost = q.Average_Similar_Cost__c; d.averageSimilarMargin = q.Average_Similar_Margin__c; d.lastLaneRate = q.Last_Lane_Rate__c; d.lastLaneCost = q.Last_Lane_Cost__c;
        d.customerContextSummary = q.Customer_Context_Summary__c; d.shipmentContextSummary = q.Shipment_Context_Summary__c; d.pricingLog = q.Pricing_Log__c; d.overrideReason = q.Override_Reason__c; d.approvalComments = q.Approval_Comments__c; d.winLossReason = q.Win_Loss_Reason__c;
        d.tariffRate = q.Tariff_Rate__c; d.tariffSource = q.Tariff_Source__c; d.tariffMatchDetail = q.Tariff_Match_Detail__c; d.contractContext = q.Contract_Context__c; d.contractAdjustmentPercent = q.Contract_Adjustment_Percent__c; d.accessorialRisk = q.Accessorial_Risk__c; d.accessorialRiskSummary = q.Accessorial_Risk_Summary__c; d.serviceIssueRisk = q.Service_Issue_Risk__c; d.serviceIssueSummary = q.Service_Issue_Summary__c; d.quoteHistorySummary = q.Quote_History_Summary__c; d.priorQuoteCount = q.Prior_Quote_Count__c; d.quoteWinRate = q.Quote_Win_Rate__c; d.recommendedAction = q.Recommended_Action__c;
        d.blockingMessages = getSendBlockers(q); d.warningMessages = getWarnings(q, hist); d.historyRows = hist.rows;
        Boolean converted = q.Converted_Load__c != null || d.workflowStatus == 'Converted to Load';
        Boolean accepted = q.Customer_Response__c == 'Accepted' || d.workflowStatus == 'Accepted';
        Boolean declined = q.Customer_Response__c == 'Declined' || d.workflowStatus == 'Declined';
        Boolean approvalPending = q.Approval_Status__c == 'Pending';
        Boolean approvalApproved = q.Approval_Status__c == 'Approved';
        Boolean approvalRejected = q.Approval_Status__c == 'Rejected';
        Boolean approvalOk = q.Approval_Required__c != true || approvalApproved || q.Approval_Status__c == 'Not Required';
        Boolean sent = d.workflowStatus == 'Sent';
        Boolean readyToSend = d.workflowStatus == READY_TO_SEND || d.workflowStatus == 'Approved';

        d.pricingLocked = converted || accepted || declined || sent || approvalPending || approvalApproved || readyToSend;
        d.canCalculate = !d.pricingLocked;
        d.canRequestApproval = !converted && !accepted && !declined && !sent &&
            (q.Approval_Required__c == true || d.marginStatus == 'Approval Required' || d.marginStatus == 'Negative Margin') &&
            !approvalPending && !approvalApproved && !approvalRejected;
        d.canApprove = !converted && !accepted && !declined && !sent && approvalPending;
        d.canMarkSent = !converted && !accepted && !declined && !sent && approvalOk && !approvalRejected && d.blockingMessages.isEmpty();
        d.canMarkAccepted = !converted && !accepted && !declined && sent;
        d.canMarkDeclined = !converted && !accepted && !declined && sent;
        d.canConvertToLoad = !converted && accepted;
        d.nextAction = determineNextAction(d, approvalPending, approvalApproved, approvalRejected, sent, accepted, declined, converted);
        return d;
    }

    private static CalculationResult calculateQuoteValues(FreightTM__Lane_Quote__c q) {
        CalculationResult r = new CalculationResult();
        r.minMargin = q.Minimum_Margin_Percent__c == null ? DEFAULT_MIN_MARGIN : q.Minimum_Margin_Percent__c;
        r.targetMargin = q.Target_Margin_Percent__c == null ? DEFAULT_TARGET_MARGIN : q.Target_Margin_Percent__c;
        r.history = buildHistory(q); r.similarHistory = buildSimilarHistory(q, r.history.loadIds); r.tariff = findBestTariff(q); r.contractContext = getContractContext(q); r.quoteHistory = buildQuoteHistory(q);
        if (r.contractContext != null && r.contractContext.active) {
            if (r.contractContext.minimumMarginPercent != null) r.minMargin = r.contractContext.minimumMarginPercent;
            if (r.contractContext.targetMarginPercent != null) r.targetMargin = r.contractContext.targetMarginPercent;
        }
        r.quotePayCost = sumQuotePay(q.Id); r.quoteLegPayCost = sumQuoteLegPayments(q.Id);
        Decimal directCost = firstPositive(new List<Decimal>{ q.FreightTM__Rate_to_Carrier__c, r.quotePayCost, r.quoteLegPayCost, r.history.avgCost, r.similarHistory.avgCost });
        Decimal suggested = null; String source = null; String explanation = null;
        if (r.tariff != null && r.tariff.rate != null && r.tariff.rate > 0) {
            suggested = r.tariff.rate; source = 'Tariff Table'; explanation = 'Matched FreightTM Tariff by origin/destination. ' + r.tariff.detail;
        } else if (r.history.loadCount >= 2 && r.history.avgRate != null) {
            suggested = r.history.avgRate; source = 'Exact Lane History'; explanation = 'Used ' + r.history.loadCount + ' exact prior loads for this customer lane.';
        } else if (r.similarHistory.loadCount > 0 && r.similarHistory.avgRate != null) {
            suggested = r.similarHistory.avgRate; source = 'Similar Shipment History'; explanation = 'No strong exact lane match. Used ' + r.similarHistory.loadCount + ' similar customer shipments.';
        } else if (directCost != null && directCost > 0) {
            suggested = rateFromCostAndTargetMargin(directCost, r.targetMargin); source = (q.FreightTM__Rate_to_Carrier__c != null ? 'Carrier Cost + Target Margin' : 'Quote Pay Cost + Target Margin'); explanation = 'Built rate from available carrier cost and target margin.';
        } else {
            suggested = fallbackRuleEstimate(q); source = 'Fallback Rule'; explanation = 'No tariff, contract price, exact lane, similar lane, or carrier cost was available. Used weight, pallets, equipment, and service fallback. Manager review recommended.';
        }
        if (r.contractContext != null && r.contractContext.active && r.contractContext.discountPercent != null && suggested != null) {
            suggested = suggested * (1 - (r.contractContext.discountPercent / 100));
            source = source + ' + Contract / Customer Terms';
            explanation += ' Contract terms adjusted rate by ' + r.contractContext.discountPercent.setScale(2) + '%.';
        }
        r.suggestedRate = suggested == null ? null : suggested.setScale(2);
        if (directCost == null && r.suggestedRate != null) directCost = (r.suggestedRate * (1 - (r.targetMargin / 100))).setScale(2);
        r.carrierCost = directCost == null ? null : directCost.setScale(2);
        r.rateUsedForMargin = q.FreightTM__Customer_Rate__c == null ? r.suggestedRate : q.FreightTM__Customer_Rate__c;
        r.pricingSource = source; r.pricingExplanation = explanation; r.confidence = confidenceFrom(r, source);
        r.accessorialRisk = riskLevel(r.history.accessorialSignalCount + r.similarHistory.accessorialSignalCount, r.history.loadCount + r.similarHistory.loadCount); r.accessorialSummary = buildAccessorialSummary(r);
        r.serviceRisk = riskLevel(r.history.serviceIssueCount + r.similarHistory.serviceIssueCount + r.history.lateCount + r.similarHistory.lateCount, r.history.loadCount + r.similarHistory.loadCount); r.serviceSummary = buildServiceSummary(r);
        if (r.rateUsedForMargin == null || r.rateUsedForMargin <= 0) { r.marginStatus = 'Missing Rate'; r.recommendedAction = 'Add shipment/rate context or review fallback before sending.'; r.pricingLog = buildPricingLog(q, r); return r; }
        if (r.carrierCost == null || r.carrierCost <= 0) { r.marginStatus = 'Missing Cost'; r.recommendedAction = 'Add carrier cost, Quote Pay, tariff, or manager review before sending.'; r.pricingLog = buildPricingLog(q, r); return r; }
        r.grossProfit = (r.rateUsedForMargin - r.carrierCost).setScale(2); r.marginPercent = ((r.grossProfit / r.rateUsedForMargin) * 100).setScale(2);
        r.approvalRequired = r.marginPercent < r.minMargin || r.accessorialRisk == 'High' || r.serviceRisk == 'High' || !String.isBlank(q.Override_Reason__c) || (source != null && source.startsWith('Fallback Rule'));
        if (r.marginPercent < 0) r.marginStatus = 'Negative Margin'; else if (r.approvalRequired) r.marginStatus = 'Approval Required'; else if (r.marginPercent < r.targetMargin) r.marginStatus = 'Watch'; else r.marginStatus = 'Healthy';
        r.recommendedAction = r.approvalRequired ? 'Request approval before sending.' : 'Ready to send after final review.';
        r.pricingLog = buildPricingLog(q, r); return r;
    }

    private static TariffMatch findBestTariff(FreightTM__Lane_Quote__c q) {
        if (String.isBlank(q.FreightTM__Pickup_City__c) && String.isBlank(q.FreightTM__Pickup_State__c) && String.isBlank(q.FreightTM__Pickup_Zip_Code__c)) return null;
        if (String.isBlank(q.FreightTM__Delivery_City__c) && String.isBlank(q.FreightTM__Delivery_State__c) && String.isBlank(q.FreightTM__Delivery_Zip_Code__c)) return null;

        List<FreightTM__Tariff__c> tariffs = [
            SELECT Id, Name, FreightTM__Origin__c, FreightTM__Destination__c, FreightTM__Rate__c,
                   FreightTM__Type__c, FreightTM__Carrier__c, FreightTM__Carrier__r.Name
            FROM FreightTM__Tariff__c
            WHERE FreightTM__Rate__c != null
            LIMIT 500
        ];

        TariffMatch best;
        for (FreightTM__Tariff__c t : tariffs) {
            Integer originScore = locationMatchScore(t.FreightTM__Origin__c, q.FreightTM__Pickup_City__c, q.FreightTM__Pickup_State__c, q.FreightTM__Pickup_Zip_Code__c, q.FreightTM__Pickup_3_Zip__c);
            Integer destinationScore = locationMatchScore(t.FreightTM__Destination__c, q.FreightTM__Delivery_City__c, q.FreightTM__Delivery_State__c, q.FreightTM__Delivery_Zip_Code__c, q.FreightTM__Delivery_3_Zip__c);
            if (originScore < 0 || destinationScore < 0) continue;

            // A carrier-specific tariff must never be used for another carrier or for an
            // unassigned quote. Generic tariffs remain eligible for every quote.
            if (t.FreightTM__Carrier__c != null && t.FreightTM__Carrier__c != q.FreightTM__Carrier__c) continue;
            if (!String.isBlank(t.FreightTM__Type__c) && !typeMatches(q, t.FreightTM__Type__c)) continue;

            Integer score = originScore + destinationScore;
            if (t.FreightTM__Carrier__c != null && t.FreightTM__Carrier__c == q.FreightTM__Carrier__c) score += 25;
            if (!String.isBlank(t.FreightTM__Type__c)) score += 12;
            else score += 3;

            if (best == null || score > best.score) {
                best = new TariffMatch();
                best.rate = t.FreightTM__Rate__c;
                best.score = score;
                best.source = t.Name;
                best.detail = 'Tariff ' + t.Name + ' matched ' + t.FreightTM__Origin__c + ' → ' + t.FreightTM__Destination__c +
                    '. Type: ' + blankToDash(t.FreightTM__Type__c) + '. Carrier: ' +
                    (t.FreightTM__Carrier__r == null ? 'Any' : t.FreightTM__Carrier__r.Name) + '. Match score: ' + score + '.';
            }
        }
        return best;
    }

    private static ContractContext getContractContext(FreightTM__Lane_Quote__c q) {
        ContractContext c = new ContractContext();
        if (q.FreightTM__Contract__c == null) { c.summary = 'No contract selected on this Lane Quote.'; return c; }
        List<Contract> rows = [SELECT Id, Name, AccountId, Status, StartDate, EndDate, ContractTerm, SpecialTerms FROM Contract WHERE Id = :q.FreightTM__Contract__c LIMIT 1];
        if (rows.isEmpty()) { c.summary = 'Contract lookup is populated, but contract could not be read.'; return c; }
        Contract con = rows[0];
        Date today = Date.today();
        Boolean activeByDate = (con.StartDate == null || con.StartDate <= today) && (con.EndDate == null || con.EndDate >= today);
        Boolean customerMatches = con.AccountId == null || con.AccountId == q.FreightTM__Customer__c;
        c.active = activeByDate && customerMatches;
        c.discountPercent = extractPercent(con.SpecialTerms, new List<String>{'discount', 'rebate'});
        c.targetMarginPercent = extractPercent(con.SpecialTerms, new List<String>{'target margin', 'target'});
        c.minimumMarginPercent = extractPercent(con.SpecialTerms, new List<String>{'minimum margin', 'min margin', 'floor'});
        List<String> parts = new List<String>{
            'Contract: ' + con.Name,
            'Status: ' + blankToDash(con.Status),
            'Active by dates: ' + String.valueOf(activeByDate),
            'Matches selected customer: ' + String.valueOf(customerMatches),
            'Eligible for pricing: ' + String.valueOf(c.active),
            'Start: ' + String.valueOf(con.StartDate),
            'End: ' + String.valueOf(con.EndDate)
        };
        if (c.discountPercent != null) parts.add('Parsed discount/rebate: ' + c.discountPercent + '%'); if (c.targetMarginPercent != null) parts.add('Parsed target margin: ' + c.targetMarginPercent + '%'); if (c.minimumMarginPercent != null) parts.add('Parsed minimum margin: ' + c.minimumMarginPercent + '%'); if (!String.isBlank(con.SpecialTerms)) parts.add('Special terms: ' + con.SpecialTerms.left(1000));
        c.summary = String.join(parts, '\n'); return c;
    }

    private static QuoteHistorySummary buildQuoteHistory(FreightTM__Lane_Quote__c q) {
        QuoteHistorySummary s = new QuoteHistorySummary();
        if (q.FreightTM__Customer__c == null || String.isBlank(q.FreightTM__Pickup_City__c) || String.isBlank(q.FreightTM__Delivery_City__c)) {
            s.summary = 'Customer, pickup city, and delivery city are required before quote outcome history can be evaluated.';
            return s;
        }

        List<FreightTM__Lane_Quote__c> qs = [
            SELECT Id, Customer_Response__c, Quote_Workflow_Status__c, Estimated_Margin_Percent__c
            FROM FreightTM__Lane_Quote__c
            WHERE Id != :q.Id
              AND FreightTM__Customer__c = :q.FreightTM__Customer__c
              AND FreightTM__Pickup_City__c = :q.FreightTM__Pickup_City__c
              AND FreightTM__Delivery_City__c = :q.FreightTM__Delivery_City__c
            LIMIT 200
        ];

        Decimal marginTotal = 0;
        Integer marginCount = 0;
        for (FreightTM__Lane_Quote__c oldQ : qs) {
            s.priorQuoteCount++;
            String state = (String.valueOf(oldQ.Customer_Response__c) + ' ' + String.valueOf(oldQ.Quote_Workflow_Status__c)).toLowerCase();
            if (state.contains('accepted') || state.contains('converted')) s.wonCount++;
            else if (state.contains('declined') || state.contains('lost')) s.lostCount++;
            if (oldQ.Estimated_Margin_Percent__c != null) {
                marginTotal += oldQ.Estimated_Margin_Percent__c;
                marginCount++;
            }
        }

        Integer decidedCount = s.wonCount + s.lostCount;
        if (decidedCount > 0) s.winRate = ((Decimal.valueOf(s.wonCount) / Decimal.valueOf(decidedCount)) * 100).setScale(2);
        if (marginCount > 0) s.avgMargin = (marginTotal / marginCount).setScale(2);
        s.summary = 'Prior quotes on same customer lane: ' + s.priorQuoteCount +
            '\nDecided quotes: ' + decidedCount +
            '\nWon/converted: ' + s.wonCount +
            '\nDeclined/lost: ' + s.lostCount +
            '\nWin rate: ' + percentText(s.winRate) +
            '\nAverage quote margin: ' + percentText(s.avgMargin);
        return s;
    }

    private static HistorySummary buildHistory(FreightTM__Lane_Quote__c q) {
        HistorySummary s = new HistorySummary();
        if (q.FreightTM__Customer__c == null || String.isBlank(q.FreightTM__Pickup_City__c) || String.isBlank(q.FreightTM__Delivery_City__c)) {
            s.warning = 'Customer, pickup city, and delivery city are required before exact lane history can be evaluated.';
            return s;
        }

        List<FreightTM__Load__c> loads = [
            SELECT Id, Name, FreightTM__Status__c, FreightTM__Pickup_Date__c, FreightTM__Delivery_Date__c,
                   FreightTM__Delivery_Departure__c, FreightTM__Pickup_Arrival__c, FreightTM__Rate__c,
                   FreightTM__Rate_to_Carrier__c, FreightTM__Total__c, FreightTM__Total_Rate_to_Carrier__c,
                   FreightTM__Total_Line_Items__c, FreightTM__Total_Pay_Items__c, Exception_Reason__c,
                   POD_Received__c, FreightTM__Bill_Status__c, FreightTM__Pay_Status__c, FreightTM__Invoice_Status__c
            FROM FreightTM__Load__c
            WHERE FreightTM__Customer__c = :q.FreightTM__Customer__c
              AND FreightTM__Pickup_City__c = :q.FreightTM__Pickup_City__c
              AND FreightTM__Delivery_City__c = :q.FreightTM__Delivery_City__c
              AND FreightTM__Load_Canceled__c = false
            ORDER BY CreatedDate DESC
            LIMIT :HISTORY_LIMIT
        ];
        summarizeLoads(s, loads);

        if (s.loadCount == 0) {
            s.warning = 'No exact prior loads found for this customer lane. Similar shipment, tariff, contract, and fallback pricing were checked.';
            return s;
        }

        Decimal currentRate = firstPositive(new List<Decimal>{q.FreightTM__Customer_Rate__c, q.Suggested_Rate__c});
        if (currentRate != null && s.avgRate != null && s.avgRate > 0) {
            Decimal variance = (((currentRate - s.avgRate) / s.avgRate) * 100).setScale(2);
            if (variance >= 20) s.warning = 'Current customer rate is ' + variance + '% above the exact-lane average.';
            else if (variance <= -20) s.warning = 'Current customer rate is ' + variance.abs() + '% below the exact-lane average.';
        }
        return s;
    }

    private static HistorySummary buildSimilarHistory(FreightTM__Lane_Quote__c q, Set<Id> exactLoadIds) {
        HistorySummary s = new HistorySummary();
        if (q.FreightTM__Customer__c == null) {
            s.warning = 'Customer is required before similar shipment history can be evaluated.';
            return s;
        }

        Id customerId = q.FreightTM__Customer__c;
        String pickupCity = q.FreightTM__Pickup_City__c;
        String pickupState = q.FreightTM__Pickup_State__c;
        String deliveryCity = q.FreightTM__Delivery_City__c;
        String deliveryState = q.FreightTM__Delivery_State__c;
        Set<Id> excludedLoadIds = exactLoadIds == null ? new Set<Id>() : exactLoadIds;
        List<String> matchConditions = new List<String>();
        if (!String.isBlank(pickupCity)) matchConditions.add('FreightTM__Pickup_City__c = :pickupCity');
        if (!String.isBlank(pickupState)) matchConditions.add('FreightTM__Pickup_State__c = :pickupState');
        if (!String.isBlank(deliveryCity)) matchConditions.add('FreightTM__Delivery_City__c = :deliveryCity');
        if (!String.isBlank(deliveryState)) matchConditions.add('FreightTM__Delivery_State__c = :deliveryState');
        if (matchConditions.isEmpty()) {
            s.warning = 'Pickup or delivery city/state is required before similar shipment history can be evaluated.';
            return s;
        }

        String soql = 'SELECT Id, Name, FreightTM__Status__c, FreightTM__Pickup_Date__c, FreightTM__Delivery_Date__c, ' +
            'FreightTM__Delivery_Departure__c, FreightTM__Pickup_Arrival__c, FreightTM__Rate__c, ' +
            'FreightTM__Rate_to_Carrier__c, FreightTM__Total__c, FreightTM__Total_Rate_to_Carrier__c, ' +
            'FreightTM__Total_Line_Items__c, FreightTM__Total_Pay_Items__c, Exception_Reason__c, ' +
            'POD_Received__c, FreightTM__Bill_Status__c, FreightTM__Pay_Status__c, FreightTM__Invoice_Status__c ' +
            'FROM FreightTM__Load__c WHERE FreightTM__Customer__c = :customerId AND FreightTM__Load_Canceled__c = false ';
        if (!excludedLoadIds.isEmpty()) soql += 'AND Id NOT IN :excludedLoadIds ';
        soql += 'AND (' + String.join(matchConditions, ' OR ') + ') ORDER BY CreatedDate DESC LIMIT ' + HISTORY_LIMIT;

        List<FreightTM__Load__c> loads = Database.query(soql);
        summarizeLoads(s, loads);
        s.warning = s.loadCount == 0 ? 'No similar shipments found for this customer route context.' : null;
        return s;
    }

    private static void summarizeLoads(HistorySummary s, List<FreightTM__Load__c> loads) {
        Decimal rateTotal = 0, costTotal = 0, marginTotal = 0; Integer rateCount = 0, costCount = 0, marginCount = 0;
        for (FreightTM__Load__c l : loads) { s.loadIds.add(l.Id); Decimal rate = l.FreightTM__Rate__c == null ? l.FreightTM__Total__c : l.FreightTM__Rate__c; Decimal cost = l.FreightTM__Rate_to_Carrier__c == null ? l.FreightTM__Total_Rate_to_Carrier__c : l.FreightTM__Rate_to_Carrier__c; Decimal m = null; if (rate != null && rate > 0 && cost != null) m = (((rate - cost) / rate) * 100).setScale(2); if (rate != null) { rateTotal += rate; rateCount++; } if (cost != null) { costTotal += cost; costCount++; } if (m != null) { marginTotal += m; marginCount++; } if (l.FreightTM__Total_Line_Items__c != null && l.FreightTM__Total_Line_Items__c > 0) s.accessorialSignalCount++; if (l.FreightTM__Total_Pay_Items__c != null && l.FreightTM__Total_Pay_Items__c > 0) s.accessorialSignalCount++; if (!String.isBlank(l.Exception_Reason__c)) s.serviceIssueCount++; if (l.POD_Received__c == false) s.podMissingCount++; if (l.FreightTM__Delivery_Date__c != null && l.FreightTM__Delivery_Departure__c != null && l.FreightTM__Delivery_Departure__c.date() > l.FreightTM__Delivery_Date__c) s.lateCount++; HistoryRowDTO row = new HistoryRowDTO(); row.loadId = String.valueOf(l.Id); row.loadNumber = l.Name; row.status = l.FreightTM__Status__c; row.pickupDate = formatDate(l.FreightTM__Pickup_Date__c); row.deliveryDate = formatDate(l.FreightTM__Delivery_Date__c); row.rate = rate; row.carrierCost = cost; row.marginPercent = m; s.rows.add(row); }
        s.loadCount = loads.size(); s.avgRate = rateCount == 0 ? null : (rateTotal / rateCount).setScale(2); s.avgCost = costCount == 0 ? null : (costTotal / costCount).setScale(2); s.avgMargin = marginCount == 0 ? null : (marginTotal / marginCount).setScale(2); if (!s.rows.isEmpty()) { s.lastRate = s.rows[0].rate; s.lastCost = s.rows[0].carrierCost; }
    }

    private static Decimal sumQuotePay(Id quoteId) { Decimal t = 0; Integer c = 0; for (FreightTM__Quote_Pay__c p : [SELECT FreightTM__Amount__c FROM FreightTM__Quote_Pay__c WHERE FreightTM__Lane_Quote__c = :quoteId LIMIT 200]) { if (p.FreightTM__Amount__c != null) { t += p.FreightTM__Amount__c; c++; } } return c == 0 ? null : t.setScale(2); }
    private static Decimal sumQuoteLegPayments(Id quoteId) { Set<Id> legIds = new Set<Id>(); for (FreightTM__Quote_Leg__c leg : [SELECT Id FROM FreightTM__Quote_Leg__c WHERE FreightTM__Lane_Quote__c = :quoteId LIMIT 200]) legIds.add(leg.Id); if (legIds.isEmpty()) return null; Decimal t = 0; Integer c = 0; for (FreightTM__Quote_Leg_Payment__c p : [SELECT FreightTM__Amount__c FROM FreightTM__Quote_Leg_Payment__c WHERE FreightTM__Quote_Leg__c IN :legIds LIMIT 500]) { if (p.FreightTM__Amount__c != null) { t += p.FreightTM__Amount__c; c++; } } return c == 0 ? null : t.setScale(2); }

    private static List<String> getSendBlockers(FreightTM__Lane_Quote__c q) { List<String> b = getCoreQuoteBlockers(q); if (q.Estimated_Margin_Percent__c == null) b.add('Calculate margin before sending.'); if (q.Approval_Required__c == true && q.Approval_Status__c != 'Approved') b.add('Approval is required before sending.'); if (q.Approval_Status__c == 'Rejected') b.add('Approval was rejected. Revise the quote before sending.'); return b; }
    private static List<String> getApprovalRequestBlockers(FreightTM__Lane_Quote__c q) { List<String> b = getCoreQuoteBlockers(q); if (q.Estimated_Margin_Percent__c == null) b.add('Calculate margin before requesting approval.'); return b; }
    private static List<String> getCoreQuoteBlockers(FreightTM__Lane_Quote__c q) { List<String> b = new List<String>(); if (q.FreightTM__Customer__c == null) b.add('Customer is required.'); if (String.isBlank(q.FreightTM__Pickup_City__c)) b.add('Pickup city is required.'); if (String.isBlank(q.FreightTM__Delivery_City__c)) b.add('Delivery city is required.'); if (q.FreightTM__Estimated_Pickup_Time__c == null) b.add('Estimated pickup time is required.'); if (String.isBlank(q.Equipment_Type__c) && String.isBlank(q.FreightTM__Mode__c)) b.add('Equipment type or mode is required.'); if (q.FreightTM__Customer_Rate__c == null && q.Suggested_Rate__c == null) b.add('Customer rate or suggested rate is required.'); if (q.FreightTM__Rate_to_Carrier__c == null) b.add('Estimated carrier cost is required.'); return b; }
    private static List<String> getConversionBlockers(FreightTM__Lane_Quote__c q) { List<String> b = new List<String>(); if (q.FreightTM__Customer__c == null) b.add('Customer is required.'); if (String.isBlank(q.FreightTM__Pickup_City__c)) b.add('Pickup city is required.'); if (String.isBlank(q.FreightTM__Delivery_City__c)) b.add('Delivery city is required.'); if (q.FreightTM__Customer_Rate__c == null && q.Suggested_Rate__c == null) b.add('Customer rate or suggested rate is required.'); return b; }
    private static List<String> getWarnings(FreightTM__Lane_Quote__c q, HistorySummary h) { List<String> w = new List<String>(); if (h != null && !String.isBlank(h.warning)) w.add(h.warning); if (q.Accessorial_Risk__c == 'High') w.add('High accessorial risk from prior shipments.'); if (q.Service_Issue_Risk__c == 'High') w.add('High service issue risk from prior shipments.'); if (q.Approval_Required__c == true && q.Approval_Status__c != 'Approved') w.add('Approval is still required before send.'); if (!String.isBlank(q.Override_Reason__c)) w.add('Manual override was entered and should be reviewed.'); if (q.FreightTM__Customer_Rate__c != null && q.FreightTM__Rate_to_Carrier__c != null && q.FreightTM__Customer_Rate__c < q.FreightTM__Rate_to_Carrier__c) w.add('Customer rate is below estimated carrier cost.'); return w; }

    private static String buildCustomerContext(FreightTM__Lane_Quote__c q, ContractContext c, QuoteHistorySummary qh) { List<String> p = new List<String>(); p.add('Customer: ' + (q.FreightTM__Customer__r == null ? 'Not selected' : q.FreightTM__Customer__r.Name)); if (q.FreightTM__Customer__r != null) { p.add('Industry: ' + blankToDash(q.FreightTM__Customer__r.Industry)); p.add('Type: ' + blankToDash(q.FreightTM__Customer__r.Type)); p.add('Rating: ' + blankToDash(q.FreightTM__Customer__r.Rating)); } if (q.FreightTM__Contract__r != null) p.add('Contract selected: ' + q.FreightTM__Contract__r.Name); if (c != null && !String.isBlank(c.summary)) p.add(c.summary); if (qh != null && !String.isBlank(qh.summary)) p.add(qh.summary); return String.join(p, '\n'); }
    private static String buildShipmentContext(FreightTM__Lane_Quote__c q, HistorySummary h, HistorySummary sh) { List<String> p = new List<String>(); p.add('Route: ' + buildRoute(q)); if (!String.isBlank(q.Equipment_Type__c)) p.add('Equipment: ' + q.Equipment_Type__c); if (!String.isBlank(q.FreightTM__Mode__c)) p.add('Mode: ' + q.FreightTM__Mode__c); if (q.FreightTM__Weight__c != null) p.add('Weight: ' + q.FreightTM__Weight__c); if (q.Pallet_Count__c != null) p.add('Pallets: ' + q.Pallet_Count__c); if (!String.isBlank(q.Commodity__c)) p.add('Commodity: ' + q.Commodity__c); if (!String.isBlank(q.Service_Level__c)) p.add('Service level: ' + q.Service_Level__c); if (h != null) p.add('Exact prior loads: ' + h.loadCount); if (sh != null) p.add('Similar shipments: ' + sh.loadCount); return String.join(p, '\n'); }

    private static String buildAccessorialSummary(CalculationResult r) { Integer signals = r.history.accessorialSignalCount + r.similarHistory.accessorialSignalCount; Integer total = r.history.loadCount + r.similarHistory.loadCount; return 'Accessorial signals from prior loads: ' + signals + ' across ' + total + ' evaluated load(s). Signals come from total line/pay item counts on historical Loads.'; }
    private static String buildServiceSummary(CalculationResult r) { Integer issues = r.history.serviceIssueCount + r.similarHistory.serviceIssueCount; Integer late = r.history.lateCount + r.similarHistory.lateCount; Integer pod = r.history.podMissingCount + r.similarHistory.podMissingCount; Integer total = r.history.loadCount + r.similarHistory.loadCount; return 'Service signals from prior loads: exceptions=' + issues + ', late deliveries=' + late + ', POD missing=' + pod + ', evaluated loads=' + total + '.'; }
    private static String riskLevel(Integer signals, Integer total) { if (total == null || total == 0 || signals == null || signals == 0) return 'Low'; Decimal ratio = (Decimal.valueOf(signals) / Decimal.valueOf(total)) * 100; if (ratio >= 35) return 'High'; if (ratio >= 15) return 'Medium'; return 'Low'; }
    private static String confidenceFrom(CalculationResult r, String source) { if (source != null && source.startsWith('Tariff Table') && r.tariff != null && r.history.loadCount >= 2) return 'High'; if (source != null && source.startsWith('Tariff Table')) return 'Medium'; if (r.history.loadCount >= 5) return 'High'; if (r.history.loadCount >= 2) return 'Medium'; if (r.similarHistory.loadCount >= 5) return 'Medium'; if (r.history.loadCount > 0 || r.similarHistory.loadCount > 0) return 'Limited'; return 'Low'; }

    private static String buildPricingLog(FreightTM__Lane_Quote__c q, CalculationResult r) { List<String> p = new List<String>(); p.add('Pricing source: ' + blankToDash(r.pricingSource)); p.add('Pricing confidence: ' + blankToDash(r.confidence)); p.add('System suggested rate: ' + moneyText(r.suggestedRate)); p.add('Rate used for margin: ' + moneyText(r.rateUsedForMargin)); p.add('Estimated carrier cost: ' + moneyText(r.carrierCost)); p.add('Gross profit: ' + moneyText(r.grossProfit)); p.add('Margin %: ' + percentText(r.marginPercent)); p.add('Minimum margin %: ' + percentText(r.minMargin)); p.add('Target margin %: ' + percentText(r.targetMargin)); p.add('Tariff rate: ' + (r.tariff == null ? '—' : moneyText(r.tariff.rate))); p.add('Quote Pay cost: ' + moneyText(r.quotePayCost)); p.add('Quote Leg Payment cost: ' + moneyText(r.quoteLegPayCost)); p.add('Exact lane history: ' + r.history.loadCount + ' load(s).'); p.add('Similar shipment history: ' + r.similarHistory.loadCount + ' load(s).'); p.add('Accessorial risk: ' + r.accessorialRisk); p.add('Service issue risk: ' + r.serviceRisk); if (!String.isBlank(r.pricingExplanation)) p.add('Explanation: ' + r.pricingExplanation); if (!String.isBlank(q.Override_Reason__c)) p.add('Manual override reason: ' + q.Override_Reason__c); return String.join(p, '\n'); }

    private static Decimal fallbackRuleEstimate(FreightTM__Lane_Quote__c q) { Decimal baseRate = 950; if (q.FreightTM__Weight__c != null && q.FreightTM__Weight__c > 0) { Decimal wr = (q.FreightTM__Weight__c * 0.08).setScale(2); if (wr > baseRate) baseRate = wr; } if (q.Pallet_Count__c != null && q.Pallet_Count__c > 0) baseRate += q.Pallet_Count__c * 35; String equip = lower(q.Equipment_Type__c); if (equip.contains('reefer')) baseRate *= 1.18; else if (equip.contains('flat')) baseRate *= 1.12; String svc = lower(q.Service_Level__c); if (svc.contains('exped')) baseRate *= 1.25; return baseRate.setScale(2); }
    private static Decimal rateFromCostAndTargetMargin(Decimal cost, Decimal targetMargin) { if (cost == null || cost <= 0) return null; Decimal d = 1 - ((targetMargin == null ? DEFAULT_TARGET_MARGIN : targetMargin) / 100); if (d <= 0) d = 0.8; return (cost / d).setScale(2); }
    private static Decimal firstPositive(List<Decimal> vals) { for (Decimal v : vals) if (v != null && v > 0) return v; return null; }
    private static Integer locationMatchScore(String tariffLocation, String city, String state, String zip, String zip3) {
        String tariffValue = norm(tariffLocation);
        if (String.isBlank(tariffValue)) return -1;

        String normalizedZip = norm(zip);
        String normalizedZip3 = norm(zip3);
        String normalizedCity = norm(city);
        String normalizedState = norm(state);

        if (!String.isBlank(normalizedZip) && (tariffValue == normalizedZip || tariffValue.contains(normalizedZip))) return 55;
        if (!String.isBlank(normalizedZip3) && tariffValue == normalizedZip3) return 48;
        if (!String.isBlank(normalizedCity) && !String.isBlank(normalizedState) && tariffValue.contains(normalizedCity) && tariffValue.contains(normalizedState)) return 42;
        if (!String.isBlank(normalizedCity) && tariffValue == normalizedCity) return 36;
        if (!String.isBlank(normalizedCity) && tariffValue.contains(normalizedCity)) return 32;
        if (!String.isBlank(normalizedState) && tariffValue == normalizedState) return 18;
        return -1;
    }

    private static void ensurePricingEditable(FreightTM__Lane_Quote__c quoteRec) {
        String workflow = lower(quoteRec.Quote_Workflow_Status__c);
        String response = lower(quoteRec.Customer_Response__c);
        String approval = lower(quoteRec.Approval_Status__c);
        if (quoteRec.Converted_Load__c != null || workflow.contains('converted')) {
            throw new AuraHandledException('A converted quote cannot be recalculated or sent again. Create a new quote for revised pricing.');
        }
        if (workflow == 'sent' || workflow == 'accepted' || workflow == 'declined' || response == 'accepted' || response == 'declined') {
            throw new AuraHandledException('This quote already has a customer-facing outcome. Create a new quote or revision before changing pricing.');
        }
        if (approval == 'pending') {
            throw new AuraHandledException('Pricing is locked while approval is pending. Reject the request before revising the quote.');
        }
        if (approval == 'approved' || workflow == lower(READY_TO_SEND) || workflow == 'approved') {
            throw new AuraHandledException('This quote is approved and ready to send. Create a revision before changing pricing.');
        }
    }

    private static String determineNextAction(QuoteDataDTO d, Boolean approvalPending, Boolean approvalApproved, Boolean approvalRejected, Boolean sent, Boolean accepted, Boolean declined, Boolean converted) {
        if (converted) return 'Workflow complete. The quote has been converted to a Load.';
        if (accepted) return 'Convert the accepted quote to a Load.';
        if (declined) return 'Review the loss reason before creating a revised quote.';
        if (sent) return 'Record whether the customer accepted or declined the quote.';
        if (approvalPending) return 'Approval is pending. Approve or reject the request.';
        if (approvalRejected) return 'Revise the quote fields, save, and calculate again.';
        if (d.blockingMessages != null && !d.blockingMessages.isEmpty()) {
            String firstBlocker = d.blockingMessages[0];
            if (approvalApproved || d.workflowStatus == READY_TO_SEND || d.workflowStatus == 'Approved') {
                return 'Approval is complete, but Mark Sent is blocked: ' + firstBlocker;
            }
            return 'Fix the required items before continuing: ' + firstBlocker;
        }
        if (approvalApproved || d.workflowStatus == READY_TO_SEND || d.workflowStatus == 'Approved') return 'Approval is complete. Mark the quote sent.';
        if (d.canRequestApproval) return 'Request approval for this quote.';
        if (d.estimatedMarginPercent != null) return 'Review the final rate and mark the quote sent.';
        return 'Complete the quote fields, save, and calculate the price.';
    }

    private static Set<String> normalizedCandidates(List<String> vals) { Set<String> s = new Set<String>(); for (String v : vals) { String n = norm(v); if (!String.isBlank(n)) s.add(n); } return s; }
    private static String norm(String v) { return String.isBlank(v) ? '' : v.trim().toLowerCase(); }
    private static String lower(String v) { return String.isBlank(v) ? '' : v.toLowerCase(); }
    private static Boolean typeMatches(FreightTM__Lane_Quote__c q, String tariffType) { if (String.isBlank(tariffType)) return true; String t = lower(tariffType); return (!String.isBlank(q.Equipment_Type__c) && t.contains(lower(q.Equipment_Type__c))) || (!String.isBlank(q.FreightTM__Mode__c) && t.contains(lower(q.FreightTM__Mode__c))) || (!String.isBlank(q.Service_Level__c) && t.contains(lower(q.Service_Level__c))); }
    private static Decimal extractPercent(String text, List<String> keywords) { if (String.isBlank(text)) return null; String l = text.toLowerCase(); for (String k : keywords) { Integer idx = l.indexOf(k.toLowerCase()); if (idx >= 0) { Integer endIdx = idx + 80; if (endIdx > l.length()) endIdx = l.length(); String tail = l.substring(idx, endIdx); Matcher m = Pattern.compile('(\\d+(?:\\.\\d+)?)\\s*%').matcher(tail); if (m.find()) return Decimal.valueOf(m.group(1)); } } return null; }
    private static String buildRoute(FreightTM__Lane_Quote__c q) { String p = joinParts(new List<String>{q.FreightTM__Pickup_City__c, q.FreightTM__Pickup_State__c, q.FreightTM__Pickup_Zip_Code__c}); String d = joinParts(new List<String>{q.FreightTM__Delivery_City__c, q.FreightTM__Delivery_State__c, q.FreightTM__Delivery_Zip_Code__c}); return (String.isBlank(p) ? 'Pickup not set' : p) + ' → ' + (String.isBlank(d) ? 'Delivery not set' : d); }
    private static String buildLoadRemarks(FreightTM__Lane_Quote__c q) { return 'Created from Lane Quote ' + q.Name + '.\nOriginal customer rate: ' + String.valueOf(q.FreightTM__Customer_Rate__c == null ? q.Suggested_Rate__c : q.FreightTM__Customer_Rate__c) + '\nOriginal estimated carrier cost: ' + String.valueOf(q.FreightTM__Rate_to_Carrier__c) + '\nOriginal estimated margin %: ' + String.valueOf(q.Estimated_Margin_Percent__c) + '\nPricing source: ' + q.Pricing_Source__c + '\nPricing explanation: ' + q.Pricing_Explanation__c; }
    private static ActionResultDTO result(Boolean success, String message, Id quoteId) { ActionResultDTO r = new ActionResultDTO(); r.success = success; r.message = message; r.data = buildQuoteData(queryQuote(quoteId, false), true); return r; }
    private static void validateQuoteId(Id quoteId) { if (quoteId == null) throw new AuraHandledException('Lane Quote Id is required.'); if (quoteId.getSObjectType() != FreightTM__Lane_Quote__c.SObjectType) throw new AuraHandledException('This workspace must be opened on a Lane Quote record.'); }
    private static Boolean isAllowedPicklistValue(Schema.SObjectField f, String value) { if (String.isBlank(value)) return false; for (Schema.PicklistEntry e : f.getDescribe().getPicklistValues()) if (e.isActive() && e.getValue() == value) return true; return false; }
    private static String appendNote(String existing, String label, String note) { String line = '[' + System.now().format() + '] ' + label + ' by ' + UserInfo.getName(); if (!String.isBlank(note)) line += ': ' + note.trim(); String combined = String.isBlank(existing) ? line : existing + '\n' + line; return combined.length() > 32000 ? combined.substring(combined.length() - 32000) : combined; }
    private static String joinParts(List<String> parts) { List<String> c = new List<String>(); for (String p : parts) if (!String.isBlank(p)) c.add(p); return String.join(c, ', '); }
    private static String formatDate(Date v) { return v == null ? '—' : v.format(); }
    private static String formatDateTime(Datetime v) { return v == null ? '—' : v.format(); }
    private static String blankToDash(Object v) { return v == null || String.isBlank(String.valueOf(v)) ? '—' : String.valueOf(v); }
    private static String moneyText(Decimal v) { return v == null ? '—' : '$' + String.valueOf(v.setScale(2)); }
    private static String percentText(Decimal v) { return v == null ? '—' : String.valueOf(v.setScale(2)) + '%'; }
}