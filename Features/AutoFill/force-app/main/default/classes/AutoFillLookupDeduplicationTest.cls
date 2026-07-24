@IsTest
private class AutoFillLookupDeduplicationTest {

    @IsTest
    static void manualUploadReusesNormalizedCarrierName() {
        FreightTM__Carrier__c existingCarrier =
            new FreightTM__Carrier__c(Name = 'ABC');
        insert existingCarrier;

        Schema.DescribeFieldResult carrierLookup =
            getCarrierLookupDescribe();

        Test.startTest();
        Id resolvedCarrierId =
            AutoFillService.findOrCreateLookup(
                carrierLookup,
                'A-B-C',
                'Carrier',
                new Map<String, Object>()
            );
        Test.stopTest();

        System.assertEquals(
            existingCarrier.Id,
            resolvedCarrierId,
            'Manual upload must reuse the existing normalized lookup.'
        );

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM FreightTM__Carrier__c
                WHERE Name = 'ABC'
            ],
            'Manual upload must not create a duplicate carrier.'
        );
    }

    @IsTest
    static void webhookReusesNormalizedCarrierName() {
        FreightTM__Carrier__c existingCarrier =
            new FreightTM__Carrier__c(Name = 'XYZ Logistics');
        insert existingCarrier;

        Schema.DescribeFieldResult carrierLookup =
            getCarrierLookupDescribe();

        Test.startTest();
        Id resolvedCarrierId =
            AutoFillService.findOrCreateLookup(
                carrierLookup,
                'XYZ   Logistics',
                'Carrier',
                new Map<String, Object>()
            );
        Test.stopTest();

        System.assertEquals(
            existingCarrier.Id,
            resolvedCarrierId,
            'Webhook processing must reuse the existing normalized lookup.'
        );

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM FreightTM__Carrier__c
                WHERE Name = 'XYZ Logistics'
            ],
            'Webhook processing must not create a duplicate carrier.'
        );
    }

    private static Schema.DescribeFieldResult getCarrierLookupDescribe() {
        Map<String, Schema.SObjectField> loadFields =
            FreightTM__Load__c.SObjectType.getDescribe().fields.getMap();

        Schema.SObjectField carrierField =
            loadFields.get('FreightTM__Carrier_Obj__c');

        System.assertNotEquals(
            null,
            carrierField,
            'The Load carrier lookup field must exist.'
        );

        Schema.DescribeFieldResult fieldDescribe =
            carrierField.getDescribe();

        System.assertEquals(
            Schema.DisplayType.Reference,
            fieldDescribe.getType(),
            'The configured carrier field must be a lookup.'
        );

        return fieldDescribe;
    }
}