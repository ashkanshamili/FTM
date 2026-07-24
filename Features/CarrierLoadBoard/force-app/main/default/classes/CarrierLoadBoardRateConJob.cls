public without sharing class CarrierLoadBoardRateConJob
    implements Queueable, Database.AllowsCallouts {

    private Id loadId;
    private Id bidId;

    /*
     * This constructor matches:
     *
     * new CarrierLoadBoardRateConJob(
     *     loadRecord.Id,
     *     selectedBid.Id
     * )
     */
    public CarrierLoadBoardRateConJob(
        Id loadId,
        Id bidId
    ) {
        this.loadId = loadId;
        this.bidId = bidId;
    }

    public void execute(
        QueueableContext context
    ) {
        try {
            sendRateConfirmation();
        } catch (Exception errorValue) {
            System.debug(
                LoggingLevel.ERROR,
                'Rate Confirmation email failed. ' +
                'LoadId=' + loadId +
                ', BidId=' + bidId +
                ', ErrorType=' + errorValue.getTypeName() +
                ', Message=' + errorValue.getMessage() +
                ', Stack=' + errorValue.getStackTraceString()
            );
        }
    }

    private void sendRateConfirmation() {
        if (loadId == null || bidId == null) {
            throw new RateConJobException(
                'Load ID and Bid ID are required.'
            );
        }

        List<FreightTM__Bid__c> bidRecords = [
            SELECT
                Id,
                Name,
                FreightTM__Load__c,
                FreightTM__Carrier__c,
                FreightTM__Rate__c,
                Transition_Date__c,
                Transit_Time__c,
                FreightTM__Carrier__r.Name,
                FreightTM__Carrier__r.FreightTM__Primary_Contact__c,
                FreightTM__Carrier__r.FreightTM__Email__c
            FROM FreightTM__Bid__c
            WHERE Id = :bidId
                AND FreightTM__Load__c = :loadId
            LIMIT 1
        ];

        if (bidRecords.isEmpty()) {
            throw new RateConJobException(
                'The selected Bid could not be found.'
            );
        }

        FreightTM__Bid__c selectedBid =
            bidRecords[0];

        List<FreightTM__Load__c> loadRecords = [
            SELECT
                Id,
                Name,
                FreightTM__Pickup_Address__c,
                FreightTM__Pickup_City__c,
                FreightTM__Pickup_State__c,
                FreightTM__Pickup_Zip_Code__c,
                FreightTM__Pickup_Date__c,
                FreightTM__Delivery_Address__c,
                FreightTM__Delivery_City__c,
                FreightTM__Delivery_State__c,
                FreightTM__Delivery_Zip_Code__c,
                FreightTM__Delivery_Date__c,
                FreightTM__Carrier_Obj__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];

        if (loadRecords.isEmpty()) {
            throw new RateConJobException(
                'The selected Load could not be found.'
            );
        }

        FreightTM__Load__c loadRecord =
            loadRecords[0];

        if (
            loadRecord.FreightTM__Carrier_Obj__c !=
            selectedBid.FreightTM__Carrier__c
        ) {
            throw new RateConJobException(
                'The assigned carrier does not match the selected Bid.'
            );
        }

        if (selectedBid.FreightTM__Carrier__r == null) {
            throw new RateConJobException(
                'The carrier related to the selected Bid could not be found.'
            );
        }

        String carrierEmail =
            selectedBid
                .FreightTM__Carrier__r
                .FreightTM__Email__c;

        if (String.isBlank(carrierEmail)) {
            throw new RateConJobException(
                'The selected carrier does not have an email address.'
            );
        }

        Blob pdfBody =
            generateRateConPdf(
                loadRecord.Id,
                selectedBid.Id
            );

        Messaging.EmailFileAttachment attachment =
            new Messaging.EmailFileAttachment();

        attachment.setFileName(
            'Rate_Con#' +
            loadRecord.Name +
            '.pdf'
        );

        attachment.setContentType(
            'application/pdf'
        );

        attachment.setBody(pdfBody);

        String greetingName =
            selectedBid
                .FreightTM__Carrier__r
                .FreightTM__Primary_Contact__c;

        if (String.isBlank(greetingName)) {
            greetingName =
                selectedBid
                    .FreightTM__Carrier__r
                    .Name;
        }

        String pickupAddress =
            buildAddress(
                loadRecord.FreightTM__Pickup_Address__c,
                loadRecord.FreightTM__Pickup_City__c,
                loadRecord.FreightTM__Pickup_State__c,
                loadRecord.FreightTM__Pickup_Zip_Code__c
            );

        String deliveryAddress =
            buildAddress(
                loadRecord.FreightTM__Delivery_Address__c,
                loadRecord.FreightTM__Delivery_City__c,
                loadRecord.FreightTM__Delivery_State__c,
                loadRecord.FreightTM__Delivery_Zip_Code__c
            );

        String pickupDate =
            formatDate(
                loadRecord.FreightTM__Pickup_Date__c
            );

        String deliveryDate =
            formatDate(
                loadRecord.FreightTM__Delivery_Date__c
            );

        String htmlBody =
            buildHtmlBody(
                greetingName,
                loadRecord.Name,
                pickupAddress,
                pickupDate,
                deliveryAddress,
                deliveryDate
            );

        String plainTextBody =
            buildPlainTextBody(
                greetingName,
                loadRecord.Name,
                pickupAddress,
                pickupDate,
                deliveryAddress,
                deliveryDate
            );

        Messaging.SingleEmailMessage email =
            new Messaging.SingleEmailMessage();

        email.setToAddresses(
            new List<String>{
                carrierEmail
            }
        );

        email.setSubject(
            'Rate Confirmation - ' +
            loadRecord.Name
        );

        email.setHtmlBody(htmlBody);
        email.setPlainTextBody(plainTextBody);

        email.setFileAttachments(
            new List<Messaging.EmailFileAttachment>{
                attachment
            }
        );

        email.setSaveAsActivity(false);

        Messaging.SendEmailResult[] emailResults =
            Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{
                    email
                }
            );

        if (
            emailResults == null ||
            emailResults.isEmpty() ||
            !emailResults[0].isSuccess()
        ) {
            String emailError =
                'The email could not be sent.';

            if (
                emailResults != null &&
                !emailResults.isEmpty() &&
                emailResults[0].getErrors() != null &&
                !emailResults[0].getErrors().isEmpty()
            ) {
                emailError =
                    emailResults[0]
                        .getErrors()[0]
                        .getMessage();
            }

            throw new RateConJobException(
                emailError
            );
        }

        System.debug(
            LoggingLevel.INFO,
            'Rate Confirmation email sent. ' +
            'LoadId=' + loadId +
            ', BidId=' + bidId +
            ', Email=' + carrierEmail
        );
    }

    private static Blob generateRateConPdf(
        Id selectedLoadId,
        Id selectedBidId
    ) {
        if (Test.isRunningTest()) {
            return Blob.valueOf(
                'Rate Confirmation test PDF'
            );
        }

        /*
         * Use this form when the Visualforce page API name
         * is exactly RateCon.
         */
        PageReference rateConPage =
            new PageReference('/apex/RateCon');

        rateConPage
            .getParameters()
            .put(
                'id',
                String.valueOf(selectedLoadId)
            );

        rateConPage
            .getParameters()
            .put(
                'bidId',
                String.valueOf(selectedBidId)
            );

        return rateConPage.getContentAsPDF();
    }

    private static String buildHtmlBody(
        String greetingName,
        String loadName,
        String pickupAddress,
        String pickupDate,
        String deliveryAddress,
        String deliveryDate
    ) {
        return
            '<div style="' +
                'font-family:Arial,Helvetica,sans-serif;' +
                'font-size:16px;' +
                'line-height:1.55;' +
                'color:#202124;' +
            '">' +

                '<p>Dear ' +
                    escapeHtml(greetingName) +
                    ',</p>' +

                '<p>' +
                    'Please find attached the ' +
                    '<strong>Rate Confirmation</strong> ' +
                    'document regarding shipment # ' +
                    '<strong>' +
                        escapeHtml(loadName) +
                    '</strong>.' +
                '</p>' +

                '<p style="margin-top:26px;">' +
                    '<strong>Pickup:</strong> ' +
                    escapeHtml(pickupAddress) +
                    '<br/>' +
                    '<strong>Date:</strong> ' +
                    escapeHtml(pickupDate) +
                '</p>' +

                '<p style="margin-top:20px;">' +
                    '<strong>Delivery:</strong> ' +
                    escapeHtml(deliveryAddress) +
                    '<br/>' +
                    '<strong>Date:</strong> ' +
                    escapeHtml(deliveryDate) +
                '</p>' +

                '<p style="margin-top:30px;">' +
                    'Best Regards,<br/>' +
                    '<strong>Logistic Manager</strong>' +
                '</p>' +

            '</div>';
    }

    private static String buildPlainTextBody(
        String greetingName,
        String loadName,
        String pickupAddress,
        String pickupDate,
        String deliveryAddress,
        String deliveryDate
    ) {
        return
            'Dear ' + greetingName + ',\n\n' +

            'Please find attached the Rate Confirmation ' +
            'document regarding shipment # ' +
            loadName +
            '.\n\n' +

            'Pickup: ' + pickupAddress + '\n' +
            'Date: ' + pickupDate + '\n\n' +

            'Delivery: ' + deliveryAddress + '\n' +
            'Date: ' + deliveryDate + '\n\n' +

            'Best Regards,\n' +
            'Logistic Manager';
    }

    private static String buildAddress(
        String street,
        String city,
        String stateValue,
        String zipCode
    ) {
        List<String> parts =
            new List<String>();

        if (!String.isBlank(street)) {
            parts.add(street.trim());
        }

        String cityStateZip = '';

        if (!String.isBlank(city)) {
            cityStateZip = city.trim();
        }

        if (!String.isBlank(stateValue)) {
            cityStateZip +=
                String.isBlank(cityStateZip)
                    ? stateValue.trim()
                    : ', ' + stateValue.trim();
        }

        if (!String.isBlank(zipCode)) {
            cityStateZip +=
                String.isBlank(cityStateZip)
                    ? zipCode.trim()
                    : ' ' + zipCode.trim();
        }

        if (!String.isBlank(cityStateZip)) {
            parts.add(cityStateZip);
        }

        return parts.isEmpty()
            ? 'Not provided'
            : String.join(parts, ', ');
    }

    private static String formatDate(
        Date dateValue
    ) {
        if (dateValue == null) {
            return 'Not provided';
        }

        Datetime dateTimeValue =
            Datetime.newInstance(
                dateValue,
                Time.newInstance(0, 0, 0, 0)
            );

        return dateTimeValue.format(
            'MMMM d, yyyy'
        );
    }

    private static String escapeHtml(
        String inputValue
    ) {
        if (String.isBlank(inputValue)) {
            return '';
        }

        String escapedValue =
            inputValue.replace(
                '&',
                '&amp;'
            );

        escapedValue =
            escapedValue.replace(
                '<',
                '&lt;'
            );

        escapedValue =
            escapedValue.replace(
                '>',
                '&gt;'
            );

        escapedValue =
            escapedValue.replace(
                '"',
                '&quot;'
            );

        return escapedValue;
    }

    public class RateConJobException
        extends Exception {
    }
}