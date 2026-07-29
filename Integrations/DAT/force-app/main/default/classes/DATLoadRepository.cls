public with sharing class DATLoadRepository {
    public static FreightTM__Load__c getLoad(Id loadId) {
        if (loadId == null) {
            throw new DATIntegrationException('Load ID is required.');
        }
        if (!FreightTM__Load__c.SObjectType.getDescribe().isAccessible()) {
            throw new DATIntegrationException('You do not have access to Loads.');
        }

        List<FreightTM__Load__c> records = [
            SELECT Id, Name,
                DAT_Post_Id__c, DAT_Shipment_Id__c, Total_Linear_Feet__c,
                FreightTM__Remarks__c, FreightTM__Required_Trailer__c,
                FreightTM__Size__c, FreightTM__Weight__c,
                FreightTM__Pickup_City__c, FreightTM__Pickup_State__c,
                FreightTM__Pickup_Zip_Code__c,
                FreightTM__Delivery_City__c, FreightTM__Delivery_State__c,
                FreightTM__Delivery_Zip_Code__c,
                FreightTM__Pickup_Date__c, FreightTM__Delivery_Date__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];

        if (records.isEmpty()) {
            throw new DATIntegrationException('Load was not found or is not accessible.');
        }

        List<SObject> genericRecords = new List<SObject>();
        genericRecords.add(records[0]);
        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.READABLE,
            genericRecords
        );
        return (FreightTM__Load__c) decision.getRecords()[0];
    }

    public static void saveDatIds(Id loadId, String postId, String shipmentId) {
        requireDatFieldsUpdateable();
        update new FreightTM__Load__c(
            Id = loadId,
            DAT_Post_Id__c = postId,
            DAT_Shipment_Id__c = shipmentId
        );
    }

    public static void clearDatIds(Id loadId) {
        saveDatIds(loadId, null, null);
    }

    private static void requireDatFieldsUpdateable() {
        if (!FreightTM__Load__c.SObjectType.getDescribe().isUpdateable()
            || !FreightTM__Load__c.DAT_Post_Id__c.getDescribe().isUpdateable()
            || !FreightTM__Load__c.DAT_Shipment_Id__c.getDescribe().isUpdateable()) {
            throw new DATIntegrationException('You do not have permission to update the DAT fields on this Load.');
        }
    }
}
