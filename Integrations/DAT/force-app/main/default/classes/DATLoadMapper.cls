public with sharing class DATLoadMapper {
    public static Map<String, Object> buildPostPayload(FreightTM__Load__c loadRecord) {
        validate(loadRecord);

        Map<String, Object> payload = new Map<String, Object>();
        payload.put('freight', buildFreight(loadRecord));
        payload.put('lane', buildLane(loadRecord));

        Map<String, Boolean> audience = new Map<String, Boolean>{ 'loadBoard' => true };
        Map<String, Object> exposure = buildExposure(loadRecord);
        exposure.put('audience', audience);
        payload.put('exposure', exposure);
        payload.put('isTrackingRequired', true);

        Map<String, Object> posterInfo = buildPosterInfo();
        if (!posterInfo.isEmpty()) {
            payload.put('posterInfo', posterInfo);
        }
        return payload;
    }

    public static Map<String, Object> buildUpdatePayload(FreightTM__Load__c loadRecord) {
        validate(loadRecord);
        return new Map<String, Object>{
            'freight' => buildFreight(loadRecord),
            'exposure' => buildExposure(loadRecord)
        };
    }

    @TestVisible
    private static void validate(FreightTM__Load__c loadRecord) {
        List<String> errors = new List<String>();
        if (loadRecord == null) {
            throw new DATIntegrationException('Load data is unavailable.');
        }

        addMissing(errors, 'Pickup City', loadRecord.FreightTM__Pickup_City__c);
        addMissing(errors, 'Pickup State', loadRecord.FreightTM__Pickup_State__c);
        addMissing(errors, 'Pickup ZIP Code', loadRecord.FreightTM__Pickup_Zip_Code__c);
        addMissing(errors, 'Delivery City', loadRecord.FreightTM__Delivery_City__c);
        addMissing(errors, 'Delivery State', loadRecord.FreightTM__Delivery_State__c);
        addMissing(errors, 'Delivery ZIP Code', loadRecord.FreightTM__Delivery_Zip_Code__c);

        if (loadRecord.FreightTM__Pickup_Date__c == null) {
            errors.add('Pickup Date');
        }
        if (loadRecord.FreightTM__Delivery_Date__c == null) {
            errors.add('Delivery Date');
        }
        if (loadRecord.FreightTM__Weight__c == null || loadRecord.FreightTM__Weight__c <= 0) {
            errors.add('Weight');
        }

        DATEquipmentMapper.toDatCode(loadRecord.FreightTM__Required_Trailer__c);

        if (loadRecord.FreightTM__Pickup_Date__c != null
            && loadRecord.FreightTM__Pickup_Date__c < Date.today()) {
            throw new DATIntegrationException('Pickup Date cannot be in the past.');
        }

        if (loadRecord.FreightTM__Pickup_Date__c != null
            && loadRecord.FreightTM__Delivery_Date__c != null) {
            if (loadRecord.FreightTM__Delivery_Date__c < loadRecord.FreightTM__Pickup_Date__c) {
                throw new DATIntegrationException('Delivery Date cannot be earlier than Pickup Date.');
            }
            if (loadRecord.FreightTM__Delivery_Date__c > Date.today().addMonths(6)) {
                throw new DATIntegrationException('Delivery Date must be within six months.');
            }
        }

        if (!errors.isEmpty()) {
            throw new DATIntegrationException('Complete these Load fields before sending to DAT: ' + String.join(errors, ', ') + '.');
        }
    }

    private static Map<String, Object> buildFreight(FreightTM__Load__c loadRecord) {
        Map<String, Object> freight = new Map<String, Object>{
            'equipmentType' => DATEquipmentMapper.toDatCode(loadRecord.FreightTM__Required_Trailer__c),
            'weightPounds' => loadRecord.FreightTM__Weight__c
        };

        String fullPartial = mapFullPartial(loadRecord.FreightTM__Size__c);
        if (fullPartial != null) {
            freight.put('fullPartial', fullPartial);
        }
        if (loadRecord.Total_Linear_Feet__c != null && loadRecord.Total_Linear_Feet__c > 0) {
            freight.put('lengthFeet', loadRecord.Total_Linear_Feet__c);
        }
        if (!String.isBlank(loadRecord.FreightTM__Remarks__c)) {
            freight.put(
                'comments',
                new List<Object>{
                    new Map<String, Object>{ 'comment' => loadRecord.FreightTM__Remarks__c }
                }
            );
        }
        return freight;
    }

    private static Map<String, Object> buildLane(FreightTM__Load__c loadRecord) {
        return new Map<String, Object>{
            'origin' => new Map<String, Object>{
                'city' => loadRecord.FreightTM__Pickup_City__c,
                'stateProv' => loadRecord.FreightTM__Pickup_State__c,
                'postalCode' => loadRecord.FreightTM__Pickup_Zip_Code__c
            },
            'destination' => new Map<String, Object>{
                'city' => loadRecord.FreightTM__Delivery_City__c,
                'stateProv' => loadRecord.FreightTM__Delivery_State__c,
                'postalCode' => loadRecord.FreightTM__Delivery_Zip_Code__c
            }
        };
    }

    private static Map<String, Object> buildExposure(FreightTM__Load__c loadRecord) {
        Datetime earliest = Datetime.newInstance(
            loadRecord.FreightTM__Pickup_Date__c,
            Time.newInstance(0, 0, 0, 0)
        );
        Datetime latest = Datetime.newInstance(
            loadRecord.FreightTM__Delivery_Date__c,
            Time.newInstance(23, 59, 59, 999)
        );
        return new Map<String, Object>{
            'startWhen' => Datetime.now(),
            'earliestAvailabilityWhen' => earliest,
            'latestAvailabilityWhen' => latest,
            'endWhen' => latest
        };
    }

    private static Map<String, Object> buildPosterInfo() {
        User currentUser = [
            SELECT Phone, Email
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        List<Object> methods = new List<Object>();
        if (!String.isBlank(currentUser.Phone)) {
            methods.add(new Map<String, Object>{
                'method' => 'PRIMARY_PHONE',
                'value' => 'tel:' + currentUser.Phone
            });
        }
        if (!String.isBlank(currentUser.Email)) {
            methods.add(new Map<String, Object>{
                'method' => 'EMAIL',
                'value' => currentUser.Email
            });
        }
        if (methods.isEmpty()) {
            return new Map<String, Object>();
        }
        return new Map<String, Object>{ 'contactMethods' => methods };
    }

    private static String mapFullPartial(String serviceLevel) {
        if (serviceLevel == 'LTL' || serviceLevel == 'STL') {
            return 'PARTIAL';
        }
        if (serviceLevel == 'TL' || serviceLevel == 'FTL' || serviceLevel == 'Expedited') {
            return 'FULL';
        }
        return null;
    }

    private static void addMissing(List<String> errors, String label, String value) {
        if (String.isBlank(value)) {
            errors.add(label);
        }
    }
}
