import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getQuoteData from '@salesforce/apex/FtmLaneQuoteWorkspaceController.getQuoteData';
import calculateQuote from '@salesforce/apex/FtmLaneQuoteWorkspaceController.calculateQuote';
import requestApproval from '@salesforce/apex/FtmLaneQuoteWorkspaceController.requestApproval';
import approveQuote from '@salesforce/apex/FtmLaneQuoteWorkspaceController.approveQuote';
import rejectApproval from '@salesforce/apex/FtmLaneQuoteWorkspaceController.rejectApproval';
import markSent from '@salesforce/apex/FtmLaneQuoteWorkspaceController.markSent';
import markAccepted from '@salesforce/apex/FtmLaneQuoteWorkspaceController.markAccepted';
import markDeclined from '@salesforce/apex/FtmLaneQuoteWorkspaceController.markDeclined';
import convertToLoad from '@salesforce/apex/FtmLaneQuoteWorkspaceController.convertToLoad';

export default class FtmLaneQuoteWorkspace extends NavigationMixin(LightningElement) {
    @api recordId;
    @track data;
    @track errorMessage;
    isLoading = false;
    actionInProgress = false;
    showNoteModal = false;
    noteValue = '';
    pendingAction = null;

    connectedCallback() {
        this.loadData();
    }

    @api
    refresh() {
        this.loadData();
    }

    get isBusy() {
        return this.isLoading || this.actionInProgress;
    }

    get calculateDisabled() {
        return this.isBusy || !this.data || !this.data.canCalculate;
    }

    get hasHistoryRows() {
        return this.data && this.data.historyRows && this.data.historyRows.length > 0;
    }

    get historyRowsForDisplay() {
        const rows = this.data?.historyRows || [];
        return rows.map((row) => ({
            ...row,
            formattedRate: this.formatCurrency(row.rate),
            formattedCarrierCost: this.formatCurrency(row.carrierCost),
            formattedMargin: this.formatPercent(row.marginPercent),
            marginClass: this.marginClassForValue(row.marginPercent)
        }));
    }

    get recentHistoryRows() {
        return this.historyRowsForDisplay.slice(0, 3);
    }

    get hasRecentHistory() {
        return this.recentHistoryRows.length > 0;
    }

    get requestApprovalDisabled() {
        return this.isBusy || !this.data || !this.data.canRequestApproval;
    }

    get approveDisabled() {
        return this.isBusy || !this.data || !this.data.canApprove;
    }

    get markSentDisabled() {
        return this.isBusy || !this.data || !this.data.canMarkSent;
    }

    get markAcceptedDisabled() {
        return this.isBusy || !this.data || !this.data.canMarkAccepted;
    }

    get markDeclinedDisabled() {
        return this.isBusy || !this.data || !this.data.canMarkDeclined;
    }

    get convertDisabled() {
        return this.isBusy || !this.data || !this.data.canConvertToLoad;
    }

    get safeCustomerName() { return this.data?.customerName || 'Not selected'; }
    get safeOwnerName() { return this.data?.ownerName || '—'; }
    get safeNativeStatus() { return this.data?.nativeStatus || '—'; }
    get safeMarginStatus() { return this.data?.marginStatus || 'Not calculated'; }
    get safeApprovalStatus() { return this.data?.approvalStatus || 'Not Requested'; }
    get safeCustomerResponse() { return this.data?.customerResponse || 'No Response'; }
    get safePricingConfidence() { return this.data?.pricingConfidence || 'Low'; }
    get safePricingSource() { return this.data?.pricingSource || 'Not calculated'; }
    get safeTariffSource() { return this.data?.tariffSource || 'No tariff matched'; }
    get safeTariffMatchDetail() { return this.data?.tariffMatchDetail || 'No tariff table match has been saved yet.'; }
    get safeContractContext() { return this.data?.contractContext || 'No contract context has been calculated yet.'; }
    get safeAccessorialRisk() { return this.data?.accessorialRisk || 'Low'; }
    get safeAccessorialRiskSummary() { return this.data?.accessorialRiskSummary || 'No accessorial history has been calculated yet.'; }
    get safeServiceIssueRisk() { return this.data?.serviceIssueRisk || 'Low'; }
    get safeServiceIssueSummary() { return this.data?.serviceIssueSummary || 'No service issue history has been calculated yet.'; }
    get safeQuoteHistorySummary() { return this.data?.quoteHistorySummary || 'No quote outcome history has been calculated yet.'; }
    get safeRecommendedAction() {
        const workflow = (this.data?.workflowStatus || '').toLowerCase();
        const approval = (this.data?.approvalStatus || '').toLowerCase();
        const response = (this.data?.customerResponse || '').toLowerCase();
        if (this.data?.convertedLoadId || workflow.includes('converted')) return 'Quote converted to a Load.';
        if (response === 'accepted' || workflow === 'accepted') return 'Customer accepted. Convert this quote to a Load.';
        if (response === 'declined' || workflow === 'declined') return 'Customer declined. Review the loss reason before revising.';
        if (workflow === 'sent') return 'Quote sent. Record the customer response.';
        if (approval === 'approved' || workflow === 'ready to send' || workflow === 'approved') {
            return this.hasBlockingMessages
                ? 'Approval is complete. Finish the required fields before sending.'
                : 'Approval is complete. Send this quote to the customer.';
        }
        if (approval === 'pending') return 'Waiting for an approval decision.';
        if (approval === 'rejected') return 'Revise the quote and calculate again.';
        return this.data?.recommendedAction || 'Calculate the quote to see the next recommended action.';
    }
    get safePricingExplanation() { return this.data?.pricingExplanation || 'Click Calculate Quote to let FTM check exact lane history, similar shipments, quote pay, carrier cost, and fallback pricing.'; }
    get safeSimilarShipmentCount() { return this.data?.similarShipmentCount ?? 0; }
    get safeCustomerContext() { return this.data?.customerContextSummary || 'Calculate the quote to refresh customer context.'; }
    get safeShipmentContext() { return this.data?.shipmentContextSummary || 'Calculate the quote to refresh shipment context.'; }
    get safePricingLog() { return this.data?.pricingLog || 'No calculation has been run yet.'; }
    get safeLastCalculatedAt() { return this.data?.lastCalculatedAt || 'Not calculated'; }
    get safeNextAction() { return this.data?.nextAction || 'Complete the quote fields, save, and calculate the price.'; }

    get customerRelationship() {
        const parts = [];
        if (this.data?.customerSinceYear) parts.push(`Customer since ${this.data.customerSinceYear}`);
        if (this.data?.customerTier) parts.push(this.data.customerTier);
        parts.push(`${this.data?.priorQuoteCount || 0} prior quote(s)`);
        return parts.join(' · ');
    }

    get equipmentSummary() {
        const parts = [];
        if (this.data?.equipmentType) parts.push(this.data.equipmentType);
        if (this.data?.serviceLevel) parts.push(this.data.serviceLevel);
        if (this.data?.palletCount !== null && this.data?.palletCount !== undefined) parts.push(`${this.data.palletCount} pallet(s)`);
        if (this.data?.weight !== null && this.data?.weight !== undefined) {
            parts.push(`${new Intl.NumberFormat('en-US').format(this.data.weight)} lb`);
        }
        return parts.length ? parts.join(' · ') : 'Equipment not set';
    }

    get historySummaryLabel() {
        const count = Number(this.data?.priorLoadCount || 0);
        return `${count} exact prior load${count === 1 ? '' : 's'} on this lane`;
    }

    get readinessText() {
        const status = (this.data?.workflowStatus || '').toLowerCase();
        const approval = (this.data?.approvalStatus || '').toLowerCase();
        if (status.includes('converted')) return `Converted to Load ${this.data?.convertedLoadName || ''}`.trim();
        if (status.includes('accepted')) return 'Customer accepted. This quote is ready to convert to a Load.';
        if (status.includes('declined')) return 'Customer declined. The loss reason is saved for future pricing intelligence.';
        if (status === 'sent') return 'Quote sent. Record the customer response when it arrives.';
        if ((status === 'ready to send' || approval === 'approved') && this.hasBlockingMessages) {
            return `Approval complete, but ${this.data.blockingMessages.length} required item(s) must be fixed before Mark Sent.`;
        }
        if (status === 'ready to send' || approval === 'approved') return 'Approval complete. The next step is Mark Sent.';
        if (approval === 'pending') return 'Approval is pending. Pricing is locked until a decision is recorded.';
        if (approval === 'rejected') return 'Approval was rejected. Revise the quote and calculate again.';
        if (this.hasBlockingMessages) return `${this.data.blockingMessages.length} item(s) must be fixed before continuing.`;
        if (this.data?.approvalRequired) return 'Approval is required before this quote can be sent.';
        if (this.data?.estimatedMarginPercent !== null && this.data?.estimatedMarginPercent !== undefined) return 'Pricing review complete. The quote is ready to send.';
        return 'Complete the quote intake, save, and calculate the recommended rate.';
    }

    get readinessBarClass() {
        const status = (this.data?.workflowStatus || '').toLowerCase();
        const approval = (this.data?.approvalStatus || '').toLowerCase();
        if (this.data?.convertedLoadId || this.data?.customerResponse === 'Accepted') return 'readiness-bar ready';
        if (this.data?.customerResponse === 'Declined' || approval === 'rejected' || this.safeMarginStatus === 'Negative Margin') return 'readiness-bar error';
        if (approval === 'pending' || this.hasBlockingMessages) return 'readiness-bar warning';
        if (status === 'ready to send' || approval === 'approved') return 'readiness-bar ready';
        if (this.data?.approvalRequired) return 'readiness-bar warning';
        if (this.data?.estimatedMarginPercent !== null && this.data?.estimatedMarginPercent !== undefined) return 'readiness-bar ready';
        return 'readiness-bar';
    }

    get readinessIcon() {
        if (this.readinessBarClass.includes('ready')) return 'utility:success';
        if (this.readinessBarClass.includes('error')) return 'utility:error';
        if (this.readinessBarClass.includes('warning')) return 'utility:warning';
        return 'utility:info';
    }

    get decisionPanelClass() {
        const state = this.visualState(this.safeDecisionStatus);
        return `decision-panel ${state}`.trim();
    }

    get decisionPillClass() {
        const state = this.visualState(this.safeDecisionStatus);
        return `decision-pill ${state}`.trim();
    }

    get safeDecisionStatus() {
        const workflow = (this.data?.workflowStatus || '').toLowerCase();
        const approval = (this.data?.approvalStatus || '').toLowerCase();
        if (this.data?.convertedLoadId || workflow.includes('converted')) return 'Converted';
        if (workflow === 'sent') return 'Sent';
        if (approval === 'approved' || workflow === 'ready to send' || workflow === 'approved') return 'Approved';
        if (approval === 'pending') return 'Approval Pending';
        if (approval === 'rejected') return 'Approval Rejected';
        return this.safeMarginStatus;
    }

    get marginMetricSubtitle() {
        const approval = (this.data?.approvalStatus || '').toLowerCase();
        if (approval === 'approved') return 'Approved';
        if (approval === 'pending') return 'Approval Pending';
        if (approval === 'rejected') return 'Approval Rejected';
        return this.safeMarginStatus;
    }

    get marginMetricClass() {
        const state = this.visualState(this.safeDecisionStatus);
        const suffix = state ? ` margin-${state}` : '';
        return `primary-metric${suffix}`;
    }

    get confidenceCardClass() {
        const confidence = (this.safePricingConfidence || '').toLowerCase();
        if (confidence === 'high') return 'intel-card success';
        if (confidence === 'medium') return 'intel-card highlight';
        if (confidence === 'limited') return 'intel-card warning';
        return 'intel-card';
    }

    get accessorialCardClass() {
        return this.riskCardClass(this.safeAccessorialRisk);
    }

    get serviceCardClass() {
        return this.riskCardClass(this.safeServiceIssueRisk);
    }

    get approvalCardClass() {
        const status = (this.safeApprovalStatus || '').toLowerCase();
        if (status === 'approved' || status === 'not required') return 'intel-card success';
        if (status === 'rejected') return 'intel-card error';
        if (status === 'pending' || this.data?.approvalRequired) return 'intel-card warning';
        return 'intel-card';
    }

    get workflowSteps() {
        const currentStage = this.workflowStage;
        const labels = ['Draft', 'Calculated', 'Approval', 'Ready to Send', 'Sent', 'Accepted', 'Load'];
        return labels.map((label, index) => {
            let className = 'workflow-step';
            if (index < currentStage) className += ' complete';
            if (index === currentStage) className += ' current';
            return {
                key: label.toLowerCase(),
                label,
                marker: index < currentStage ? '✓' : String(index + 1),
                className
            };
        });
    }

    get workflowStage() {
        const workflow = (this.data?.workflowStatus || '').toLowerCase();
        const response = (this.data?.customerResponse || '').toLowerCase();
        const approval = (this.data?.approvalStatus || '').toLowerCase();
        if (this.data?.convertedLoadId || workflow.includes('converted')) return 6;
        if (response === 'accepted' || workflow === 'accepted') return 5;
        if (workflow === 'sent') return 4;
        if (workflow === 'ready to send' || workflow === 'approved' || approval === 'approved') return 3;
        if (workflow.includes('approval') || approval === 'pending' || approval === 'rejected') return 2;
        if (this.data?.estimatedMarginPercent !== null && this.data?.estimatedMarginPercent !== undefined) return 1;
        return 0;
    }

    get approvalRequiredText() {
        const status = (this.data?.approvalStatus || '').toLowerCase();
        if (status === 'approved') return 'Approved. Ready to send';
        if (status === 'pending') return 'Waiting for a decision';
        if (status === 'rejected') return 'Revise and request again';
        return this.data?.approvalRequired ? 'Required before send' : 'No approval required';
    }

    get pricingModeText() {
        if (!this.data?.pricingLocked) return 'Save fields before calculating';
        const approval = (this.data?.approvalStatus || '').toLowerCase();
        if (approval === 'pending') return 'Fields locked while approval is pending';
        if (approval === 'approved') return 'Approved pricing is locked';
        return 'Quote fields are read-only in this stage';
    }

    get hasBlockingMessages() {
        return Boolean(this.data?.blockingMessages?.length);
    }

    get isTerminalWorkflow() {
        const workflow = (this.data?.workflowStatus || '').toLowerCase();
        const response = (this.data?.customerResponse || '').toLowerCase();
        return Boolean(this.data?.convertedLoadId) || workflow.includes('converted') ||
            workflow === 'declined' || response === 'declined';
    }

    get isSendStage() {
        const workflow = (this.data?.workflowStatus || '').toLowerCase();
        const approval = (this.data?.approvalStatus || '').toLowerCase();
        const hasCalculatedMargin = this.data?.estimatedMarginPercent !== null && this.data?.estimatedMarginPercent !== undefined;
        if (approval === 'pending' || approval === 'rejected') return false;
        if (this.data?.approvalRequired && approval !== 'approved') return false;
        return workflow === 'calculated' || workflow === 'ready to send' || workflow === 'approved' ||
            approval === 'approved' || hasCalculatedMargin;
    }

    get showCalculateAction() { return Boolean(this.data?.canCalculate); }
    get showRequestApprovalAction() { return Boolean(this.data?.canRequestApproval); }
    get showApprovalDecisionActions() { return Boolean(this.data?.canApprove); }
    get showMarkSentAction() { return Boolean(this.data?.canMarkSent) || this.isSendStage; }
    get showCustomerResponseActions() { return Boolean(this.data?.canMarkAccepted || this.data?.canMarkDeclined); }
    get showConvertAction() { return Boolean(this.data?.canConvertToLoad); }
    get showEditRequiredFieldsAction() { return this.hasBlockingMessages && !this.isTerminalWorkflow; }
    get showActionBlockerPanel() { return this.showEditRequiredFieldsAction; }
    get hasAvailableActions() {
        return this.showCalculateAction || this.showRequestApprovalAction || this.showApprovalDecisionActions ||
            this.showMarkSentAction || this.showCustomerResponseActions || this.showConvertAction ||
            this.showEditRequiredFieldsAction;
    }
    get markSentVariant() { return this.data?.canMarkSent ? 'brand' : 'neutral'; }

    get blockerPanelTitle() {
        if (this.isSendStage) return 'Mark Sent is waiting for required fields';
        return 'Complete the required fields to continue';
    }

    get blockerPanelMessage() {
        const blockers = this.data?.blockingMessages || [];
        if (!blockers.length) return '';
        const preview = blockers.slice(0, 2).join(' ');
        const remaining = blockers.length - 2;
        return remaining > 0 ? `${preview} Plus ${remaining} more item(s).` : preview;
    }

    get noActionMessage() {
        const workflow = (this.data?.workflowStatus || '').toLowerCase();
        const response = (this.data?.customerResponse || '').toLowerCase();
        if (this.data?.convertedLoadId || workflow.includes('converted')) return 'Workflow complete. This quote has been converted to a Load.';
        if (workflow === 'declined' || response === 'declined') return 'This quote was declined. Create a revision when new pricing is needed.';
        return 'No workflow action is available for the current record state.';
    }

    get workflowBadgeClass() {
        const status = (this.data?.workflowStatus || '').toLowerCase();
        if (status.includes('accepted') || status.includes('converted') || status === 'approved' || status === 'ready to send') return 'status-badge success';
        if (status.includes('approval') || status.includes('pending')) return 'status-badge warning';
        if (status.includes('declined') || status.includes('rejected') || status.includes('lost')) return 'status-badge error';
        return 'status-badge neutral';
    }

    get formattedCustomerRate() { return this.formatCurrency(this.data?.customerRate); }
    get formattedSuggestedRate() { return this.formatCurrency(this.data?.suggestedRate); }
    get formattedCarrierCost() { return this.formatCurrency(this.data?.estimatedCarrierCost); }
    get formattedAverageRate() { return this.formatCurrency(this.data?.averageLaneRate); }
    get formattedAverageCost() { return this.formatCurrency(this.data?.averageLaneCost); }
    get formattedMargin() { return this.formatPercent(this.data?.estimatedMarginPercent); }
    get formattedAverageMargin() { return this.formatPercent(this.data?.averageLaneMargin); }
    get formattedAverageSimilarRate() { return this.formatCurrency(this.data?.averageSimilarRate); }
    get formattedAverageSimilarCost() { return this.formatCurrency(this.data?.averageSimilarCost); }
    get formattedAverageSimilarMargin() { return this.formatPercent(this.data?.averageSimilarMargin); }
    get formattedTariffRate() { return this.formatCurrency(this.data?.tariffRate); }
    get formattedContractAdjustment() { return this.formatPercent(this.data?.contractAdjustmentPercent); }
    get formattedQuoteWinRate() { return this.formatPercent(this.data?.quoteWinRate); }
    get formattedLastLaneRate() { return this.formatCurrency(this.data?.lastLaneRate); }
    get formattedLastLaneCost() { return this.formatCurrency(this.data?.lastLaneCost); }

    get modalTitle() {
        if (this.pendingAction === 'requestApproval') return 'Request Approval';
        if (this.pendingAction === 'approve') return 'Approve Quote';
        if (this.pendingAction === 'rejectApproval') return 'Reject Approval';
        if (this.pendingAction === 'markAccepted') return 'Mark Accepted';
        if (this.pendingAction === 'markDeclined') return 'Mark Declined';
        return 'Add Note';
    }

    get modalLabel() {
        if (this.pendingAction === 'markDeclined') return 'Decline / loss reason';
        if (this.pendingAction === 'requestApproval') return 'Approval request note';
        return 'Note';
    }

    async loadData() {
        if (!this.recordId) return;
        this.isLoading = true;
        this.errorMessage = null;
        try {
            this.data = await getQuoteData({ quoteId: this.recordId });
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleCalculate() {
        await this.runAction(() => calculateQuote({ quoteId: this.recordId }), 'Quote calculated');
    }

    handleRequestApproval() { this.openNoteModal('requestApproval'); }
    handleApprove() { this.openNoteModal('approve'); }
    handleRejectApproval() { this.openNoteModal('rejectApproval'); }
    openDeclineModal() { this.openNoteModal('markDeclined'); }

    async handleMarkSent() {
        await this.runAction(() => markSent({ quoteId: this.recordId }), 'Quote marked sent');
    }

    async handleMarkAccepted() {
        this.openNoteModal('markAccepted');
    }

    async handleConvertToLoad() {
        await this.runAction(() => convertToLoad({ quoteId: this.recordId }), 'Quote converted to Load');
    }

    handleEditQuote() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'FreightTM__Lane_Quote__c',
                actionName: 'edit'
            }
        });
    }

    openNoteModal(actionName) {
        this.pendingAction = actionName;
        this.noteValue = '';
        this.showNoteModal = true;
    }

    closeNoteModal() {
        if (this.actionInProgress) return;
        this.showNoteModal = false;
        this.pendingAction = null;
        this.noteValue = '';
    }

    handleNoteChange(event) {
        this.noteValue = event.target.value;
    }

    async submitNoteAction() {
        const action = this.pendingAction;
        const note = this.noteValue;
        let succeeded = false;
        if (action === 'requestApproval') {
            succeeded = await this.runAction(() => requestApproval({ quoteId: this.recordId, note }), 'Approval requested');
        } else if (action === 'approve') {
            succeeded = await this.runAction(() => approveQuote({ quoteId: this.recordId, note }), 'Quote approved');
        } else if (action === 'rejectApproval') {
            succeeded = await this.runAction(() => rejectApproval({ quoteId: this.recordId, note }), 'Approval rejected');
        } else if (action === 'markAccepted') {
            succeeded = await this.runAction(() => markAccepted({ quoteId: this.recordId, note }), 'Quote accepted');
        } else if (action === 'markDeclined') {
            succeeded = await this.runAction(() => markDeclined({ quoteId: this.recordId, reason: note }), 'Quote declined');
        }
        if (succeeded) this.closeNoteModal();
    }

    async runAction(actionCallback, fallbackSuccessMessage) {
        this.actionInProgress = true;
        this.errorMessage = null;
        try {
            const result = await actionCallback();
            this.data = result?.data || this.data;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: result?.message || fallbackSuccessMessage,
                variant: 'success'
            }));
            return true;
        } catch (error) {
            const message = this.normalizeError(error);
            this.errorMessage = message;
            this.dispatchEvent(new ShowToastEvent({ title: 'Action failed', message, variant: 'error' }));
            return false;
        } finally {
            this.actionInProgress = false;
        }
    }

    handleNativeSave() {
        this.dispatchEvent(new ShowToastEvent({ title: 'Saved', message: 'Quote fields saved. Recalculate to refresh pricing.', variant: 'success' }));
        this.loadData();
    }

    handleNativeError(event) {
        this.errorMessage = event.detail?.message || 'Could not save quote fields.';
    }

    visualState(value) {
        const normalized = (value || '').toLowerCase();
        if (normalized.includes('negative') || normalized.includes('rejected') || normalized.includes('declined') || normalized.includes('missing')) return 'error';
        if (normalized.includes('approval') || normalized.includes('watch') || normalized.includes('pending')) return 'warning';
        if (normalized.includes('healthy') || normalized.includes('approved') || normalized.includes('accepted') || normalized.includes('converted')) return 'success';
        return '';
    }

    riskCardClass(value) {
        const risk = (value || '').toLowerCase();
        if (risk === 'high') return 'intel-card error';
        if (risk === 'medium') return 'intel-card warning';
        if (risk === 'low') return 'intel-card success';
        return 'intel-card';
    }

    marginClassForValue(value) {
        if (value === null || value === undefined || value === '') return 'margin-chip';
        const numericValue = Number(value);
        const minimum = Number(this.data?.minimumMarginPercent ?? 15);
        const target = Number(this.data?.targetMarginPercent ?? 20);
        if (numericValue < 0 || numericValue < minimum) return 'margin-chip error';
        if (numericValue < target) return 'margin-chip warning';
        return 'margin-chip success';
    }

    formatCurrency(value) {
        if (value === null || value === undefined || value === '') return '—';
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);
    }

    formatPercent(value) {
        if (value === null || value === undefined || value === '') return '—';
        const numberValue = Number(value);
        if (Number.isNaN(numberValue)) return `${value}%`;
        return `${new Intl.NumberFormat('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 2 }).format(numberValue)}%`;
    }

    normalizeError(error) {
        if (!error) return 'Something went wrong.';
        if (Array.isArray(error.body)) return error.body.map((e) => e.message).join(', ');
        if (error.body && typeof error.body.message === 'string') return error.body.message;
        if (typeof error.message === 'string') return error.message;
        return 'Something went wrong.';
    }
}