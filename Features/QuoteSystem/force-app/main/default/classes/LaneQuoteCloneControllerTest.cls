@IsTest
private class LaneQuoteCloneControllerTest {
    @IsTest
    static void clonesParentAndAllChildTypes() {
        Account accountRec = LaneQuoteControllerTestDataFactory.createAccount(
            'Clone Controller Customer'
        );
        FreightTM__Lane_Quote__c sourceQuote =
            LaneQuoteControllerTestDataFactory.createLaneQuote(accountRec, 'clone');
        LaneQuoteControllerTestDataFactory.createQuoteChildren(sourceQuote.Id);
        LaneQuoteControllerTestDataFactory.setControllerPage(
            'LaneQuoteCloneControllerPage',
            sourceQuote.Id
        );

        LaneQuoteCloneController controller = new LaneQuoteCloneController();
        System.assertEquals(sourceQuote.Id, controller.sourceLaneQuoteId);
        System.assertNotEquals(
            null,
            controller.laneQuoteRecord,
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );

        if (controller.getHasLaneQuoteRecordTypes()) {
            if (controller.selectedRecordTypeId == null) {
                controller.selectedRecordTypeId = LaneQuoteControllerTestDataFactory.firstOptionId(
                    controller.getLaneQuoteRecordTypeOptions()
                );
            }
            System.assertNotEquals(null, controller.selectedRecordTypeId);
        }

        System.assertEquals(
            1,
            controller.quoteLines.size(),
            'The test Quote Line was not loaded. ' +
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );
        System.assertEquals(
            1,
            controller.quotePays.size(),
            'The test Quote Pay was not loaded. ' +
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );
        System.assertEquals(
            1,
            controller.quoteLegs.size(),
            'The test Quote Leg was not loaded. ' +
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );

        controller.cloneCount = 2;
        Test.startTest();
        PageReference redirectPage = controller.saveClones();
        Test.stopTest();

        System.assertNotEquals(
            null,
            redirectPage,
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );
        System.assertEquals('/' + sourceQuote.Id, redirectPage.getUrl());

        Set<Id> clonedQuoteIds = new Map<Id, FreightTM__Lane_Quote__c>([
            SELECT Id
            FROM FreightTM__Lane_Quote__c
            WHERE FreightTM__Customer__c = :accountRec.Id
            AND Id != :sourceQuote.Id
        ]).keySet();
        System.assertEquals(2, clonedQuoteIds.size());
        System.assertEquals(
            2,
            [SELECT COUNT() FROM FreightTM__Quote_Line__c
             WHERE FreightTM__Lane_Quote__c IN :clonedQuoteIds]
        );
        System.assertEquals(
            2,
            [SELECT COUNT() FROM FreightTM__Quote_Pay__c
             WHERE FreightTM__Lane_Quote__c IN :clonedQuoteIds]
        );
        System.assertEquals(
            2,
            [SELECT COUNT() FROM FreightTM__Quote_Leg__c
             WHERE FreightTM__Lane_Quote__c IN :clonedQuoteIds]
        );

        System.assertEquals('/' + sourceQuote.Id, controller.cancel().getUrl());
    }

    @IsTest
    static void oneCloneRedirectsToNewRecord() {
        Account accountRec = LaneQuoteControllerTestDataFactory.createAccount(
            'Single Clone Customer'
        );
        FreightTM__Lane_Quote__c sourceQuote =
            LaneQuoteControllerTestDataFactory.createLaneQuote(accountRec, 'single clone');
        LaneQuoteControllerTestDataFactory.setControllerPage(
            'LaneQuoteCloneControllerPage',
            sourceQuote.Id
        );

        LaneQuoteCloneController controller = new LaneQuoteCloneController();
        if (controller.getHasLaneQuoteRecordTypes() && controller.selectedRecordTypeId == null) {
            controller.selectedRecordTypeId = LaneQuoteControllerTestDataFactory.firstOptionId(
                controller.getLaneQuoteRecordTypeOptions()
            );
        }
        controller.cloneCount = 1;

        Test.startTest();
        PageReference result = controller.saveClones();
        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );
        Id clonedId = LaneQuoteControllerTestDataFactory.recordIdFrom(result);
        System.assertNotEquals(sourceQuote.Id, clonedId);
        System.assertEquals(
            accountRec.Id,
            [SELECT FreightTM__Customer__c
             FROM FreightTM__Lane_Quote__c
             WHERE Id = :clonedId].FreightTM__Customer__c
        );
    }

    @IsTest
    static void rowEditorsAndCloneCountValidation() {
        Account accountRec = LaneQuoteControllerTestDataFactory.createAccount(
            'Clone Editor Customer'
        );
        FreightTM__Lane_Quote__c sourceQuote =
            LaneQuoteControllerTestDataFactory.createLaneQuote(accountRec, 'clone rows');
        LaneQuoteControllerTestDataFactory.setControllerPage(
            'LaneQuoteCloneControllerPage',
            sourceQuote.Id
        );

        LaneQuoteCloneController controller = new LaneQuoteCloneController();
        if (controller.getHasLaneQuoteRecordTypes() && controller.selectedRecordTypeId == null) {
            controller.selectedRecordTypeId = LaneQuoteControllerTestDataFactory.firstOptionId(
                controller.getLaneQuoteRecordTypeOptions()
            );
        }

        controller.addQuoteLine();
        controller.addQuotePay();
        controller.addQuoteLeg();
        LaneQuoteControllerTestDataFactory.populateQuoteLine(controller.quoteLines[0].record);
        LaneQuoteControllerTestDataFactory.populateQuotePay(controller.quotePays[0].record);
        LaneQuoteControllerTestDataFactory.populateQuoteLeg(controller.quoteLegs[0].record);
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

        controller.cloneCount = 0;
        PageReference result = controller.saveClones();
        System.assertEquals(null, result);
        System.assert(
            LaneQuoteControllerTestDataFactory.messagesContain('between 1 and 25'),
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );
    }

    @IsTest
    static void invalidRecordTypeIsRejectedWhenRecordTypesExist() {
        Account accountRec = LaneQuoteControllerTestDataFactory.createAccount(
            'Clone Record Type Customer'
        );
        FreightTM__Lane_Quote__c sourceQuote =
            LaneQuoteControllerTestDataFactory.createLaneQuote(accountRec, 'invalid record type');
        LaneQuoteControllerTestDataFactory.setControllerPage(
            'LaneQuoteCloneControllerPage',
            sourceQuote.Id
        );

        LaneQuoteCloneController controller = new LaneQuoteCloneController();
        if (!controller.getHasLaneQuoteRecordTypes()) {
            System.assertEquals(null, controller.selectedRecordTypeId);
            return;
        }

        controller.selectedRecordTypeId = null;
        controller.cloneCount = 1;
        System.assertEquals(null, controller.saveClones());
        System.assert(
            LaneQuoteControllerTestDataFactory.messagesContain(
                'Select an available Lane Quote Record Type.'
            ),
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );
    }

    @IsTest
    static void missingRecordIdShowsFatalMessage() {
        LaneQuoteControllerTestDataFactory.setControllerPage(
            'LaneQuoteCloneControllerPage',
            null
        );
        LaneQuoteCloneController controller = new LaneQuoteCloneController();
        System.assertEquals(null, controller.sourceLaneQuoteId);
        System.assert(
            LaneQuoteControllerTestDataFactory.messagesContain(
                'A Lane Quote record ID is required.'
            ),
            LaneQuoteControllerTestDataFactory.allPageMessages()
        );
    }
}
