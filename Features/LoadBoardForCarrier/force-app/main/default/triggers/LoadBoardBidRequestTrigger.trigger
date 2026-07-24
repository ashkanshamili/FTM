trigger LoadBoardBidRequestTrigger on Load_Board_Bid_Request__e (after insert) {

    LoadBoardBidRequestHandler.handleAfterInsert(
        Trigger.new
    );
}