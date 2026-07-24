public without sharing class CustomerPortalDriverLocationService {
    public class LocationUpdateResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id loadId;
        @AuraEnabled public DateTime updatedAt;
    }

    /**
     * Intended for Driver Portal server-side use after driver token validation.
     * This method updates the same FreightTM__Load__c record that Customer Portal reads.
     */
    public static void applyLocation(Id loadId, Decimal latitude, Decimal longitude, String locationText, Decimal routeProgressPercent) {
        validateCoordinates(latitude, longitude);
        FreightTM__Load__c updateLoad = new FreightTM__Load__c(
            Id = loadId,
            Driver_Current_Latitude__c = latitude,
            Driver_Current_Longitude__c = longitude,
            Driver_Current_Location_Text__c = sanitize255(locationText),
            Driver_Last_GPS_Update__c = System.now(),
            Route_Progress_Percent__c = normalizeProgress(routeProgressPercent),
            Customer_Visible_Tracking__c = true,
            Tracking_Map_Enabled__c = true
        );
        update updateLoad;
    }

    /**
     * Optional direct endpoint for a Driver Portal LWC/Aura component.
     * The driverPortalToken must match FreightTM__Load__c.Driver_Portal_Token_Hash__c.
     */
    @AuraEnabled
    public static LocationUpdateResult updateDriverLocation(String driverPortalToken, String loadId, Decimal latitude, Decimal longitude, String locationText, Decimal routeProgressPercent) {
        Id targetLoadId = safeId(loadId);
        if (targetLoadId == null) {
            throw new AuraHandledException('Load is required.');
        }
        if (String.isBlank(driverPortalToken)) {
            throw new AuraHandledException('Driver portal token is required.');
        }
        validateCoordinates(latitude, longitude);

        FreightTM__Load__c loadRec = [
            SELECT Id,
                   Driver_Portal_Active__c,
                   Driver_Portal_Expires_At__c,
                   Driver_Portal_Token_Hash__c
            FROM FreightTM__Load__c
            WHERE Id = :targetLoadId
            LIMIT 1
        ];

        if (loadRec.Driver_Portal_Active__c != true) {
            throw new AuraHandledException('Driver portal access is inactive for this load.');
        }
        if (loadRec.Driver_Portal_Expires_At__c != null && loadRec.Driver_Portal_Expires_At__c < System.now()) {
            throw new AuraHandledException('Driver portal access has expired for this load.');
        }
        String expectedHash = CustomerPortalTokenService.hashToken(driverPortalToken);
        if (String.isBlank(loadRec.Driver_Portal_Token_Hash__c) || expectedHash != loadRec.Driver_Portal_Token_Hash__c) {
            throw new AuraHandledException('Driver portal token is invalid.');
        }

        applyLocation(targetLoadId, latitude, longitude, locationText, routeProgressPercent);

        LocationUpdateResult result = new LocationUpdateResult();
        result.success = true;
        result.message = 'Driver location updated.';
        result.loadId = targetLoadId;
        result.updatedAt = System.now();
        return result;
    }

    private static void validateCoordinates(Decimal latitude, Decimal longitude) {
        if (latitude == null || longitude == null) {
            throw new AuraHandledException('Latitude and longitude are required.');
        }
        if (latitude < -90 || latitude > 90) {
            throw new AuraHandledException('Latitude must be between -90 and 90.');
        }
        if (longitude < -180 || longitude > 180) {
            throw new AuraHandledException('Longitude must be between -180 and 180.');
        }
    }

    private static Decimal normalizeProgress(Decimal value) {
        if (value == null) return null;
        if (value < 0) return 0;
        if (value > 100) return 100;
        return value.setScale(2);
    }

    private static Id safeId(String value) {
        if (String.isBlank(value)) return null;
        try { return (Id)value; } catch (Exception ex) { return null; }
    }

    private static String sanitize255(String value) {
        if (String.isBlank(value)) return null;
        return value.length() > 255 ? value.substring(0, 255) : value;
    }
}