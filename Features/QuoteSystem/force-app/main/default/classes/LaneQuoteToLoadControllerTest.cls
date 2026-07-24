@IsTest
private class LaneQuoteToLoadControllerTest {
    @IsTest
    static void convertsExistingQuoteAndAllChildren() {
        Account accountRec = LaneQuoteControllerTestDataFactory.createAccount(
            'Convert Existing Quote Customer'
        );
        FreightTM__Lane_Quote__c sourceQuote =
            LaneQuoteControllerTestDataFactory.createLaneQuote(accountRec, 'convert existing');
        LaneQuoteControllerTestDataFactory.createQuoteChildren(sourceQuote.Id);
        LaneQuoteControllerTestDataFactory.setControllerPage(
            'LaneQuoteToLoadControllerPage',
            sourceQuote.Id
        );
        LaneQuoteControllerTestDataFactory.registerCalloutMock();

        LaneQuoteToLoadController controller = new LaneQuoteToLoadController();
        System.assertEquals(sourceQuote.Id, controller.sourceLaneQuoteId);
        System.assertNotEquals(
            null,
            controller.laneQuoteRecord,
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );
        System.assertEquals(sourceQuote.Id, (Id)controller.laneQuoteRecord.get('Id'));

        if (controller.selectedLoadRecordTypeId == null) {
            controller.selectedLoadRecordTypeId = LaneQuoteControllerTestDataFactory.firstOptionId(
                controller.getLoadRecordTypeOptions()
            );
        }
        System.assertNotEquals(
            null,
            controller.selectedLoadRecordTypeId,
            'A non-Master Load Record Type is required for conversion.'
        );
        System.assertEquals(1, controller.quoteLines.size());
        System.assertEquals(1, controller.quotePays.size());
        System.assertEquals(1, controller.quoteLegs.size());

        Test.startTest();
        PageReference loadPage = controller.convertToLoad();
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
        System.assertEquals(sourceQuote.Id, createdLoad.FreightTM__Lane_Quote__c);
        System.assertEquals(accountRec.Id, createdLoad.FreightTM__Customer__c);
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
        System.assertEquals('/' + sourceQuote.Id, controller.cancel().getUrl());
    }

    @IsTest
    static void convertsQuoteWithoutChildren() {
        Account accountRec = LaneQuoteControllerTestDataFactory.createAccount(
            'Convert Empty Quote Customer'
        );
        FreightTM__Lane_Quote__c sourceQuote =
            LaneQuoteControllerTestDataFactory.createLaneQuote(accountRec, 'no children');
        LaneQuoteControllerTestDataFactory.setControllerPage(
            'LaneQuoteToLoadControllerPage',
            sourceQuote.Id
        );
        LaneQuoteControllerTestDataFactory.registerCalloutMock();

        LaneQuoteToLoadController controller = new LaneQuoteToLoadController();
        if (controller.selectedLoadRecordTypeId == null) {
            controller.selectedLoadRecordTypeId = LaneQuoteControllerTestDataFactory.firstOptionId(
                controller.getLoadRecordTypeOptions()
            );
        }
        System.assertEquals(0, controller.quoteLines.size());
        System.assertEquals(0, controller.quotePays.size());
        System.assertEquals(0, controller.quoteLegs.size());

        Test.startTest();
        PageReference result = controller.convertToLoad();
        Test.stopTest();
        System.assertNotEquals(
            null,
            result,
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );
    }

    @IsTest
    static void rowEditorsAndInvalidLoadRecordType() {
        Account accountRec = LaneQuoteControllerTestDataFactory.createAccount(
            'Convert Editor Customer'
        );
        FreightTM__Lane_Quote__c sourceQuote =
            LaneQuoteControllerTestDataFactory.createLaneQuote(accountRec, 'convert rows');
        LaneQuoteControllerTestDataFactory.setControllerPage(
            'LaneQuoteToLoadControllerPage',
            sourceQuote.Id
        );

        LaneQuoteToLoadController controller = new LaneQuoteToLoadController();
        controller.addQuoteLine();
        controller.addQuotePay();
        controller.addQuoteLeg();
        LaneQuoteControllerTestDataFactory.populateQuoteLine(controller.quoteLines[0].record);
        LaneQuoteControllerTestDataFactory.populateQuotePay(controller.quotePays[0].record);
        LaneQuoteControllerTestDataFactory.populateQuoteLeg(controller.quoteLegs[0].record);

        controller.rowIndex = 0;
        controller.removeQuoteLine();
        controller.removeQuotePay();
        controller.removeQuoteLeg();
        System.assertEquals(0, controller.quoteLines.size());
        System.assertEquals(0, controller.quotePays.size());
        System.assertEquals(0, controller.quoteLegs.size());

        controller.selectedLoadRecordTypeId = null;
        PageReference result = controller.convertToLoad();
        System.assertEquals(null, result);
        System.assert(
            LaneQuoteControllerTestDataFactory.messagesContain(
                'Select an available Load Record Type.'
            ),
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );
    }

    @IsTest
    static void missingRecordIdShowsFatalMessage() {
        LaneQuoteControllerTestDataFactory.setControllerPage(
            'LaneQuoteToLoadControllerPage',
            null
        );
        LaneQuoteToLoadController controller = new LaneQuoteToLoadController();
        System.assertEquals(null, controller.sourceLaneQuoteId);
        System.assert(
            LaneQuoteControllerTestDataFactory.messagesContain(
                'A Lane Quote record ID is required.'
            ),
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );
    }
}
