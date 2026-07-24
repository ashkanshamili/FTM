@IsTest
private class NewLaneQuoteToLoadControllerTest {
    @IsTest
    static void createsNewQuoteLoadAndAllChildren() {
        Account accountRec = LaneQuoteControllerTestDataFactory.createAccount(
            'New Quote Conversion Customer'
        );
        LaneQuoteControllerTestDataFactory.setControllerPage(
            'NewLaneQuoteToLoadControllerPage',
            null
        );
        LaneQuoteControllerTestDataFactory.registerCalloutMock();

        NewLaneQuoteToLoadController controller = new NewLaneQuoteToLoadController();
        System.assertNotEquals(
            null,
            controller.laneQuoteRecord,
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );
        setValidRecordTypes(controller);
        LaneQuoteControllerTestDataFactory.populateLaneQuoteTemplate(
            controller.laneQuoteRecord,
            accountRec.Id
        );
        controller.addQuoteLine();
        controller.addQuotePay();
        controller.addQuoteLeg();
        LaneQuoteControllerTestDataFactory.populateQuoteLine(controller.quoteLines[0].record);
        LaneQuoteControllerTestDataFactory.populateQuotePay(controller.quotePays[0].record);
        LaneQuoteControllerTestDataFactory.populateQuoteLeg(controller.quoteLegs[0].record);

        Test.startTest();
        PageReference loadPage = controller.createAndConvert();
        Test.stopTest();

        System.assertNotEquals(
            null,
            loadPage,
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );
        Id loadId = LaneQuoteControllerTestDataFactory.recordIdFrom(loadPage);
        FreightTM__Load__c createdLoad = [
            SELECT Id, FreightTM__Lane_Quote__c, FreightTM__Customer__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
        ];
        System.assertNotEquals(null, createdLoad.FreightTM__Lane_Quote__c);
        System.assertEquals(accountRec.Id, createdLoad.FreightTM__Customer__c);

        FreightTM__Lane_Quote__c createdQuote = [
            SELECT Id, FreightTM__Customer__c
            FROM FreightTM__Lane_Quote__c
            WHERE Id = :createdLoad.FreightTM__Lane_Quote__c
        ];
        System.assertEquals(accountRec.Id, createdQuote.FreightTM__Customer__c);
        System.assertEquals(
            1,
            LaneQuoteControllerTestDataFactory.countRecords(
                'FreightTM__Quote_Line__c',
                'FreightTM__Lane_Quote__c = \'' +
                String.escapeSingleQuotes(String.valueOf(createdQuote.Id)) + '\''
            )
        );
        System.assertEquals(
            1,
            LaneQuoteControllerTestDataFactory.countRecords(
                'FreightTM__Quote_Pay__c',
                'FreightTM__Lane_Quote__c = \'' +
                String.escapeSingleQuotes(String.valueOf(createdQuote.Id)) + '\''
            )
        );
        System.assertEquals(
            1,
            LaneQuoteControllerTestDataFactory.countRecords(
                'FreightTM__Quote_Leg__c',
                'FreightTM__Lane_Quote__c = \'' +
                String.escapeSingleQuotes(String.valueOf(createdQuote.Id)) + '\''
            )
        );
        System.assertEquals(
            1,
            LaneQuoteControllerTestDataFactory.countRecords(
                'FreightTM__Line_Item__c',
                'FreightTM__Load__c = \'' +
                String.escapeSingleQuotes(String.valueOf(loadId)) + '\''
            )
        );
        System.assertEquals(
            1,
            LaneQuoteControllerTestDataFactory.countRecords(
                'FreightTM__Pay_Item__c',
                'FreightTM__Load__c = \'' +
                String.escapeSingleQuotes(String.valueOf(loadId)) + '\''
            )
        );
        System.assertEquals(
            1,
            LaneQuoteControllerTestDataFactory.countRecords(
                'FreightTM__Leg__c',
                'FreightTM__Load__c = \'' +
                String.escapeSingleQuotes(String.valueOf(loadId)) + '\''
            )
        );
    }

    @IsTest
    static void createsQuoteAndLoadWithoutChildren() {
        Account accountRec = LaneQuoteControllerTestDataFactory.createAccount(
            'New Empty Quote Customer'
        );
        LaneQuoteControllerTestDataFactory.setControllerPage(
            'NewLaneQuoteToLoadControllerPage',
            null
        );
        LaneQuoteControllerTestDataFactory.registerCalloutMock();

        NewLaneQuoteToLoadController controller = new NewLaneQuoteToLoadController();
        setValidRecordTypes(controller);
        LaneQuoteControllerTestDataFactory.populateLaneQuoteTemplate(
            controller.laneQuoteRecord,
            accountRec.Id
        );

        Test.startTest();
        PageReference result = controller.createAndConvert();
        Test.stopTest();
        System.assertNotEquals(
            null,
            result,
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );
    }

    @IsTest
    static void rowEditorsAreCovered() {
        LaneQuoteControllerTestDataFactory.setControllerPage(
            'NewLaneQuoteToLoadControllerPage',
            null
        );
        NewLaneQuoteToLoadController controller = new NewLaneQuoteToLoadController();
        controller.addQuoteLine();
        controller.addQuotePay();
        controller.addQuoteLeg();
        System.assertEquals(1, controller.quoteLines.size());
        System.assertEquals(1, controller.quotePays.size());
        System.assertEquals(1, controller.quoteLegs.size());

        controller.rowIndex = 0;
        controller.removeQuoteLine();
        controller.removeQuotePay();
        controller.removeQuoteLeg();
        System.assertEquals(0, controller.quoteLines.size());
        System.assertEquals(0, controller.quotePays.size());
        System.assertEquals(0, controller.quoteLegs.size());
    }

    @IsTest
    static void invalidLaneQuoteRecordTypeIsRejectedWhenSupported() {
        LaneQuoteControllerTestDataFactory.setControllerPage(
            'NewLaneQuoteToLoadControllerPage',
            null
        );
        NewLaneQuoteToLoadController controller = new NewLaneQuoteToLoadController();
        if (!controller.getHasLaneQuoteRecordTypes()) {
            System.assertEquals(null, controller.selectedLaneQuoteRecordTypeId);
            return;
        }

        controller.selectedLaneQuoteRecordTypeId = null;
        if (controller.selectedLoadRecordTypeId == null) {
            controller.selectedLoadRecordTypeId = LaneQuoteControllerTestDataFactory.firstOptionId(
                controller.getLoadRecordTypeOptions()
            );
        }
        System.assertEquals(null, controller.createAndConvert());
        System.assert(
            LaneQuoteControllerTestDataFactory.messagesContain(
                'Select an available Lane Quote Record Type.'
            ),
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );
    }

    @IsTest
    static void invalidLoadRecordTypeIsRejected() {
        Account accountRec = LaneQuoteControllerTestDataFactory.createAccount(
            'New Quote Validation Customer'
        );
        LaneQuoteControllerTestDataFactory.setControllerPage(
            'NewLaneQuoteToLoadControllerPage',
            null
        );
        NewLaneQuoteToLoadController controller = new NewLaneQuoteToLoadController();
        LaneQuoteControllerTestDataFactory.populateLaneQuoteTemplate(
            controller.laneQuoteRecord,
            accountRec.Id
        );
        if (controller.getHasLaneQuoteRecordTypes() &&
            controller.selectedLaneQuoteRecordTypeId == null) {
            controller.selectedLaneQuoteRecordTypeId =
                LaneQuoteControllerTestDataFactory.firstOptionId(
                    controller.getLaneQuoteRecordTypeOptions()
                );
        }
        controller.selectedLoadRecordTypeId = null;

        System.assertEquals(null, controller.createAndConvert());
        System.assert(
            LaneQuoteControllerTestDataFactory.messagesContain(
                'Select an available Load Record Type.'
            ),
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );
    }

    private static void setValidRecordTypes(
        NewLaneQuoteToLoadController controller
    ) {
        if (controller.getHasLaneQuoteRecordTypes() &&
            controller.selectedLaneQuoteRecordTypeId == null) {
            controller.selectedLaneQuoteRecordTypeId =
                LaneQuoteControllerTestDataFactory.firstOptionId(
                    controller.getLaneQuoteRecordTypeOptions()
                );
        }
        if (controller.selectedLoadRecordTypeId == null) {
            controller.selectedLoadRecordTypeId =
                LaneQuoteControllerTestDataFactory.firstOptionId(
                    controller.getLoadRecordTypeOptions()
                );
        }
        System.assertNotEquals(
            null,
            controller.selectedLoadRecordTypeId,
            'A non-Master Load Record Type is required for conversion.'
        );
    }
}
