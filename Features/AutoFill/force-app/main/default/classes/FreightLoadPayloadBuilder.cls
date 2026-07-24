public without sharing class FreightLoadPayloadBuilder {

    public static Map<String, Object> build(FreightTM__Load__c loadRecord) {
        Map<String, Object> body = new Map<String, Object>();

        body.put('ExternalId', valueOrBlank(loadRecord.Id));

        body.put('OriginZip', valueOrBlank(loadRecord.FreightTM__Pickup_Zip_Code__c));
        body.put('OriginCity', valueOrBlank(loadRecord.FreightTM__Pickup_City__c));
        body.put('OriginState', valueOrBlank(loadRecord.FreightTM__Pickup_State__c));
        body.put('OriginCountry', valueOrBlank(loadRecord.FreightTM__Pickup_Country__c));

        body.put('DestinationZip', valueOrBlank(loadRecord.FreightTM__Delivery_Zip_Code__c));
        body.put('DestinationCity', valueOrBlank(loadRecord.FreightTM__Delivery_City__c));
        body.put('DestinationState', valueOrBlank(loadRecord.FreightTM__Delivery_State__c));
        body.put('DestinationCountry', valueOrBlank(loadRecord.FreightTM__Delivery_Country__c));

        body.put('EquipmentType', String.isBlank(loadRecord.FreightTM__Trailer__c) ? 'Van' : loadRecord.FreightTM__Trailer__c);
        body.put('LoadType', String.isBlank(loadRecord.FreightTM__Size__c) ? 'FTL' : loadRecord.FreightTM__Size__c);

        body.put('PickupDate', formatDateTimeUtc(loadRecord.FreightTM__Pickup_Arrival__c));
        body.put('DeliveryDate', formatDateTimeUtc(loadRecord.FreightTM__Delivery_Arrival__c));

        body.put('WeightLbs', loadRecord.FreightTM__Weight__c == null ? 0 : loadRecord.FreightTM__Weight__c);
        body.put('RateUsd', loadRecord.FreightTM__Rate__c == null ? 0 : loadRecord.FreightTM__Rate__c);

        body.put('Notes', valueOrBlank(loadRecord.FreightTM__Remarks__c));

        return body;
    }

    private static String valueOrBlank(Object value) {
        return value == null ? '' : String.valueOf(value);
    }

    private static String formatDateTimeUtc(Datetime dt) {
        if (dt == null) {
            return null;
        }

        return dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
    }
}