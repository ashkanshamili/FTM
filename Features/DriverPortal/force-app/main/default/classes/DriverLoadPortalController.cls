public without sharing class DriverLoadPortalController {
    public class PortalData {
        @AuraEnabled public Id loadId;
        @AuraEnabled public String loadName;
        @AuraEnabled public String status;
        @AuraEnabled public String route;
        @AuraEnabled public String driverName;
        @AuraEnabled public String driverEmail;
        @AuraEnabled public String carrierName;
        @AuraEnabled public String carrierEmail;
        
        @AuraEnabled public String pickupFacility;
        @AuraEnabled public String pickupAddress;
        @AuraEnabled public String pickupContact;
        @AuraEnabled public String pickupPhone;
        @AuraEnabled public String pickupEmail;
        @AuraEnabled public String pickupRef;
        @AuraEnabled public String pickupRemarks;
        @AuraEnabled public Datetime pickupArrival;
        @AuraEnabled public Datetime pickupDeparture;
        
        @AuraEnabled public String deliveryFacility;
        @AuraEnabled public String deliveryAddress;
        @AuraEnabled public String deliveryContact;
        @AuraEnabled public String deliveryPhone;
        @AuraEnabled public String deliveryEmail;
        @AuraEnabled public String deliveryRef;
        @AuraEnabled public String deliveryRemarks;
        @AuraEnabled public Datetime deliveryArrival;
        @AuraEnabled public Datetime deliveryDeparture;
        
        @AuraEnabled public String commodity;
        @AuraEnabled public Decimal weight;
        @AuraEnabled public Decimal distance;
        @AuraEnabled public String remarks;
        @AuraEnabled public String requirements;
        @AuraEnabled public String driverRemarks;
        @AuraEnabled public String exceptionReason;
        
        @AuraEnabled public Boolean portalClosed;
        @AuraEnabled public String portalClosedMessage;
        
        @AuraEnabled public List<LegDTO> legs;
    }
    
    public class LegDTO {
        @AuraEnabled public Id legId;
        @AuraEnabled public String legName;
        @AuraEnabled public String status;
    }
    
    @AuraEnabled
    public static PortalData getPortalData(String token) {
        FreightTM__Load__c tokenLoad =
            //DriverLoadPortalTokenService.validateToken(token);
            DriverLoadPortalTokenService.validateTokenForDisplay(token);
        
        FreightTM__Load__c loadRec = [
            SELECT Id,
            Name, Driver_Portal_Active__c,
            FreightTM__Status__c,
            FreightTM__Calendar_Load__c,
            
            FreightTM__Driver__c,
            FreightTM__Driver__r.Name,
            FreightTM__Driver_Email__c,
            
            FreightTM__Carrier_Obj__c,
            FreightTM__Carrier_Obj__r.Name,
            FreightTM__Carrier_Email__c,
            
            FreightTM__PickupFacility__c,
            FreightTM__PickupFacility__r.Name,
            FreightTM__Pickup_Address__c,
            FreightTM__Pickup_City__c,
            FreightTM__Pickup_State__c,
            FreightTM__Pickup_Zip_Code__c,
            FreightTM__Pickup_Country__c,
            FreightTM__Pickup_Contact__c,
            FreightTM__Pickup_Phone__c,
            FreightTM__Pickup_Email__c,
            FreightTM__Pickup_Ref__c,
            FreightTM__Pickup_Remarks__c,
            FreightTM__Pickup_Arrival__c,
            FreightTM__Pickup_Departure__c,
            
            FreightTM__DeliveryFacility__c,
            FreightTM__DeliveryFacility__r.Name,
            FreightTM__Delivery_Address__c,
            FreightTM__Delivery_City__c,
            FreightTM__Delivery_State__c,
            FreightTM__Delivery_Zip_Code__c,
            FreightTM__Delivery_Country__c,
            FreightTM__Delivery_Contact__c,
            FreightTM__Delivery_Phone__c,
            FreightTM__Delivery_Email__c,
            FreightTM__Delivery_Ref__c,
            FreightTM__Delivery_Remarks__c,
            FreightTM__Delivery_Arrival__c,
            FreightTM__Delivery_Departure__c,
            
            FreightTM__Commodity__c,
            FreightTM__Weight__c,
            FreightTM__Distance__c,
            FreightTM__Remarks__c,
            FreightTM__Requirements__c, 
            FreightTM__Driver_Remarks__c,
            Exception_Reason__c
            
            FROM FreightTM__Load__c
            WHERE Id = :tokenLoad.Id
            LIMIT 1
        ];
        
        PortalData data = new PortalData();
        data.loadId = loadRec.Id;
        data.loadName = loadRec.Name;
        data.status = loadRec.FreightTM__Status__c;
        data.route = loadRec.FreightTM__Calendar_Load__c;
        
        data.portalClosed =
            loadRec.Driver_Portal_Active__c != true ||
            loadRec.FreightTM__Status__c == 'Delivered';
        
        data.portalClosedMessage = data.portalClosed
            ? 'This delivery has been completed. Thank you.'
            : null;
        
        data.driverName = loadRec.FreightTM__Driver__r != null
            ? loadRec.FreightTM__Driver__r.Name
            : null;
        data.driverEmail = loadRec.FreightTM__Driver_Email__c;
        
        data.carrierName = loadRec.FreightTM__Carrier_Obj__r != null
            ? loadRec.FreightTM__Carrier_Obj__r.Name
            : null;
        data.carrierEmail = loadRec.FreightTM__Carrier_Email__c;
        
        data.pickupFacility = loadRec.FreightTM__PickupFacility__r != null  
            ? loadRec.FreightTM__PickupFacility__r.Name
            : null;
        data.pickupAddress = buildAddress(
            loadRec.FreightTM__Pickup_Address__c,
            loadRec.FreightTM__Pickup_City__c,
            loadRec.FreightTM__Pickup_State__c,
            loadRec.FreightTM__Pickup_Zip_Code__c,
            loadRec.FreightTM__Pickup_Country__c
        );
        data.pickupContact = loadRec.FreightTM__Pickup_Contact__c;
        data.pickupPhone = loadRec.FreightTM__Pickup_Phone__c;
        data.pickupEmail = loadRec.FreightTM__Pickup_Email__c;
        data.pickupRef = loadRec.FreightTM__Pickup_Ref__c;
        data.pickupRemarks = loadRec.FreightTM__Pickup_Remarks__c;
        data.pickupArrival = loadRec.FreightTM__Pickup_Arrival__c;
        data.pickupDeparture = loadRec.FreightTM__Pickup_Departure__c;
        
        data.deliveryFacility = loadRec.FreightTM__DeliveryFacility__r != null
            ? loadRec.FreightTM__DeliveryFacility__r.Name
            : null;
        data.deliveryAddress = buildAddress(
            loadRec.FreightTM__Delivery_Address__c,
            loadRec.FreightTM__Delivery_City__c,
            loadRec.FreightTM__Delivery_State__c,
            loadRec.FreightTM__Delivery_Zip_Code__c,
            loadRec.FreightTM__Delivery_Country__c
        );
        data.deliveryContact = loadRec.FreightTM__Delivery_Contact__c;
        data.deliveryPhone = loadRec.FreightTM__Delivery_Phone__c;
        data.deliveryEmail = loadRec.FreightTM__Delivery_Email__c;
        data.deliveryRef = loadRec.FreightTM__Delivery_Ref__c;
        data.deliveryRemarks = loadRec.FreightTM__Delivery_Remarks__c;
        data.deliveryArrival = loadRec.FreightTM__Delivery_Arrival__c;
        data.deliveryDeparture = loadRec.FreightTM__Delivery_Departure__c;
        
        data.commodity = loadRec.FreightTM__Commodity__c;
        data.weight = loadRec.FreightTM__Weight__c;
        data.distance = loadRec.FreightTM__Distance__c;
        data.remarks = loadRec.FreightTM__Remarks__c;
        data.requirements = loadRec.FreightTM__Requirements__c;
        data.driverRemarks = loadRec.FreightTM__Driver_Remarks__c;
        data.exceptionReason = loadRec.Exception_Reason__c;
        
        data.legs = new List<LegDTO>();
        
        for (FreightTM__Leg__c leg : [
            SELECT Id, Name, FreightTM__Status__c
            FROM FreightTM__Leg__c
            WHERE FreightTM__Load__c = :loadRec.Id
            ORDER BY CreatedDate ASC
        ]) {
            LegDTO dto = new LegDTO();
            dto.legId = leg.Id;
            dto.legName = leg.Name;
            dto.status = leg.FreightTM__Status__c;
            data.legs.add(dto);
        }
        
        return data;
    }
    
    @AuraEnabled
    public static void updateLoadStatus(String token, String actionName) {
        FreightTM__Load__c loadRec =
            DriverLoadPortalTokenService.validateToken(token);
        
        if (String.isBlank(actionName)) {
            throw new AuraHandledException('Action is required.');
        }
        
        Set<String> allowedActions = new Set<String>{
            'ARRIVED_PICKUP',
                'DEPARTED_PICKUP',
                'ARRIVED_DELIVERY',
                'DELIVERED'
                };
                    
                    if (!allowedActions.contains(actionName)) {
                        throw new AuraHandledException('Invalid status action.');
                    }
        
        Driver_Portal_Action__e evt = new Driver_Portal_Action__e();
        evt.Load_Id__c = String.valueOf(loadRec.Id);
        evt.Action_Name__c = actionName;
        evt.Token_Hash__c = DriverLoadPortalTokenService.hashToken(token);
        evt.Event_Time__c = System.now();
        
        Database.SaveResult result = EventBus.publish(evt);
        System.debug('Driver portal event publish success: ' + result.isSuccess());
        System.debug('Driver portal event action: ' + actionName);
        System.debug('Driver portal event load: ' + loadRec.Id);
        
        if (!result.isSuccess()) {
            String message = 'Unable to submit driver status update.';
            
            if (!result.getErrors().isEmpty()) {
                message += ' ' + result.getErrors()[0].getMessage();
            }
            
            throw new AuraHandledException(message);
        }
    }
    
    @AuraEnabled
    public static void saveLocation(
        String token,
        Decimal latitude,
        Decimal longitude,
        String deviceInfo
    ) {
        FreightTM__Load__c loadRec =
            DriverLoadPortalTokenService.validateToken(token);
        
        if (latitude == null || longitude == null) {
            throw new AuraHandledException('Latitude and longitude are required.');
        }
        
        FreightTM__Site_Location__c loc = new FreightTM__Site_Location__c();
        
        loc.FreightTM__Load__c = loadRec.Id;
        loc.FreightTM__Coordinates__latitude__s = latitude;
        loc.FreightTM__Coordinates__longitude__s = longitude;
        loc.FreightTM__Location_Name__c = 'Driver Browser Location';
        loc.FreightTM__Remarks__c = buildLocationRemarks(deviceInfo);
        
        insert loc;
    }
    
    @AuraEnabled
    public static Id saveSignature(
        String token,
        String signatureDataUrl,
        String signerName,
        String signatureType
    ) {
        try {
            FreightTM__Load__c validatedLoad =
                DriverLoadPortalTokenService.validateToken(token);

            if (String.isBlank(signatureDataUrl)) {
                throw new AuraHandledException('Signature is required.');
            }

            if (String.isBlank(signerName)) {
                throw new AuraHandledException('Signer name is required.');
            }

            FreightTM__Load__c loadRec = [
                SELECT Id, FreightTM__Status__c
                FROM FreightTM__Load__c
                WHERE Id = :validatedLoad.Id
                LIMIT 1
            ];

            SignatureContext context =
                getSignatureContext(loadRec.FreightTM__Status__c);

            String cleanBase64 = signatureDataUrl.contains(',')
                ? signatureDataUrl.substringAfter(',')
                : signatureDataUrl;

            Blob signatureBody;
            try {
                signatureBody = EncodingUtil.base64Decode(cleanBase64);
            } catch (Exception decodeException) {
                throw new AuraHandledException('The signature image is invalid.');
            }

            String safeType = sanitizeSignatureValue(
                String.isBlank(signatureType)
                    ? context.defaultSignerType
                    : signatureType,
                'Contact'
            );

            String safeSigner = sanitizeSignatureValue(signerName, 'Unknown');

            String signatureTitle =
                'DriverPortal_Signature_' +
                safeType + '_' +
                safeSigner + '_' +
                context.fileSuffix;

            List<ContentDocumentLink> existingLinks = [
                SELECT ContentDocumentId, ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :loadRec.Id
                  AND ContentDocument.Title = :signatureTitle
                ORDER BY ContentDocument.LastModifiedDate DESC
                LIMIT 1
            ];

            if (!existingLinks.isEmpty()) {
                publishSignatureSavedEvent(
                    loadRec.Id,
                    token,
                    context.eventAction
                );
                return existingLinks[0].ContentDocumentId;
            }

            ContentVersion signatureVersion = new ContentVersion();
            signatureVersion.Title = signatureTitle;
            signatureVersion.PathOnClient = signatureTitle + '.png';
            signatureVersion.VersionData = signatureBody;
            signatureVersion.FirstPublishLocationId = loadRec.Id;

            try {
                insert signatureVersion;
            } catch (DmlException fileException) {
                throw new AuraHandledException(
                    'Unable to create the signature file: ' +
                    fileException.getDmlMessage(0)
                );
            }

            publishSignatureSavedEvent(
                loadRec.Id,
                token,
                context.eventAction
            );

            return signatureVersion.Id;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            System.debug(
                LoggingLevel.ERROR,
                'saveSignature failed: ' +
                unexpectedException.getTypeName() + ' - ' +
                unexpectedException.getMessage() + '\n' +
                unexpectedException.getStackTraceString()
            );
            throw new AuraHandledException(
                'Unable to save signature: ' +
                unexpectedException.getMessage()
            );
        }
    }

    @AuraEnabled
    public static Id uploadFile(
        String token,
        String fileName,
        String base64Data
    ) {
        FreightTM__Load__c loadRec =
            DriverLoadPortalTokenService.validateToken(token);
        
        if (String.isBlank(fileName) || String.isBlank(base64Data)) {
            throw new AuraHandledException(
                'File name and file data are required.'
            );
        }
        
        String cleanFileName = fileName.trim();
        
        if (cleanFileName.length() > 200) {
            cleanFileName = cleanFileName.substring(0, 200);
        }
        
        String cleanBase64 = base64Data.contains(',')
            ? base64Data.substringAfter(',')
            : base64Data;
        
        /*
* Approximately 1 MB of binary data becomes about
* 1.4 million Base64 characters.
*/
        Integer maxBase64Length = 1400000;
        
        if (cleanBase64.length() > maxBase64Length) {
            throw new AuraHandledException(
                'File is too large. Maximum size is 1 MB.'
            );
        }
        
        Blob body;
        
        try {
            body = EncodingUtil.base64Decode(cleanBase64);
        } catch (Exception decodeException) {
            throw new AuraHandledException(
                'The selected file could not be processed.'
            );
        }
        
        Integer maxFileSizeBytes = 1 * 1024 * 1024;
        
        if (body.size() > maxFileSizeBytes) {
            throw new AuraHandledException(
                'File is too large. Maximum size is 1 MB.'
            );
        }
        
        ContentVersion cv = new ContentVersion();
        cv.Title = 'DriverPortal_' + cleanFileName;
        cv.PathOnClient = cleanFileName;
        cv.VersionData = body;
        cv.FirstPublishLocationId = loadRec.Id;
        
        try {
            insert cv;
        } catch (DmlException fileException) {
            throw new AuraHandledException(
                'Unable to upload the file: ' +
                fileException.getDmlMessage(0)
            );
        }
        
        return cv.Id;
    }
    
    private static String buildAddress(
        String street,
        String city,
        String state,
        String zip,
        String country
    ) {
        List<String> parts = new List<String>();
        
        if (!String.isBlank(street)) parts.add(street);
        if (!String.isBlank(city)) parts.add(city);
        if (!String.isBlank(state)) parts.add(state);
        if (!String.isBlank(zip)) parts.add(zip);
        if (!String.isBlank(country)) parts.add(country);
        
        return String.join(parts, ', ');
    }
    
    private static String buildLocationRemarks(String deviceInfo) {
        String remarks = 'Captured from Driver-Carrier Portal';
        
        if (!String.isBlank(deviceInfo)) {
            remarks += ' | Device: ' + deviceInfo;
        }
        
        if (remarks.length() > 255) {
            remarks = remarks.substring(0, 255);
        }
        
        return remarks;
    }
    
    @AuraEnabled
    public static void recordPortalOpened(String token) {
        FreightTM__Load__c loadRec =
            DriverLoadPortalTokenService.validateToken(token);
        
        Driver_Portal_Action__e evt = new Driver_Portal_Action__e();
        evt.Load_Id__c = String.valueOf(loadRec.Id);
        evt.Action_Name__c = 'PORTAL_OPENED';
        evt.Token_Hash__c = DriverLoadPortalTokenService.hashToken(token);
        evt.Event_Time__c = System.now();
        
        EventBus.publish(evt);
    }
    
    
    @AuraEnabled
    public static void reportIssue(
        String token,
        String issueType,
        String notes
    ) {
        FreightTM__Load__c loadRec =
            DriverLoadPortalTokenService.validateToken(token);
        
        if (String.isBlank(issueType)) {
            throw new AuraHandledException('Exception reason is required.');
        }
        
        if (String.isBlank(notes)) {
            throw new AuraHandledException('Driver remarks are required.');
        }
        
        String cleanIssueType = issueType.trim();
        String cleanNotes = notes.trim();
        
        if (cleanIssueType.length() > 100) {
            cleanIssueType = cleanIssueType.substring(0, 100);
        }
        
        if (cleanNotes.length() > 255) {
            throw new AuraHandledException(
                'Driver remarks must be 255 characters or fewer.'
            );
        }
        
        Driver_Portal_Action__e evt = new Driver_Portal_Action__e();
        evt.Load_Id__c = String.valueOf(loadRec.Id);
        evt.Action_Name__c = 'ISSUE_REPORTED';
        evt.Token_Hash__c = DriverLoadPortalTokenService.hashToken(token);
        evt.Event_Time__c = System.now();
        
        evt.Issue_Type__c = cleanIssueType;
        evt.Notes__c = cleanNotes;
        
        Database.SaveResult result = EventBus.publish(evt);
        
        if (!result.isSuccess()) {
            String message = 'Unable to submit driver issue.';
            
            if (!result.getErrors().isEmpty()) {
                message += ' ' + result.getErrors()[0].getMessage();
            }
            
            throw new AuraHandledException(message);
        }
    }

    private class SignatureContext {
        public String fileSuffix;
        public String eventAction;
        public String defaultSignerType;

        public SignatureContext(
            String fileSuffix,
            String eventAction,
            String defaultSignerType
        ) {
            this.fileSuffix = fileSuffix;
            this.eventAction = eventAction;
            this.defaultSignerType = defaultSignerType;
        }
    }

    private static SignatureContext getSignatureContext(String loadStatus) {
        String normalizedStatus = String.isBlank(loadStatus)
            ? ''
            : loadStatus.trim().toLowerCase();

        if (
            normalizedStatus == 'assigned' ||
            normalizedStatus == 'dispatched' ||
            normalizedStatus == 'in transit to pickup'
        ) {
            return new SignatureContext(
                'PickupArrived',
                'SIGNATURE_AT_SHIPPING',
                'Pickup Contact'
            );
        }

        if (
            normalizedStatus == 'at shipping' ||
            normalizedStatus == 'arrived for pickup'
        ) {
            return new SignatureContext(
                'PickupDeparted',
                'SIGNATURE_IN_TRANSIT_TO_DELIVERY',
                'Pickup Contact'
            );
        }

        if (
            normalizedStatus == 'in transit to delivery' ||
            normalizedStatus == 'departed pickup'
        ) {
            return new SignatureContext(
                'DeliveryArrived',
                'SIGNATURE_AT_RECEIVING',
                'Delivery Contact'
            );
        }

        if (
            normalizedStatus == 'at receiving' ||
            normalizedStatus == 'arrived for delivery'
        ) {
            return new SignatureContext(
                'Delivered',
                'SIGNATURE_DELIVERED',
                'Delivery Contact'
            );
        }

        throw new AuraHandledException(
            'A signature cannot be saved for the current load status: ' +
            loadStatus
        );
    }

    private static String sanitizeSignatureValue(
        String value,
        String fallbackValue
    ) {
        String result = String.isBlank(value)
            ? fallbackValue
            : value.trim();

        result = result.replaceAll('[^a-zA-Z0-9_ -]', '');
        result = result.replaceAll('\\s+', ' ').trim();

        if (String.isBlank(result)) {
            result = fallbackValue;
        }

        if (result.length() > 80) {
            result = result.substring(0, 80);
        }

        return result;
    }

    private static void publishSignatureSavedEvent(
        Id loadId,
        String token,
        String actionName
    ) {
        Driver_Portal_Action__e evt = new Driver_Portal_Action__e();
        evt.Load_Id__c = String.valueOf(loadId);
        evt.Action_Name__c = actionName;
        evt.Token_Hash__c = DriverLoadPortalTokenService.hashToken(token);
        evt.Event_Time__c = System.now();

        Database.SaveResult result = EventBus.publish(evt);

        if (!result.isSuccess()) {
            String message = 'The signature file could not be finalized.';
            if (!result.getErrors().isEmpty()) {
                message += ' ' + result.getErrors()[0].getMessage();
            }
            throw new AuraHandledException(message);
        }
    }
}



/*public without sharing class DriverLoadPortalController {
    public class PortalData {
        @AuraEnabled public Id loadId;
        @AuraEnabled public String loadName;
        @AuraEnabled public String status;
        @AuraEnabled public String route;
        @AuraEnabled public String driverName;
        @AuraEnabled public String driverEmail;
        @AuraEnabled public String carrierName;
        @AuraEnabled public String carrierEmail;
        
        @AuraEnabled public String pickupFacility;
        @AuraEnabled public String pickupAddress;
        @AuraEnabled public String pickupContact;
        @AuraEnabled public String pickupPhone;
        @AuraEnabled public String pickupEmail;
        @AuraEnabled public String pickupRef;
        @AuraEnabled public String pickupRemarks;
        @AuraEnabled public Datetime pickupArrival;
        @AuraEnabled public Datetime pickupDeparture;
        
        @AuraEnabled public String deliveryFacility;
        @AuraEnabled public String deliveryAddress;
        @AuraEnabled public String deliveryContact;
        @AuraEnabled public String deliveryPhone;
        @AuraEnabled public String deliveryEmail;
        @AuraEnabled public String deliveryRef;
        @AuraEnabled public String deliveryRemarks;
        @AuraEnabled public Datetime deliveryArrival;
        @AuraEnabled public Datetime deliveryDeparture;
        
        @AuraEnabled public String commodity;
        @AuraEnabled public Decimal weight;
        @AuraEnabled public Decimal distance;
        @AuraEnabled public String remarks;
        @AuraEnabled public String requirements;
        @AuraEnabled public String driverRemarks;
        @AuraEnabled public String exceptionReason;
        
        @AuraEnabled public Boolean portalClosed;
        @AuraEnabled public String portalClosedMessage;
        
        @AuraEnabled public List<LegDTO> legs;
    }
    
    public class LegDTO {
        @AuraEnabled public Id legId;
        @AuraEnabled public String legName;
        @AuraEnabled public String status;
    }
    
    @AuraEnabled
    public static PortalData getPortalData(String token) {
        FreightTM__Load__c tokenLoad =
            //DriverLoadPortalTokenService.validateToken(token);
            DriverLoadPortalTokenService.validateTokenForDisplay(token);
        
        FreightTM__Load__c loadRec = [
            SELECT Id,
            Name, Driver_Portal_Active__c,
            FreightTM__Status__c,
            FreightTM__Calendar_Load__c,
            
            FreightTM__Driver__c,
            FreightTM__Driver__r.Name,
            FreightTM__Driver_Email__c,
            
            FreightTM__Carrier_Obj__c,
            FreightTM__Carrier_Obj__r.Name,
            FreightTM__Carrier_Email__c,
            
            FreightTM__PickupFacility__c,
            FreightTM__PickupFacility__r.Name,
            FreightTM__Pickup_Address__c,
            FreightTM__Pickup_City__c,
            FreightTM__Pickup_State__c,
            FreightTM__Pickup_Zip_Code__c,
            FreightTM__Pickup_Country__c,
            FreightTM__Pickup_Contact__c,
            FreightTM__Pickup_Phone__c,
            FreightTM__Pickup_Email__c,
            FreightTM__Pickup_Ref__c,
            FreightTM__Pickup_Remarks__c,
            FreightTM__Pickup_Arrival__c,
            FreightTM__Pickup_Departure__c,
            
            FreightTM__DeliveryFacility__c,
            FreightTM__DeliveryFacility__r.Name,
            FreightTM__Delivery_Address__c,
            FreightTM__Delivery_City__c,
            FreightTM__Delivery_State__c,
            FreightTM__Delivery_Zip_Code__c,
            FreightTM__Delivery_Country__c,
            FreightTM__Delivery_Contact__c,
            FreightTM__Delivery_Phone__c,
            FreightTM__Delivery_Email__c,
            FreightTM__Delivery_Ref__c,
            FreightTM__Delivery_Remarks__c,
            FreightTM__Delivery_Arrival__c,
            FreightTM__Delivery_Departure__c,
            
            FreightTM__Commodity__c,
            FreightTM__Weight__c,
            FreightTM__Distance__c,
            FreightTM__Remarks__c,
            FreightTM__Requirements__c, 
            FreightTM__Driver_Remarks__c,
            Exception_Reason__c
            
            FROM FreightTM__Load__c
            WHERE Id = :tokenLoad.Id
            LIMIT 1
        ];
        
        PortalData data = new PortalData();
        data.loadId = loadRec.Id;
        data.loadName = loadRec.Name;
        data.status = loadRec.FreightTM__Status__c;
        data.route = loadRec.FreightTM__Calendar_Load__c;
        
        data.portalClosed =
            loadRec.Driver_Portal_Active__c != true ||
            loadRec.FreightTM__Status__c == 'Delivered';
        
        data.portalClosedMessage = data.portalClosed
            ? 'This delivery has been completed. Thank you.'
            : null;
        
        data.driverName = loadRec.FreightTM__Driver__r != null
            ? loadRec.FreightTM__Driver__r.Name
            : null;
        data.driverEmail = loadRec.FreightTM__Driver_Email__c;
        
        data.carrierName = loadRec.FreightTM__Carrier_Obj__r != null
            ? loadRec.FreightTM__Carrier_Obj__r.Name
            : null;
        data.carrierEmail = loadRec.FreightTM__Carrier_Email__c;
        
        data.pickupFacility = loadRec.FreightTM__PickupFacility__r != null  
            ? loadRec.FreightTM__PickupFacility__r.Name
            : null;
        data.pickupAddress = buildAddress(
            loadRec.FreightTM__Pickup_Address__c,
            loadRec.FreightTM__Pickup_City__c,
            loadRec.FreightTM__Pickup_State__c,
            loadRec.FreightTM__Pickup_Zip_Code__c,
            loadRec.FreightTM__Pickup_Country__c
        );
        data.pickupContact = loadRec.FreightTM__Pickup_Contact__c;
        data.pickupPhone = loadRec.FreightTM__Pickup_Phone__c;
        data.pickupEmail = loadRec.FreightTM__Pickup_Email__c;
        data.pickupRef = loadRec.FreightTM__Pickup_Ref__c;
        data.pickupRemarks = loadRec.FreightTM__Pickup_Remarks__c;
        data.pickupArrival = loadRec.FreightTM__Pickup_Arrival__c;
        data.pickupDeparture = loadRec.FreightTM__Pickup_Departure__c;
        
        data.deliveryFacility = loadRec.FreightTM__DeliveryFacility__r != null
            ? loadRec.FreightTM__DeliveryFacility__r.Name
            : null;
        data.deliveryAddress = buildAddress(
            loadRec.FreightTM__Delivery_Address__c,
            loadRec.FreightTM__Delivery_City__c,
            loadRec.FreightTM__Delivery_State__c,
            loadRec.FreightTM__Delivery_Zip_Code__c,
            loadRec.FreightTM__Delivery_Country__c
        );
        data.deliveryContact = loadRec.FreightTM__Delivery_Contact__c;
        data.deliveryPhone = loadRec.FreightTM__Delivery_Phone__c;
        data.deliveryEmail = loadRec.FreightTM__Delivery_Email__c;
        data.deliveryRef = loadRec.FreightTM__Delivery_Ref__c;
        data.deliveryRemarks = loadRec.FreightTM__Delivery_Remarks__c;
        data.deliveryArrival = loadRec.FreightTM__Delivery_Arrival__c;
        data.deliveryDeparture = loadRec.FreightTM__Delivery_Departure__c;
        
        data.commodity = loadRec.FreightTM__Commodity__c;
        data.weight = loadRec.FreightTM__Weight__c;
        data.distance = loadRec.FreightTM__Distance__c;
        data.remarks = loadRec.FreightTM__Remarks__c;
        data.requirements = loadRec.FreightTM__Requirements__c;
        data.driverRemarks = loadRec.FreightTM__Driver_Remarks__c;
        data.exceptionReason = loadRec.Exception_Reason__c;
        
        data.legs = new List<LegDTO>();
        
        for (FreightTM__Leg__c leg : [
            SELECT Id, Name, FreightTM__Status__c
            FROM FreightTM__Leg__c
            WHERE FreightTM__Load__c = :loadRec.Id
            ORDER BY CreatedDate ASC
        ]) {
            LegDTO dto = new LegDTO();
            dto.legId = leg.Id;
            dto.legName = leg.Name;
            dto.status = leg.FreightTM__Status__c;
            data.legs.add(dto);
        }
        
        return data;
    }
    
    @AuraEnabled
    public static void updateLoadStatus(String token, String actionName) {
        FreightTM__Load__c loadRec =
            DriverLoadPortalTokenService.validateToken(token);
        
        if (String.isBlank(actionName)) {
            throw new AuraHandledException('Action is required.');
        }
        
        Set<String> allowedActions = new Set<String>{
            'ARRIVED_PICKUP',
                'DEPARTED_PICKUP',
                'ARRIVED_DELIVERY',
                'DELIVERED'
                };
                    
                    if (!allowedActions.contains(actionName)) {
                        throw new AuraHandledException('Invalid status action.');
                    }
        
        Driver_Portal_Action__e evt = new Driver_Portal_Action__e();
        evt.Load_Id__c = String.valueOf(loadRec.Id);
        evt.Action_Name__c = actionName;
        evt.Token_Hash__c = DriverLoadPortalTokenService.hashToken(token);
        evt.Event_Time__c = System.now();
        
        Database.SaveResult result = EventBus.publish(evt);
        System.debug('Driver portal event publish success: ' + result.isSuccess());
        System.debug('Driver portal event action: ' + actionName);
        System.debug('Driver portal event load: ' + loadRec.Id);
        
        if (!result.isSuccess()) {
            String message = 'Unable to submit driver status update.';
            
            if (!result.getErrors().isEmpty()) {
                message += ' ' + result.getErrors()[0].getMessage();
            }
            
            throw new AuraHandledException(message);
        }
    }
    
    @AuraEnabled
    public static void saveLocation(
        String token,
        Decimal latitude,
        Decimal longitude,
        String deviceInfo
    ) {
        FreightTM__Load__c loadRec =
            DriverLoadPortalTokenService.validateToken(token);
        
        if (latitude == null || longitude == null) {
            throw new AuraHandledException('Latitude and longitude are required.');
        }
        
        FreightTM__Site_Location__c loc = new FreightTM__Site_Location__c();
        
        loc.FreightTM__Load__c = loadRec.Id;
        loc.FreightTM__Coordinates__latitude__s = latitude;
        loc.FreightTM__Coordinates__longitude__s = longitude;
        loc.FreightTM__Location_Name__c = 'Driver Browser Location';
        loc.FreightTM__Remarks__c = buildLocationRemarks(deviceInfo);
        
        insert loc;
    }
    
    @AuraEnabled
    public static Id saveSignature(
        String token,
        String signatureDataUrl,
        String signerName,
        String signatureType
    ) {
        FreightTM__Load__c loadRec =
            DriverLoadPortalTokenService.validateToken(token);
        
        if (String.isBlank(signatureDataUrl)) {
            throw new AuraHandledException('Signature is required.');
        }
        
        String base64Data = signatureDataUrl.contains(',')
            ? signatureDataUrl.substringAfter(',')
            : signatureDataUrl;
        
        Blob body = EncodingUtil.base64Decode(base64Data);
        
        String safeType = String.isBlank(signatureType)
            ? 'Driver'
            : signatureType.replaceAll('[^a-zA-Z0-9_ -]', '');
        
        String safeSigner = String.isBlank(signerName)
            ? 'Unknown'
            : signerName.replaceAll('[^a-zA-Z0-9_ -]', '');
        
        ContentVersion cv = new ContentVersion();
        cv.Title = 'DriverPortal_Signature_' + safeType + '_' + safeSigner;
        cv.PathOnClient = 'signature.png';
        cv.VersionData = body;
        cv.FirstPublishLocationId = loadRec.Id;
        
        insert cv;
        
        return cv.Id;
    }
    
    @AuraEnabled
    public static Id uploadFile(
        String token,
        String fileName,
        String base64Data
    ) {
        FreightTM__Load__c loadRec =
            DriverLoadPortalTokenService.validateToken(token);
        
        if (String.isBlank(fileName) || String.isBlank(base64Data)) {
            throw new AuraHandledException('File name and file data are required.');
        }
        
        String cleanBase64 = base64Data.contains(',')
            ? base64Data.substringAfter(',')
            : base64Data;
        
        Blob body = EncodingUtil.base64Decode(cleanBase64);
        
        ContentVersion cv = new ContentVersion();
        cv.Title = 'DriverPortal_' + fileName;
        cv.PathOnClient = fileName;
        cv.VersionData = body;
        cv.FirstPublishLocationId = loadRec.Id;
        
        insert cv;
        
        return cv.Id;
    }
    
    private static String buildAddress(
        String street,
        String city,
        String state,
        String zip,
        String country
    ) {
        List<String> parts = new List<String>();
        
        if (!String.isBlank(street)) parts.add(street);
        if (!String.isBlank(city)) parts.add(city);
        if (!String.isBlank(state)) parts.add(state);
        if (!String.isBlank(zip)) parts.add(zip);
        if (!String.isBlank(country)) parts.add(country);
        
        return String.join(parts, ', ');
    }
    
    private static String buildLocationRemarks(String deviceInfo) {
        String remarks = 'Captured from Driver-Carrier Portal';
        
        if (!String.isBlank(deviceInfo)) {
            remarks += ' | Device: ' + deviceInfo;
        }
        
        if (remarks.length() > 255) {
            remarks = remarks.substring(0, 255);
        }
        
        return remarks;
    }
    
    @AuraEnabled
    public static void recordPortalOpened(String token) {
        FreightTM__Load__c loadRec =
            DriverLoadPortalTokenService.validateToken(token);
        
        Driver_Portal_Action__e evt = new Driver_Portal_Action__e();
        evt.Load_Id__c = String.valueOf(loadRec.Id);
        evt.Action_Name__c = 'PORTAL_OPENED';
        evt.Token_Hash__c = DriverLoadPortalTokenService.hashToken(token);
        evt.Event_Time__c = System.now();
        
        EventBus.publish(evt);
    }
    
    
    @AuraEnabled
    public static void reportIssue(
        String token,
        String issueType,
        String notes
    ) {
        FreightTM__Load__c loadRec =
            DriverLoadPortalTokenService.validateToken(token);
        
        if (String.isBlank(issueType)) {
            throw new AuraHandledException('Exception reason is required.');
        }
        
        if (String.isBlank(notes)) {
            throw new AuraHandledException('Driver remarks are required.');
        }
        
        String cleanIssueType = issueType.trim();
        String cleanNotes = notes.trim();
        
        if (cleanIssueType.length() > 100) {
            cleanIssueType = cleanIssueType.substring(0, 100);
        }
        
        if (cleanNotes.length() > 255) {
            cleanNotes = cleanNotes.substring(0, 255);
        }
        
        Driver_Portal_Action__e evt = new Driver_Portal_Action__e();
        evt.Load_Id__c = String.valueOf(loadRec.Id);
        evt.Action_Name__c = 'ISSUE_REPORTED';
        evt.Token_Hash__c = DriverLoadPortalTokenService.hashToken(token);
        evt.Event_Time__c = System.now();
        
        evt.Issue_Type__c = cleanIssueType;
        evt.Notes__c = cleanNotes;
        
        Database.SaveResult result = EventBus.publish(evt);
        
        if (!result.isSuccess()) {
            String message = 'Unable to submit driver issue.';
            
            if (!result.getErrors().isEmpty()) {
                message += ' ' + result.getErrors()[0].getMessage();
            }
            
            throw new AuraHandledException(message);
        }
    }
}*/