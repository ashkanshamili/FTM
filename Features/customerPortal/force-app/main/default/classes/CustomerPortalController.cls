public without sharing class CustomerPortalController {
    private static final String SITE_DASHBOARD_PAGE = 'dashboard';
    private static final String SITE_SHIPMENTS_PAGE = 'shipments';
    private static final String SITE_LOAD_PAGE = 'load';
    private static final String SITE_DOCUMENTS_PAGE = 'documents';
    private static final String SITE_INVOICES_PAGE = 'invoices';
    private static final String SITE_REQUESTS_PAGE = 'requests';
    private static final String BOL_PAGE_NAME = 'BOL';
    private static final String INVOICE_PAGE_NAME = 'Invoice';

    public class PortalContextDTO {
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public Id sessionId;
        @AuraEnabled public String customerName;
        @AuraEnabled public String contactName;
        @AuraEnabled public String contactEmail;
        @AuraEnabled public String accessMode;
        @AuraEnabled public Boolean loginRequired;
        @AuraEnabled public String loginUrl;
    }

    public class PortalSummaryDTO {
        @AuraEnabled public Integer activeShipments;
        @AuraEnabled public Integer delivered30;
        @AuraEnabled public Decimal onTimeRate;
        @AuraEnabled public Integer documentCount;
        @AuraEnabled public Integer invoiceCount;
        @AuraEnabled public Integer requestCount;
    }

    public class PortalDataDTO {
        @AuraEnabled public PortalContextDTO context;
        @AuraEnabled public PortalSummaryDTO summary;
        @AuraEnabled public List<ShipmentDTO> shipments;
        @AuraEnabled public ShipmentDTO selectedLoad;
        @AuraEnabled public List<DocumentDTO> documents;
        @AuraEnabled public List<InvoiceDTO> invoices;
        @AuraEnabled public List<RequestDTO> requests;
    }

    public class ShipmentDTO {
        @AuraEnabled public String loadId;
        @AuraEnabled public String loadNumber;
        @AuraEnabled public String route;
        @AuraEnabled public String pickupText;
        @AuraEnabled public String deliveryText;
        @AuraEnabled public String status;
        @AuraEnabled public String statusTone;
        @AuraEnabled public String totalText;
        @AuraEnabled public Boolean podReceived;
        @AuraEnabled public String bolUrl;
        @AuraEnabled public String invoiceUrl;
        @AuraEnabled public String detailUrl;
        @AuraEnabled public String bucket;
        @AuraEnabled public String pickupCity;
        @AuraEnabled public String pickupState;
        @AuraEnabled public String pickupFacilityName;
        @AuraEnabled public String pickupAddressLine;
        @AuraEnabled public String pickupCityStateZip;
        @AuraEnabled public String deliveryCity;
        @AuraEnabled public String deliveryState;
        @AuraEnabled public String deliveryFacilityName;
        @AuraEnabled public String deliveryAddressLine;
        @AuraEnabled public String deliveryCityStateZip;
        @AuraEnabled public Decimal palletCount;
        @AuraEnabled public Decimal weightLbs;
        @AuraEnabled public Decimal driverLatitude;
        @AuraEnabled public Decimal driverLongitude;
        @AuraEnabled public String driverLocationText;
        @AuraEnabled public String driverLastGpsUpdateText;
        @AuraEnabled public Decimal routeProgressPercent;
        @AuraEnabled public Boolean customerVisibleTracking;
        @AuraEnabled public Boolean trackingMapEnabled;
        @AuraEnabled public Boolean trackingAvailable;
        @AuraEnabled public Boolean hasCustomerRate;
        @AuraEnabled public String quoteAmountText;
        @AuraEnabled public String quoteStageLabel;
        @AuraEnabled public String quoteNextActionLabel;
        @AuraEnabled public String quoteStatus;
        @AuraEnabled public String quoteStatusLabel;
        @AuraEnabled public String quoteResponseAtText;
        @AuraEnabled public String quoteResponseMessage;
        @AuraEnabled public Boolean quoteActionAvailable;
        @AuraEnabled public Boolean deliveryConfirmationAvailable;
        @AuraEnabled public Boolean deliveryConfirmed;
        @AuraEnabled public String deliveryConfirmationLabel;
        @AuraEnabled public String deliveryConfirmedAtText;
        @AuraEnabled public String invoiceDisputeStatus;
        @AuraEnabled public String invoiceDisputeStatusLabel;
        @AuraEnabled public String invoiceDisputeMessage;
        @AuraEnabled public String invoiceDisputedAtText;
        @AuraEnabled public Boolean invoiceIssueActionAvailable;
    }

    public class DocumentDTO {
        @AuraEnabled public String documentId;
        @AuraEnabled public String versionId;
        @AuraEnabled public String loadId;
        @AuraEnabled public String loadNumber;
        @AuraEnabled public String title;
        @AuraEnabled public String type;
        @AuraEnabled public String dateText;
        @AuraEnabled public String downloadUrl;
    }

    public class InvoiceDTO {
        @AuraEnabled public String invoiceId;
        @AuraEnabled public String loadId;
        @AuraEnabled public String loadNumber;
        @AuraEnabled public String invoiceNumber;
        @AuraEnabled public String amountText;
        @AuraEnabled public String status;
        @AuraEnabled public String dateText;
        @AuraEnabled public String actionUrl;
        @AuraEnabled public String invoiceDisputeStatus;
        @AuraEnabled public String invoiceDisputeStatusLabel;
        @AuraEnabled public Boolean invoiceIssueActionAvailable;
    }

    public class RequestDTO {
        @AuraEnabled public String requestId;
        @AuraEnabled public String loadId;
        @AuraEnabled public String loadNumber;
        @AuraEnabled public String type;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        @AuraEnabled public String dateText;
    }

    public class ActionResultDTO {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String requestId;
        @AuraEnabled public String contentVersionId;
    }

    public class LoginResultDTO {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String sessionKey;
        @AuraEnabled public String customerName;
        @AuraEnabled public Id accountId;
        @AuraEnabled public DateTime expiresAt;
    }

    private class AccessContext {
        Id accountId;
        Id contactId;
        Id sessionId;
        String customerName;
        String contactName;
        String contactEmail;
        String accessMode;
        String tokenHash;
    }

    @AuraEnabled
    public static LoginResultDTO login(String username, String password, String userAgent) {
        String cleanUsername = CustomerPortalCredentialService.normalizeUsername(username);
        if (String.isBlank(cleanUsername) || String.isBlank(password)) {
            throw new AuraHandledException('Username and password are required.');
        }

        List<Account> accounts = [
            SELECT Id,
                   Name,
                   Customer_Portal_Username__c,
                   Customer_Portal_Password_Hash__c,
                   Customer_Portal_Password_Salt__c,
                   Customer_Portal_Active__c
            FROM Account
            WHERE Customer_Portal_Username__c = :cleanUsername
            LIMIT 1
        ];

        if (accounts.isEmpty()) {
            throw new AuraHandledException('Username or password is incorrect.');
        }

        Account accountRec = accounts[0];
        if (accountRec.Customer_Portal_Active__c != true) {
            throw new AuraHandledException('This customer portal login is inactive.');
        }

        String expectedHash = CustomerPortalCredentialService.hashPassword(accountRec.Customer_Portal_Password_Salt__c, password);
        if (String.isBlank(accountRec.Customer_Portal_Password_Hash__c) || expectedHash != accountRec.Customer_Portal_Password_Hash__c) {
            throw new AuraHandledException('Username or password is incorrect.');
        }

        String sessionKey = generateSessionKey();
        DateTime expiresAt = System.now().addHours(12);

        Customer_Portal_Session__c sessionRec = new Customer_Portal_Session__c();
        sessionRec.Account__c = accountRec.Id;
        sessionRec.Token_Hash__c = CustomerPortalTokenService.hashToken(sessionKey);
        sessionRec.Active__c = true;
        sessionRec.Expires_At__c = expiresAt;
        sessionRec.Portal_Link__c = 'LOGIN_SESSION';
        sessionRec.Last_Opened__c = System.now();
        sessionRec.Last_User_Agent__c = sanitize255(userAgent);
        insert sessionRec;

        try {
            update new Account(Id = accountRec.Id, Customer_Portal_Last_Login__c = System.now());
        } catch (Exception ex) {
            System.debug('Unable to update portal last login: ' + ex.getMessage());
        }

        AccessContext access = new AccessContext();
        access.accountId = accountRec.Id;
        access.sessionId = sessionRec.Id;
        access.customerName = accountRec.Name;
        access.accessMode = 'Login';
        access.tokenHash = CustomerPortalTokenService.hashToken(sessionKey);
        publishAction(access, null, 'LOGIN', null, null, null, userAgent);

        LoginResultDTO result = new LoginResultDTO();
        result.success = true;
        result.message = 'Logged in.';
        result.sessionKey = sessionKey;
        result.customerName = accountRec.Name;
        result.accountId = accountRec.Id;
        result.expiresAt = expiresAt;
        return result;
    }

    @AuraEnabled
    public static void logout(String sessionKey) {
        if (String.isBlank(sessionKey)) return;
        String tokenHash = CustomerPortalTokenService.hashToken(sessionKey);
        List<Customer_Portal_Session__c> sessions = [
            SELECT Id, Active__c
            FROM Customer_Portal_Session__c
            WHERE Token_Hash__c = :tokenHash
            LIMIT 1
        ];
        if (!sessions.isEmpty()) {
            sessions[0].Active__c = false;
            update sessions[0];
        }
    }

    @AuraEnabled
    public static PortalDataDTO getPortalData(String sessionKey, String pageName, String loadId) {
        AccessContext access = resolveAccess(sessionKey, true);
        PortalDataDTO data = new PortalDataDTO();
        data.context = buildContext(access);
        data.summary = new PortalSummaryDTO();
        data.shipments = new List<ShipmentDTO>();
        data.documents = new List<DocumentDTO>();
        data.invoices = new List<InvoiceDTO>();
        data.requests = new List<RequestDTO>();

        String requestedPage = String.isBlank(pageName) ? SITE_DASHBOARD_PAGE : pageName.trim().toLowerCase();
        List<FreightTM__Load__c> loads = queryCustomerLoads(access.accountId, 200);
        Set<Id> loadIds = new Set<Id>();
        Map<Id, String> loadNumberById = new Map<Id, String>();
        for (FreightTM__Load__c loadRec : loads) {
            loadIds.add(loadRec.Id);
            loadNumberById.put(loadRec.Id, loadRec.Name);
        }

        // Return only the collections required by the active portal view. This keeps
        // navigation fast and prevents document/request queries on every tab change.
        data.shipments = buildShipmentDtos(loads);
        if (requestedPage == SITE_DASHBOARD_PAGE || requestedPage == SITE_DOCUMENTS_PAGE) {
            data.documents = queryDocuments(loadIds, loadNumberById);
        }
        if (requestedPage == SITE_DASHBOARD_PAGE || requestedPage == SITE_INVOICES_PAGE) {
            data.invoices = buildInvoices(loads);
        }
        if (requestedPage == SITE_DASHBOARD_PAGE || requestedPage == SITE_REQUESTS_PAGE) {
            data.requests = queryRequests(access.accountId, loadNumberById);
        }
        data.summary = buildSummary(loads, data.documents, data.invoices, data.requests);

        if (!String.isBlank(loadId)) {
            Id requestedLoadId = safeId(loadId);
            if (requestedLoadId != null) {
                for (ShipmentDTO shipment : data.shipments) {
                    if (shipment.loadId == String.valueOf(requestedLoadId)) {
                        data.selectedLoad = shipment;
                        break;
                    }
                }
            }
        }

        return data;
    }

    @AuraEnabled
    public static ActionResultDTO submitCustomerAction(String sessionKey, String loadId, String actionName, String message, String userAgent) {
        AccessContext access = resolveAccess(sessionKey, true);
        Id targetLoadId = safeId(loadId);
        if (targetLoadId == null) {
            throw new AuraHandledException('Load is required.');
        }
        validateLoadAccess(targetLoadId, access.accountId);

        String normalizedAction = normalizeAction(actionName);
        if (String.isBlank(normalizedAction)) {
            throw new AuraHandledException('Action is required.');
        }

        ActionResultDTO actionResult = applyCustomerActionToLoad(access, targetLoadId, normalizedAction, message);

        Id requestId = createRequest(access, targetLoadId, normalizedAction, actionResult.message, null, null);
        publishAction(access, targetLoadId, normalizedAction, actionResult.message, null, null, userAgent);

        actionResult.success = true;
        actionResult.requestId = requestId == null ? null : String.valueOf(requestId);
        return actionResult;
    }

    @AuraEnabled
    public static ActionResultDTO uploadPod(String sessionKey, String loadId, String fileName, String base64Data, String message, String userAgent) {
        AccessContext access = resolveAccess(sessionKey, true);
        Id targetLoadId = safeId(loadId);
        if (targetLoadId == null) {
            throw new AuraHandledException('Load is required.');
        }
        validateLoadAccess(targetLoadId, access.accountId);
        if (String.isBlank(fileName) || String.isBlank(base64Data)) {
            throw new AuraHandledException('File name and file data are required.');
        }

        String cleanBase64 = base64Data.contains(',') ? base64Data.substringAfter(',') : base64Data;
        Blob body = EncodingUtil.base64Decode(cleanBase64);
        if (body.size() > 6000000) {
            throw new AuraHandledException('File is too large. Use a file smaller than 6 MB.');
        }

        String cleanName = sanitizeFileName(fileName);
        if (!cleanName.toLowerCase().contains('pod') && !cleanName.toLowerCase().contains('proof')) {
            cleanName = 'POD - ' + cleanName;
        }
        // The POD prefix can push an already-truncated name beyond the
        // ContentVersion title limit used by the portal. Sanitize once more
        // after adding the prefix so the final stored title stays <= 120.
        cleanName = sanitizeFileName(cleanName);
        ContentVersion cv = new ContentVersion();
        cv.Title = cleanName;
        cv.PathOnClient = cleanName;
        cv.VersionData = body;
        cv.FirstPublishLocationId = targetLoadId;
        insert cv;

        try {
            update new FreightTM__Load__c(Id = targetLoadId, POD_Received__c = true);
        } catch (Exception ex) {
            System.debug('Unable to update POD_Received__c: ' + ex.getMessage());
        }

        Id requestId = createRequest(access, targetLoadId, 'POD_UPLOADED', message, cleanName, String.valueOf(cv.Id));
        publishAction(access, targetLoadId, 'POD_UPLOADED', message, cleanName, String.valueOf(cv.Id), userAgent);

        ActionResultDTO result = new ActionResultDTO();
        result.success = true;
        result.message = 'POD uploaded.';
        result.requestId = String.valueOf(requestId);
        result.contentVersionId = String.valueOf(cv.Id);
        return result;
    }

    @AuraEnabled
    public static void recordPortalOpened(String sessionKey, String userAgent) {
        try {
            AccessContext access = resolveAccess(sessionKey, true);
            publishAction(access, null, 'PORTAL_OPENED', null, null, null, userAgent);
        } catch (Exception ex) {
            System.debug('Could not record portal open: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static void recordDocumentViewed(String sessionKey, String documentId, String loadId, String userAgent) {
        try {
            AccessContext access = resolveAccess(sessionKey, true);
            Id targetLoadId = safeId(loadId);
            if (targetLoadId != null) {
                validateLoadAccess(targetLoadId, access.accountId);
            }
            publishAction(access, targetLoadId, 'DOCUMENT_VIEWED', documentId, null, documentId, userAgent);
        } catch (Exception ex) {
            System.debug('Could not record document view: ' + ex.getMessage());
        }
    }


    @AuraEnabled
    public static String getDocumentDownloadUrl(String sessionKey, String versionId, String loadId) {
        AccessContext access = resolveAccess(sessionKey, true);
        Id cvId = safeId(versionId);
        Id targetLoadId = safeId(loadId);
        if (cvId == null || targetLoadId == null) {
            throw new AuraHandledException('Document is required.');
        }
        validateLoadAccess(targetLoadId, access.accountId);

        ContentVersion cv = [
            SELECT Id, Title, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cvId
            LIMIT 1
        ];

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :targetLoadId
              AND ContentDocumentId = :cv.ContentDocumentId
            LIMIT 1
        ];
        if (links.isEmpty()) {
            throw new AuraHandledException('This document is not available for this customer.');
        }

        List<ContentDistribution> existing = [
            SELECT Id, ContentDownloadUrl, DistributionPublicUrl
            FROM ContentDistribution
            WHERE ContentVersionId = :cv.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            ContentDistribution cd = new ContentDistribution();
            cd.Name = sanitizeContentDistributionName(cv.Title);
            cd.ContentVersionId = cv.Id;
            cd.PreferencesAllowViewInBrowser = true;
            cd.PreferencesAllowOriginalDownload = true;
            cd.PreferencesLinkLatestVersion = true;
            cd.PreferencesNotifyOnVisit = false;
            cd.PreferencesPasswordRequired = false;
            insert cd;
            existing = [
                SELECT Id, ContentDownloadUrl, DistributionPublicUrl
                FROM ContentDistribution
                WHERE Id = :cd.Id
                LIMIT 1
            ];
        }

        ContentDistribution dist = existing[0];
        if (!String.isBlank(dist.ContentDownloadUrl)) return dist.ContentDownloadUrl;
        if (!String.isBlank(dist.DistributionPublicUrl)) return dist.DistributionPublicUrl;
        throw new AuraHandledException('Document link could not be created.');
    }


    @AuraEnabled
    public static ActionResultDTO updateLoadStatus(String sessionKey, String loadId, String statusValue, String userAgent) {
        AccessContext access = resolveAccess(sessionKey, true);
        Id targetLoadId = safeId(loadId);
        if (targetLoadId == null) {
            throw new AuraHandledException('Load is required.');
        }
        validateLoadAccess(targetLoadId, access.accountId);

        String cleanStatus = normalizeLoadStatus(statusValue);
        FreightTM__Load__c loadUpdate = new FreightTM__Load__c(Id = targetLoadId);
        loadUpdate.FreightTM__Status__c = cleanStatus;
        if (cleanStatus == 'Delivered') {
            loadUpdate.FreightTM__Delivery_Departure__c = System.now();
        }
        update loadUpdate;

        String displayStatus = String.isBlank(cleanStatus) ? '--None--' : cleanStatus;
        String message = 'Status changed to ' + displayStatus;
        Id requestId = createRequest(access, targetLoadId, 'STATUS_UPDATED', message, null, null);
        publishAction(access, targetLoadId, 'STATUS_UPDATED', message, null, null, userAgent);

        ActionResultDTO result = new ActionResultDTO();
        result.success = true;
        result.message = message;
        result.requestId = requestId == null ? null : String.valueOf(requestId);
        return result;
    }

    private static AccessContext resolveAccess(String sessionKey, Boolean requireActive) {
        if (String.isBlank(sessionKey)) {
            throw new AuraHandledException('Please log in to access the customer portal.');
        }

        Customer_Portal_Session__c session = CustomerPortalTokenService.validateToken(sessionKey);
        Account accountRec = [SELECT Id, Name FROM Account WHERE Id = :session.Account__c LIMIT 1];
        Contact contactRec = null;
        if (session.Contact__c != null) {
            List<Contact> contacts = [SELECT Id, Name, Email FROM Contact WHERE Id = :session.Contact__c LIMIT 1];
            if (!contacts.isEmpty()) contactRec = contacts[0];
        }

        try {
            session.Last_Opened__c = System.now();
            update session;
        } catch (Exception ex) {
            System.debug('Unable to update session last opened: ' + ex.getMessage());
        }

        AccessContext ctx = new AccessContext();
        ctx.accountId = session.Account__c;
        ctx.contactId = session.Contact__c;
        ctx.sessionId = session.Id;
        ctx.customerName = accountRec.Name;
        ctx.contactName = contactRec == null ? null : contactRec.Name;
        ctx.contactEmail = contactRec == null ? null : contactRec.Email;
        ctx.accessMode = 'Login';
        ctx.tokenHash = CustomerPortalTokenService.hashToken(sessionKey);
        return ctx;
    }

    private static PortalContextDTO buildContext(AccessContext access) {
        PortalContextDTO dto = new PortalContextDTO();
        dto.accountId = access.accountId;
        dto.contactId = access.contactId;
        dto.sessionId = access.sessionId;
        dto.customerName = access.customerName;
        dto.contactName = access.contactName;
        dto.contactEmail = access.contactEmail;
        dto.accessMode = access.accessMode;
        dto.loginRequired = false;
        dto.loginUrl = '/login';
        return dto;
    }

    private static List<FreightTM__Load__c> queryCustomerLoads(Id accountId, Integer limitSize) {
        return [
            SELECT Id,
                   Name,
                   CreatedDate,
                   FreightTM__Customer__c,
                   FreightTM__Status__c,
                   FreightTM__Calendar_Load__c,
                   FreightTM__Pickup_City__c,
                   FreightTM__Pickup_State__c,
                   FreightTM__Pickup_Address__c,
                   FreightTM__Pickup_Zip_Code__c,
                   FreightTM__PickupFacility__c,
                   FreightTM__PickupFacility__r.Name,
                   FreightTM__Pickup_Date__c,
                   FreightTM__Pickup_Arrival__c,
                   FreightTM__Pickup_Departure__c,
                   FreightTM__Delivery_City__c,
                   FreightTM__Delivery_State__c,
                   FreightTM__Delivery_Address__c,
                   FreightTM__Delivery_Zip_Code__c,
                   FreightTM__DeliveryFacility__c,
                   FreightTM__DeliveryFacility__r.Name,
                   FreightTM__Delivery_Date__c,
                   FreightTM__Delivery_Arrival__c,
                   FreightTM__Delivery_Departure__c,
                   FreightTM__Invoice_Status__c,
                   FreightTM__Invoiced_On__c,
                   FreightTM__Billed_On__c,
                   FreightTM__Rate__c,
                   FreightTM__Total__c,
                   FreightTM__Number_of_Pallets__c,
                   FreightTM__Weight__c,
                   FreightTM__Load_Canceled__c,
                   POD_Received__c,
                   Driver_Current_Latitude__c,
                   Driver_Current_Longitude__c,
                   Driver_Last_GPS_Update__c,
                   Driver_Current_Location_Text__c,
                   Route_Progress_Percent__c,
                   Customer_Visible_Tracking__c,
                   Tracking_Map_Enabled__c,
                   Customer_Portal_Quote_Status__c,
                   Customer_Portal_Quote_Response_At__c,
                   Customer_Portal_Quote_Response_Message__c,
                   Customer_Portal_Delivery_Confirmed__c,
                   Customer_Portal_Delivery_Confirmed_At__c,
                   Customer_Portal_Invoice_Dispute_Status__c,
                   Customer_Portal_Invoice_Disputed_At__c,
                   Customer_Portal_Invoice_Dispute_Message__c
            FROM FreightTM__Load__c
            WHERE FreightTM__Customer__c = :accountId
            ORDER BY CreatedDate DESC
            LIMIT :limitSize
        ];
    }

    private static void validateLoadAccess(Id loadId, Id accountId) {
        List<FreightTM__Load__c> loads = [
            SELECT Id
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            AND FreightTM__Customer__c = :accountId
            LIMIT 1
        ];
        if (loads.isEmpty()) {
            throw new AuraHandledException('This load is not available for this customer.');
        }
    }

    private static PortalSummaryDTO buildSummary(List<FreightTM__Load__c> loads, List<DocumentDTO> docs, List<InvoiceDTO> invoices, List<RequestDTO> requests) {
        PortalSummaryDTO summary = new PortalSummaryDTO();
        summary.activeShipments = 0;
        summary.delivered30 = 0;
        summary.onTimeRate = null;
        summary.documentCount = docs == null ? 0 : docs.size();
        summary.invoiceCount = invoices == null ? 0 : invoices.size();
        summary.requestCount = requests == null ? 0 : requests.size();

        Integer deliveredCount = 0;
        Integer onTimeCount = 0;
        Date thirtyDaysAgo = Date.today().addDays(-30);

        for (FreightTM__Load__c loadRec : loads) {
            Boolean delivered = isDeliveredStatus(loadRec.FreightTM__Status__c);
            if (!delivered && loadRec.FreightTM__Load_Canceled__c != true) {
                summary.activeShipments++;
            }

            Date deliveredDate = loadRec.FreightTM__Delivery_Departure__c == null
                ? loadRec.FreightTM__Delivery_Date__c
                : loadRec.FreightTM__Delivery_Departure__c.date();

            if (delivered && deliveredDate != null) {
                deliveredCount++;
                if (deliveredDate >= thirtyDaysAgo) {
                    summary.delivered30++;
                }
                if (loadRec.FreightTM__Delivery_Date__c == null || deliveredDate <= loadRec.FreightTM__Delivery_Date__c) {
                    onTimeCount++;
                }
            }
        }

        if (deliveredCount > 0) {
            summary.onTimeRate = ((Decimal)onTimeCount / (Decimal)deliveredCount * 100).setScale(1);
        }
        return summary;
    }

    private static List<ShipmentDTO> buildShipmentDtos(List<FreightTM__Load__c> loads) {
        List<ShipmentDTO> rows = new List<ShipmentDTO>();
        for (FreightTM__Load__c loadRec : loads) {
            ShipmentDTO dto = new ShipmentDTO();
            dto.loadId = String.valueOf(loadRec.Id);
            dto.loadNumber = loadRec.Name;
            dto.route = !String.isBlank(loadRec.FreightTM__Calendar_Load__c)
                ? loadRec.FreightTM__Calendar_Load__c
                : buildRoute(loadRec.FreightTM__Pickup_City__c, loadRec.FreightTM__Pickup_State__c, loadRec.FreightTM__Delivery_City__c, loadRec.FreightTM__Delivery_State__c);
            dto.pickupText = formatDate(loadRec.FreightTM__Pickup_Date__c);
            dto.deliveryText = formatDate(loadRec.FreightTM__Delivery_Date__c);
            dto.status = String.isBlank(loadRec.FreightTM__Status__c) ? '--None--' : loadRec.FreightTM__Status__c;
            dto.bucket = getShipmentBucket(loadRec);
            dto.statusTone = dto.bucket == 'delivered' ? 'delivered' : (dto.bucket == 'future' ? 'future' : 'transit');
            dto.totalText = loadRec.FreightTM__Total__c == null ? '—' : '$' + String.valueOf(loadRec.FreightTM__Total__c.setScale(2));
            dto.podReceived = loadRec.POD_Received__c;
            dto.pickupCity = loadRec.FreightTM__Pickup_City__c;
            dto.pickupState = loadRec.FreightTM__Pickup_State__c;
            dto.pickupFacilityName = loadRec.FreightTM__PickupFacility__r == null || String.isBlank(loadRec.FreightTM__PickupFacility__r.Name)
                ? 'Pickup Location'
                : loadRec.FreightTM__PickupFacility__r.Name;
            dto.pickupAddressLine = String.isBlank(loadRec.FreightTM__Pickup_Address__c) ? '—' : loadRec.FreightTM__Pickup_Address__c;
            dto.pickupCityStateZip = buildCityStateZip(loadRec.FreightTM__Pickup_City__c, loadRec.FreightTM__Pickup_State__c, loadRec.FreightTM__Pickup_Zip_Code__c);
            dto.deliveryCity = loadRec.FreightTM__Delivery_City__c;
            dto.deliveryState = loadRec.FreightTM__Delivery_State__c;
            dto.deliveryFacilityName = loadRec.FreightTM__DeliveryFacility__r == null || String.isBlank(loadRec.FreightTM__DeliveryFacility__r.Name)
                ? 'Delivery Location'
                : loadRec.FreightTM__DeliveryFacility__r.Name;
            dto.deliveryAddressLine = String.isBlank(loadRec.FreightTM__Delivery_Address__c) ? '—' : loadRec.FreightTM__Delivery_Address__c;
            dto.deliveryCityStateZip = buildCityStateZip(loadRec.FreightTM__Delivery_City__c, loadRec.FreightTM__Delivery_State__c, loadRec.FreightTM__Delivery_Zip_Code__c);
            dto.palletCount = loadRec.FreightTM__Number_of_Pallets__c;
            dto.weightLbs = loadRec.FreightTM__Weight__c;
            dto.customerVisibleTracking = loadRec.Customer_Visible_Tracking__c == true;
            dto.trackingMapEnabled = loadRec.Tracking_Map_Enabled__c == true;
            Boolean trackingIsVisible = dto.customerVisibleTracking == true && dto.trackingMapEnabled == true;
            dto.driverLatitude = trackingIsVisible ? loadRec.Driver_Current_Latitude__c : null;
            dto.driverLongitude = trackingIsVisible ? loadRec.Driver_Current_Longitude__c : null;
            dto.driverLocationText = trackingIsVisible ? loadRec.Driver_Current_Location_Text__c : null;
            dto.driverLastGpsUpdateText = trackingIsVisible ? formatDateTime(loadRec.Driver_Last_GPS_Update__c) : null;
            dto.routeProgressPercent = trackingIsVisible ? loadRec.Route_Progress_Percent__c : null;
            dto.trackingAvailable = trackingIsVisible && dto.driverLatitude != null && dto.driverLongitude != null;

            String normalizedStatus = String.isBlank(loadRec.FreightTM__Status__c) ? '' : loadRec.FreightTM__Status__c.trim().toLowerCase();
            Decimal customerQuoteAmount = getCustomerQuoteAmount(loadRec);
            dto.hasCustomerRate = customerQuoteAmount != null;
            dto.quoteAmountText = customerQuoteAmount == null
                ? 'No customer quote amount yet'
                : '$' + String.valueOf(customerQuoteAmount.setScale(2));
            dto.quoteStatus = loadRec.Customer_Portal_Quote_Status__c;
            dto.quoteResponseAtText = loadRec.Customer_Portal_Quote_Response_At__c == null ? null : formatDateTime(loadRec.Customer_Portal_Quote_Response_At__c);
            dto.quoteResponseMessage = loadRec.Customer_Portal_Quote_Response_Message__c;
            dto.quoteStatusLabel = buildQuoteStatusLabel(dto.hasCustomerRate, dto.quoteStatus, normalizedStatus);
            dto.quoteStageLabel = buildQuoteStageLabel(dto.hasCustomerRate, normalizedStatus);
            dto.quoteNextActionLabel = buildQuoteNextActionLabel(dto.hasCustomerRate, dto.quoteStatus, normalizedStatus);
            dto.quoteActionAvailable = dto.hasCustomerRate == true
                && normalizedStatus == 'assigned'
                && !hasFinalQuoteResponse(loadRec.Customer_Portal_Quote_Status__c);

            dto.deliveryConfirmed = loadRec.Customer_Portal_Delivery_Confirmed__c == true;
            dto.deliveryConfirmedAtText = loadRec.Customer_Portal_Delivery_Confirmed_At__c == null ? null : formatDateTime(loadRec.Customer_Portal_Delivery_Confirmed_At__c);
            dto.deliveryConfirmationLabel = dto.deliveryConfirmed
                ? 'Confirmed by customer'
                : 'Not confirmed by customer';
            dto.deliveryConfirmationAvailable = dto.deliveryConfirmed != true && (
                normalizedStatus == 'at receiving'
                || normalizedStatus == 'in transit to delivery'
                || isDeliveredStatus(loadRec.FreightTM__Status__c)
                || loadRec.POD_Received__c == true
            );

            dto.invoiceDisputeStatus = loadRec.Customer_Portal_Invoice_Dispute_Status__c;
            dto.invoiceDisputedAtText = loadRec.Customer_Portal_Invoice_Disputed_At__c == null ? null : formatDateTime(loadRec.Customer_Portal_Invoice_Disputed_At__c);
            dto.invoiceDisputeMessage = loadRec.Customer_Portal_Invoice_Dispute_Message__c;
            dto.invoiceDisputeStatusLabel = String.isBlank(dto.invoiceDisputeStatus)
                ? 'No invoice issue reported'
                : 'Invoice issue: ' + dto.invoiceDisputeStatus;
            dto.invoiceIssueActionAvailable = String.isBlank(dto.invoiceDisputeStatus);

            dto.bolUrl = '#';
            dto.invoiceUrl = '#';
            dto.detailUrl = buildPortalUrl(SITE_LOAD_PAGE, loadRec.Id);
            rows.add(dto);
        }
        return rows;
    }

    private static List<DocumentDTO> queryDocuments(Set<Id> loadIds, Map<Id, String> loadNumberById) {
        List<DocumentDTO> results = new List<DocumentDTO>();
        if (loadIds == null || loadIds.isEmpty()) return results;

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId,
                   LinkedEntityId,
                   ContentDocument.Title,
                   ContentDocument.FileType,
                   ContentDocument.CreatedDate,
                   ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :loadIds
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 100
        ];

        for (ContentDocumentLink link : links) {
            DocumentDTO dto = new DocumentDTO();
            dto.documentId = String.valueOf(link.ContentDocumentId);
            dto.versionId = String.valueOf(link.ContentDocument.LatestPublishedVersionId);
            dto.loadId = String.valueOf(link.LinkedEntityId);
            dto.loadNumber = loadNumberById.get(link.LinkedEntityId);
            dto.title = link.ContentDocument.Title;
            dto.type = classifyDocument(link.ContentDocument.Title);
            if (dto.type != 'POD') {
                continue;
            }
            dto.dateText = formatDate(link.ContentDocument.CreatedDate.date());
            dto.downloadUrl = '#';
            results.add(dto);
        }
        return results;
    }

    private static List<InvoiceDTO> buildInvoices(List<FreightTM__Load__c> loads) {
        List<InvoiceDTO> results = new List<InvoiceDTO>();
        for (FreightTM__Load__c loadRec : loads) {
            InvoiceDTO dto = new InvoiceDTO();
            dto.invoiceId = String.valueOf(loadRec.Id);
            dto.loadId = String.valueOf(loadRec.Id);
            dto.loadNumber = loadRec.Name;
            dto.invoiceNumber = 'Invoice · ' + loadRec.Name;
            dto.amountText = loadRec.FreightTM__Total__c == null ? '—' : '$' + String.valueOf(loadRec.FreightTM__Total__c.setScale(2));
            dto.status = String.isBlank(loadRec.FreightTM__Invoice_Status__c) ? 'Not Started' : loadRec.FreightTM__Invoice_Status__c;
            dto.dateText = loadRec.FreightTM__Invoiced_On__c == null ? formatDate(loadRec.FreightTM__Billed_On__c) : formatDate(loadRec.FreightTM__Invoiced_On__c);
            dto.actionUrl = '#';
            dto.invoiceDisputeStatus = loadRec.Customer_Portal_Invoice_Dispute_Status__c;
            dto.invoiceDisputeStatusLabel = String.isBlank(dto.invoiceDisputeStatus)
                ? 'No invoice issue reported'
                : 'Invoice issue: ' + dto.invoiceDisputeStatus;
            dto.invoiceIssueActionAvailable = String.isBlank(dto.invoiceDisputeStatus);
            results.add(dto);
        }
        return results;
    }

    private static List<RequestDTO> queryRequests(Id accountId, Map<Id, String> loadNumberById) {
        List<RequestDTO> results = new List<RequestDTO>();
        if (!Schema.getGlobalDescribe().containsKey('Customer_Portal_Request__c')) return results;

        List<Customer_Portal_Request__c> requests = [
            SELECT Id,
                   Load__c,
                   Request_Type__c,
                   Status__c,
                   Message__c,
                   CreatedDate
            FROM Customer_Portal_Request__c
            WHERE Account__c = :accountId
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];

        for (Customer_Portal_Request__c rec : requests) {
            RequestDTO dto = new RequestDTO();
            dto.requestId = String.valueOf(rec.Id);
            dto.loadId = rec.Load__c == null ? null : String.valueOf(rec.Load__c);
            dto.loadNumber = rec.Load__c == null ? null : loadNumberById.get(rec.Load__c);
            dto.type = rec.Request_Type__c;
            dto.status = rec.Status__c;
            dto.message = rec.Message__c;
            dto.dateText = formatDate(rec.CreatedDate.date());
            results.add(dto);
        }
        return results;
    }

    private static Id createRequest(AccessContext access, Id loadId, String actionName, String message, String fileName, String contentVersionId) {
        if (!Schema.getGlobalDescribe().containsKey('Customer_Portal_Request__c')) return null;

        Customer_Portal_Request__c req = new Customer_Portal_Request__c();
        req.Account__c = access.accountId;
        req.Contact__c = access.contactId;
        req.Load__c = loadId;
        req.Request_Type__c = actionName;
        req.Status__c = 'New';
        req.Message__c = message;
        req.Source__c = access.accessMode;
        req.File_Name__c = fileName;
        req.Content_Version_Id__c = contentVersionId;
        req.Event_Time__c = System.now();
        req.Requester_Name__c = access.contactName;
        req.Requester_Email__c = access.contactEmail;
        insert req;
        return req.Id;
    }

    private static void publishAction(AccessContext access, Id loadId, String actionName, String message, String fileName, String documentId, String userAgent) {
        Customer_Portal_Action__e evt = new Customer_Portal_Action__e();
        evt.Account_Id__c = access.accountId == null ? null : String.valueOf(access.accountId);
        evt.Contact_Id__c = access.contactId == null ? null : String.valueOf(access.contactId);
        evt.Session_Id__c = access.sessionId == null ? null : String.valueOf(access.sessionId);
        evt.Load_Id__c = loadId == null ? null : String.valueOf(loadId);
        evt.Action_Name__c = actionName;
        evt.Token_Hash__c = access.tokenHash;
        evt.Event_Time__c = System.now();
        evt.User_Agent__c = sanitize255(userAgent);
        evt.Message__c = sanitize255(message);
        evt.File_Name__c = sanitize255(fileName);
        evt.Document_Id__c = sanitize255(documentId);
        evt.Source__c = access.accessMode;
        EventBus.publish(evt);
    }

    private static ActionResultDTO applyCustomerActionToLoad(AccessContext access, Id loadId, String actionName, String message) {
        ActionResultDTO result = new ActionResultDTO();
        FreightTM__Load__c currentLoad = [
            SELECT Id,
                   FreightTM__Status__c,
                   FreightTM__Rate__c,
                   FreightTM__Total__c,
                   POD_Received__c,
                   Customer_Portal_Quote_Status__c,
                   Customer_Portal_Delivery_Confirmed__c,
                   Customer_Portal_Invoice_Dispute_Status__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];
        String normalizedStatus = String.isBlank(currentLoad.FreightTM__Status__c) ? '' : currentLoad.FreightTM__Status__c.trim().toLowerCase();
        FreightTM__Load__c loadUpdate = new FreightTM__Load__c(Id = loadId);
        Datetime nowValue = System.now();
        String cleanMessage = sanitizeLong(message);

        if (actionName == 'APPROVE_QUOTE') {
            if (getCustomerQuoteAmount(currentLoad) == null || normalizedStatus != 'assigned' || hasFinalQuoteResponse(currentLoad.Customer_Portal_Quote_Status__c)) {
                throw new AuraHandledException('This quote is not available for customer approval.');
            }
            loadUpdate.Customer_Portal_Quote_Status__c = 'Approved';
            loadUpdate.Customer_Portal_Quote_Response_At__c = nowValue;
            loadUpdate.Customer_Portal_Quote_Response_Message__c = cleanMessage;
            result.message = String.isBlank(cleanMessage)
                ? 'Quote approved by customer.'
                : 'Quote approved by customer. Note: ' + cleanMessage;
        } else if (actionName == 'REJECT_QUOTE') {
            if (getCustomerQuoteAmount(currentLoad) == null || normalizedStatus != 'assigned' || hasFinalQuoteResponse(currentLoad.Customer_Portal_Quote_Status__c)) {
                throw new AuraHandledException('This quote is not available for customer decline.');
            }
            loadUpdate.Customer_Portal_Quote_Status__c = 'Rejected';
            loadUpdate.Customer_Portal_Quote_Response_At__c = nowValue;
            loadUpdate.Customer_Portal_Quote_Response_Message__c = cleanMessage;
            result.message = String.isBlank(cleanMessage)
                ? 'Quote rejected by customer.'
                : 'Quote rejected by customer. Reason: ' + cleanMessage;
        } else if (actionName == 'CONFIRM_DELIVERY') {
            Boolean canConfirmDelivery = currentLoad.Customer_Portal_Delivery_Confirmed__c != true && (
                normalizedStatus == 'at receiving'
                || normalizedStatus == 'in transit to delivery'
                || isDeliveredStatus(currentLoad.FreightTM__Status__c)
                || currentLoad.POD_Received__c == true
            );
            if (!canConfirmDelivery) {
                throw new AuraHandledException('Delivery confirmation is not available for this load yet.');
            }
            loadUpdate.FreightTM__Status__c = 'Delivered';
            loadUpdate.FreightTM__Delivery_Departure__c = nowValue;
            loadUpdate.Customer_Portal_Delivery_Confirmed__c = true;
            loadUpdate.Customer_Portal_Delivery_Confirmed_At__c = nowValue;
            result.message = String.isBlank(cleanMessage)
                ? 'Delivery confirmed by customer.'
                : 'Delivery confirmed by customer. Note: ' + cleanMessage;
        } else if (actionName == 'DISPUTE_INVOICE') {
            if (hasOpenInvoiceIssue(currentLoad.Customer_Portal_Invoice_Dispute_Status__c)) {
                throw new AuraHandledException('An invoice issue is already open for this load.');
            }
            loadUpdate.Customer_Portal_Invoice_Dispute_Status__c = 'Open';
            loadUpdate.Customer_Portal_Invoice_Disputed_At__c = nowValue;
            loadUpdate.Customer_Portal_Invoice_Dispute_Message__c = cleanMessage;
            result.message = String.isBlank(cleanMessage)
                ? 'Invoice dispute opened by customer.'
                : 'Invoice dispute opened by customer. Reason: ' + cleanMessage;
        } else {
            result.message = 'Customer action submitted.';
        }

        update loadUpdate;
        return result;
    }


    @TestVisible
    private static Decimal getCustomerQuoteAmount(FreightTM__Load__c loadRec) {
        if (loadRec == null) return null;
        return loadRec.FreightTM__Total__c != null
            ? loadRec.FreightTM__Total__c
            : loadRec.FreightTM__Rate__c;
    }

    @TestVisible
    private static String sanitizeLong(String value) {
        if (String.isBlank(value)) return null;
        String clean = value.trim();
        return clean.length() > 32000 ? clean.substring(0, 32000) : clean;
    }

    private static String normalizeAction(String actionName) {
        if (String.isBlank(actionName)) return null;
        String value = actionName.trim().toUpperCase();
        Set<String> allowed = new Set<String>{
            'APPROVE_QUOTE', 'REJECT_QUOTE', 'CONFIRM_DELIVERY', 'DISPUTE_INVOICE',
            'STATUS_UPDATED'
        };
        if (!allowed.contains(value)) {
            throw new AuraHandledException('Unsupported customer portal action.');
        }
        return value;
    }

    private static String buildPortalUrl(String pageName, Id loadId) {
        String url = '?p=' + EncodingUtil.urlEncode(pageName, 'UTF-8');
        if (loadId != null) url += '&loadId=' + EncodingUtil.urlEncode(String.valueOf(loadId), 'UTF-8');
        return url;
    }

    @TestVisible
    private static String buildPageUrl(String pageName, Id loadId) {
        return 'apex/' + pageName + '?id=' + EncodingUtil.urlEncode(String.valueOf(loadId), 'UTF-8');
    }

    private static String generateSessionKey() {
        String token = EncodingUtil.base64Encode(Crypto.generateAesKey(128));
        token = token.replace('+', '-');
        token = token.replace('/', '_');
        token = token.replace('=', '');
        return token;
    }

    @TestVisible
    private static String buildRoute(String pickupCity, String pickupState, String deliveryCity, String deliveryState) {
        String pickup = joinLocation(pickupCity, pickupState);
        String delivery = joinLocation(deliveryCity, deliveryState);
        if (String.isBlank(pickup) && String.isBlank(delivery)) return 'Route not set';
        return pickup + ' → ' + delivery;
    }

    private static String joinLocation(String city, String state) {
        List<String> parts = new List<String>();
        if (!String.isBlank(city)) parts.add(city);
        if (!String.isBlank(state)) parts.add(state);
        return String.join(parts, ', ');
    }

    private static String buildCityStateZip(String city, String state, String zipCode) {
        String cityState = joinLocation(city, state);
        List<String> parts = new List<String>();
        if (!String.isBlank(cityState)) parts.add(cityState);
        if (!String.isBlank(zipCode)) parts.add(zipCode);
        return parts.isEmpty() ? '—' : String.join(parts, ' ');
    }


    private static String getShipmentBucket(FreightTM__Load__c loadRec) {
        if (loadRec == null) return 'future';
        String status = loadRec.FreightTM__Status__c;
        if (isDeliveredStatus(status)) return 'delivered';

        String lower = String.isBlank(status) ? '' : status.toLowerCase();
        Set<String> currentStatuses = new Set<String>{
            'in transit to pickup', 'at shipping', 'in transit to delivery', 'at receiving'
        };
        if (currentStatuses.contains(lower)) return 'current';

        if (loadRec.FreightTM__Pickup_Date__c != null && loadRec.FreightTM__Pickup_Date__c <= Date.today()) {
            return 'current';
        }

        return 'future';
    }

    private static String normalizeLoadStatus(String statusValue) {
        if (String.isBlank(statusValue) || statusValue == '--None--') return null;
        String clean = statusValue.trim();
        Set<String> allowed = new Set<String>{
            'Assigned', 'Dispatched', 'In Transit to Pickup', 'At Shipping',
            'In Transit to Delivery', 'At Receiving', 'Delivered'
        };
        if (!allowed.contains(clean)) {
            throw new AuraHandledException('Unsupported load status.');
        }
        return clean;
    }

    private static String buildQuoteStatusLabel(Boolean hasCustomerRate, String quoteStatus, String normalizedStatus) {
        if (hasCustomerRate != true) {
            return 'No customer price yet';
        }
        String lower = String.isBlank(quoteStatus) ? '' : quoteStatus.trim().toLowerCase();
        if (lower == 'approved' || lower == 'accepted') {
            return 'Accepted by customer';
        }
        if (lower == 'rejected' || lower == 'declined') {
            return 'Declined by customer';
        }
        if (normalizedStatus != 'assigned') {
            return 'Customer price already in operations';
        }
        return 'Waiting for customer response';
    }

    private static String buildQuoteStageLabel(Boolean hasCustomerRate, String normalizedStatus) {
        if (hasCustomerRate != true) {
            return 'Not quoted';
        }
        if (normalizedStatus == 'assigned') {
            return 'Quote approval stage';
        }
        if (normalizedStatus == 'dispatched' || normalizedStatus == 'in transit to pickup' || normalizedStatus == 'at shipping' || normalizedStatus == 'in transit to delivery' || normalizedStatus == 'at receiving') {
            return 'Operations stage';
        }
        if (normalizedStatus != null && normalizedStatus.contains('deliver')) {
            return 'Delivered / billing stage';
        }
        return 'Quote published';
    }

    private static String buildQuoteNextActionLabel(Boolean hasCustomerRate, String quoteStatus, String normalizedStatus) {
        if (hasCustomerRate != true) {
            return 'No customer-facing quote amount has been published for this load yet.';
        }
        String lower = String.isBlank(quoteStatus) ? '' : quoteStatus.trim().toLowerCase();
        if (lower == 'approved' || lower == 'accepted') {
            return 'Customer accepted this quote.';
        }
        if (lower == 'rejected' || lower == 'declined') {
            return 'Customer declined this quote.';
        }
        if (normalizedStatus == 'assigned') {
            return 'Customer can accept or decline this quote before dispatch begins.';
        }
        return 'This load is already past the customer quote approval window.';
    }

    @TestVisible
    private static Boolean hasFinalQuoteResponse(String quoteStatus) {
        if (String.isBlank(quoteStatus)) return false;
        String lower = quoteStatus.trim().toLowerCase();
        return lower == 'approved' || lower == 'accepted'
            || lower == 'rejected' || lower == 'declined';
    }


    @TestVisible
    private static Boolean hasOpenInvoiceIssue(String disputeStatus) {
        if (String.isBlank(disputeStatus)) return false;
        String lower = disputeStatus.trim().toLowerCase();
        return lower == 'open'
            || lower == 'new'
            || lower == 'pending'
            || lower == 'under review'
            || lower == 'in review';
    }

    private static Boolean isDeliveredStatus(String status) {
        if (String.isBlank(status)) return false;
        String lower = status.trim().toLowerCase();
        return lower == 'delivered' || lower == 'completed' || lower == 'closed';
    }

    private static String classifyDocument(String title) {
        String lower = String.isBlank(title) ? '' : title.toLowerCase();
        if (lower.contains('pod') || lower.contains('proof')) return 'POD';
        if (lower.contains('bol') || lower.contains('bill of lading')) return 'BOL';
        if (lower.contains('invoice')) return 'Invoice';
        if (lower.contains('rate')) return 'Rate Confirmation';
        return 'Document';
    }

    private static String formatDate(Date value) {
        if (value == null) return '—';
        return value.format();
    }

    private static String formatDateTime(DateTime value) {
        if (value == null) return '—';
        return value.format();
    }

    private static Id safeId(String value) {
        if (String.isBlank(value)) return null;
        try { return (Id)value; } catch (Exception ex) { return null; }
    }

    private static String sanitizeFileName(String value) {
        String name = String.isBlank(value) ? 'CustomerPortal_File' : value.replaceAll('[^a-zA-Z0-9_. -]', '');
        if (name.length() > 120) name = name.substring(0, 120);
        return name;
    }

    @TestVisible
    private static String sanitizeContentDistributionName(String value) {
        String clean = String.isBlank(value) ? 'Customer Portal Document' : value.trim();
        return clean.length() > 80 ? clean.substring(0, 80) : clean;
    }

    private static String sanitize255(String value) {
        if (String.isBlank(value)) return null;
        return value.length() > 255 ? value.substring(0, 255) : value;
    }
}