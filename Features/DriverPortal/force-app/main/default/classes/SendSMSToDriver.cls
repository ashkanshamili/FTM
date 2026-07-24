public without sharing class SendSMSToDriver { 
    @TestVisible
    private static final Map<String, String> carrierEmailToSMSMap =
        new Map<String, String>{
            'AT&T' => 'txt.att.net',
                'Verizon' => 'vtext.com',
                'T-Mobile' => 'tmomail.net',
                'Sprint' => 'messaging.sprintpcs.com',
                'MetroPCS' => 'mymetropcs.com',
                'Boost Mobile' => 'tmomail.net',
                'Cricket Wireless' => 'sms.cricketwireless.net',
                'U.S. Cellular' => 'email.uscc.net',
                'TracFone' => 'mmst5.tracfone.com',
                'Virgin Mobile' => 'vmobl.com'
                };
                    
                    public static void sendSMS(String phoneNumber, String carrier, String message) {
                        System.debug(
                            '▶ sendSMS called with: phoneNumber=' +
                            phoneNumber +
                            ', carrier=' +
                            carrier +
                            ', message=' +
                            message
                        );
                        
                        if (String.isBlank(phoneNumber)) {
                            System.debug('✗ sendSMS skipped: missing phone number.');
                            return;
                        }
                        
                        String cleanPhone = phoneNumber.replaceAll('[^0-9]', '');
                        
                        if (String.isBlank(cleanPhone)) {
                            System.debug('✗ sendSMS skipped: invalid phone number.');
                            return;
                        }
                        
                        if (
                            String.isNotBlank(carrier) &&
                            carrierEmailToSMSMap.containsKey(carrier)
                        ) {
                            sendEmailToSmsGateway(cleanPhone, carrier, message);
                            return;
                        }
                        
                        System.debug('No valid carrier provided. Sending to all SMS gateways.');
                        
                        for (String carrierName : carrierEmailToSMSMap.keySet()) {
                            sendEmailToSmsGateway(cleanPhone, carrierName, message);
                        }
                    }
    
    @InvocableMethod
    public static void sendSMSToAllCarriers(List<EmailWrapper> emailDataList) {
        if (emailDataList == null || emailDataList.isEmpty()) {
            return;
        }
        
        for (EmailWrapper emailData : emailDataList) {
            String phoneNumber = emailData.phoneNumber;
            String message = emailData.message;
            String selectedCarrier = emailData.carrier;
            
            if (
                String.isNotBlank(selectedCarrier) &&
                carrierEmailToSMSMap.containsKey(selectedCarrier)
            ) {
                sendSMS(phoneNumber, selectedCarrier, message);
            } else {
                for (String carrier : carrierEmailToSMSMap.keySet()) {
                    sendSMS(phoneNumber, carrier, message);
                }
            }
        }
    }
    
    public class EmailWrapper {
        @InvocableVariable
        public String phoneNumber;
        
        @InvocableVariable
        public String message;
        
        @InvocableVariable
        public String carrier;
    }
    
    private static void sendEmailToSmsGateway(
        String cleanPhone,
        String carrier,
        String message
    ) {
        String email = cleanPhone + '@' + carrierEmailToSMSMap.get(carrier);
        
        if (Test.isRunningTest()) {
            System.debug(
                '✓ SMS email skipped during test. Would send to: ' +
                email +
                ', message=' +
                message
            );
            return;
        }
        
        Messaging.SingleEmailMessage emailMessage = new Messaging.SingleEmailMessage();
        
        emailMessage.setToAddresses(new String[] { email });
        //emailMessage.setSubject('From Holloway Logistics:');
        emailMessage.setSubject('');
        emailMessage.setPlainTextBody(message);
        
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { emailMessage });
        
        System.debug('✓ SMS email sent to: ' + email);
    }
}