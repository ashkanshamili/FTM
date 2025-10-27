global virtual with sharing class SageInvoice {
    public  id invoiceId {get;set;}
    public FreightTM__Storage__c invoice { get; set; }
    public List<FreightTM__Storage__c> invoices { get; set; }
    
    public SageInvoice(ApexPages.StandardController controller) {
        invoiceId = ApexPages.currentPage().getParameters().get('id');
        system.debug(invoiceId);
    }
    
    public static void CustomerCreate(id invoiceId) {
        String senderid = 'Your-senderid';
        String senderpassword = 'Your-Password';
        String userid = 'Your-userid';
        String companyid = 'Your-companyid';
        String passwordid = 'Your-passwordid';
        FreightTM__Storage__c invoice = [SELECT id, Name, Customer__r.Name, Customer__r.Customer_Id__c, Customer__r.Phone, Customer__r.Email__c, 
                                         Customer__r.BillingStreet, Customer__r.BillingCity, Customer__r.BillingState, Customer__r.BillingPostalCode, 
                                         Customer__r.BillingCountry, Customer__r.ShippingStreet, Customer__r.ShippingCity, Customer__r.ShippingState,
                                         Customer__r.ShippingPostalCode, Customer__r.SAGECustomerID__c, Customer__r.Sage_Record_Number__c,
                                         Customer__r.Primary_Contact__c, Sage_Customer_RecordNo__c, Customer__r.Status__c 
                                         FROM FreightTM__Storage__c WHERE Id = :invoiceId LIMIT 1]; 
        
        String customerID = invoice.Customer__r.Customer_Id__c;
        String customerNAME = invoice.Customer__r.Name;
        String PHONE = invoice.Customer__r.Phone;
        String EMAIL = invoice.Customer__r.Email__c;
        String ADDRESS = invoice.Customer__r.BillingStreet;
        String CITY = invoice.Customer__r.BillingCity;
        String STATE = invoice.Customer__r.BillingState;
        String ZIP = invoice.Customer__r.BillingPostalCode;
        String COUNTRY = invoice.Customer__r.BillingCountry;
        String CONTACTNAME = invoice.Customer__r.Primary_Contact__c;
        System.debug(EMAIL);
        String xmlCostumerRequest = '<?xml version="1.0" encoding="UTF-8"?>' +
            '<request>' +
            '<control><senderid>Your-senderid</senderid><password>Your-Password</password><controlid>test</controlid><uniqueid>false</uniqueid><dtdversion>3.0</dtdversion></control>' +
            '<operation>' +
            '<authentication><login><userid>Your-userid</userid><companyid>Your-companyid</companyid><password>Your-passwordid</password></login></authentication>' +
            '<content>' +
            '<function controlid="3G2DFC86-9899-4283-360X-C789142D2801">' +
            '<create>' +
            '<CUSTOMER>' +
            '<CUSTOMERID>' + customerID + '</CUSTOMERID>' +
            '<NAME>' + customerNAME + '</NAME>' +
            '<DISPLAYCONTACT>' +
            '<PHONE1>' + PHONE + '</PHONE1>' +
            //'<EMAIL1>' + EMAIL + '</EMAIL1>' +
            '<MAILADDRESS>' +
            '<ADDRESS2>' + ADDRESS + '</ADDRESS2>' +
            '<CITY>' + CITY + '</CITY>' +
            '<STATE>' + STATE + '</STATE>' +
            '<ZIP>' + ZIP + '</ZIP>' +
            //'<COUNTRY>' + COUNTRY + '</COUNTRY>' +
            '</MAILADDRESS>' +
            '</DISPLAYCONTACT>' +
            //'<CONTACTINFO>' +
            //'<CONTACTNAME>' + CONTACTNAME + '</CONTACTNAME>' +
            //'</CONTACTINFO>' +
            '</CUSTOMER></create></function></content></operation></request>';
        System.debug(xmlCostumerRequest);
        
        HttpRequest Costumerrequest = new HttpRequest();
        Costumerrequest.setEndpoint('https://api.intacct.com/ia/xml/xmlgw.phtml');
        Costumerrequest.setMethod('POST');
        Costumerrequest.setHeader('Content-Type', 'application/xml');
        Costumerrequest.setHeader('Accept', '*/*');
        
        Costumerrequest.setBody(xmlCostumerRequest);
        
        Http http = new Http();
        HttpResponse Costresponse = http.send(Costumerrequest);
        system.debug(Costresponse.getStatus());
        system.debug(Costresponse.getBody());
        system.debug(Costresponse.getStatusCode());
        System.debug(Costumerrequest);
        
        // Check response status
        
        if (Costresponse.getStatusCode() == 200) {
            // Parse the response XML
            Dom.Document doc = new Dom.Document();
            doc.load(Costresponse.getBody());
            Dom.XmlNode resultNode = doc.getRootElement().getChildElement('operation', null).getChildElement('result', null);
            
            // Check if the response status is failure
            if (resultNode.getChildElement('status', null).getText().equalsIgnoreCase('failure')) {
                // Get the error message
                String errorMessage = '';
                for (Dom.XmlNode errorNode : resultNode.getChildElement('errormessage', null).getChildElements()) {
                    errorMessage += errorNode.getChildElement('description2', null).getText() + '. ';
                }
                //errorMessage += 'This has been added for test'; 
                // Display error message in VFP
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, errorMessage));
            } else {
                // Retrieve the values from the response
                String sageCustomerRecordNo = resultNode.getChildElement('data', null).getChildElement('customer', null).getChildElement('RECORDNO', null).getText();
                String newCustomerId = resultNode.getChildElement('data', null).getChildElement('customer', null).getChildElement('CUSTOMERID', null).getText();
                
                // Query the Account record based on some criteria to get the record you want to update
                Account[] accountsToUpdate = [SELECT Id, Sage_Customer_ID__c, Status__c, Sage_Customer_RecordNo__c 
                                              FROM Account WHERE Customer_Id__c = :invoice.Customer__r.Customer_Id__c LIMIT 1];
                
                // Check if there are any matching Account records
                if (accountsToUpdate.size() > 0) {
                    // Retrieve the Account record
                    Account updatedCustomer = accountsToUpdate[0];
                    
                    // Update the Account fields with the values from the response
                    updatedCustomer.Sage_Customer_ID__c = newCustomerId;
                    updatedCustomer.Sage_Customer_RecordNo__c = sageCustomerRecordNo;
                    updatedCustomer.Status__c = 'Sent';
                    
                    // Perform the update
                    try {
                        update updatedCustomer;
                        //update updatedInvoice;
                        System.debug('Invoice fields updated successfully.');
                        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.INFO, 'The customer with ' + sageCustomerRecordNo + ' record number has been created in Sage successfully.'));
                    } catch (Exception e) {
                        System.debug('Error updating invoice fields: ' + e.getMessage());
                        // Handle the error appropriately
                    }
                }
            }} else {
                // Error in creating customer
                System.debug('There was an Error, Please contact the administrator.');
                
                // Display error message in VFP
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'There was an Error, Please contact the administrator.'));
            }
    }
    
    public PageReference CreateCustomer() {  
        try {
            CustomerCreate(invoiceId);
        } catch (Exception ex) {
            // Handle the exception or log it if needed
            System.debug('Error in Sage: ' + ex.getMessage());
        }
        
        system.debug('id: ' + invoiceId);
        return null;
    }
    
    public static void InvoiceCreate(Id invoiceId) {

        String senderid = 'Your-senderid';
        String senderpassword = 'Your-Password';
        String userid = 'Your-userid';
        String companyid = 'Your-companyid';
        String passwordid = 'Your-passwordid';
        FreightTM__Storage__c invoice = [SELECT Id, Name, Customer__c, State__c, Terms__c, Customer_Name__c, 
                                         Customer__r.Name, Customer__r.Customer_Id__c, Customer__r.Phone, Customer__r.Email__c, 
                                         Customer__r.BillingStreet, Customer__r.BillingCity, Customer__r.BillingState, Customer__r.BillingPostalCode, 
                                         Customer__r.BillingCountry, Customer__r.ShippingStreet, Customer__r.ShippingCity, Customer__r.ShippingState,
                                         Customer__r.ShippingPostalCode, Customer__r.SAGECustomerID__c, Customer__r.Sage_Record_Number__c,
                                         Customer__r.Primary_Contact__c, Sage_Customer_RecordNo__c, Date__c, Sage_Customer_ID__c, 
                                         Job_Ref_Number__c, FreightTM__Load__r.Name, FreightTM__Load__r.Account__r.Customer_Id__c
                                         FROM FreightTM__Storage__c WHERE Id = :invoiceId LIMIT 1]; 
        
        // Query only the line items related to the specific invoice
        List<FreightTM__Storage_Billing__c> lineItems = [SELECT Id, Name, Description__c, Unit_Price__c, Type__c, Item_Name__c, Sage_Item_Type__c, Location_IDs__c,
                                                         Sage_Item_Record_Number__c, Number_of_Units__c, Job__c, FreightTM__Storage__c, Amount__c, Taxable__c,
                                                         RevRec_Start_Date__c
                                                         FROM FreightTM__Storage_Billing__c 
                                                         WHERE FreightTM__Storage__c = :invoiceId];
        
        
        String transactiontype = 'Sales Invoice';
        
        Date myDate = invoice.Date__c; 
        Integer createdYear = myDate.year();
        Integer createdMonth = myDate.month();
        Integer createdDay = myDate.day();
        String datecreated = '<year>' + createdYear + '</year><month>' + createdMonth + '</month><day>' + createdDay + '</day>';
        System.debug(datecreated);
        
        //String customerid = invoice.Customer_ID__c; //invoice.Customer__r.Customer_Id__c;
        String customerid = invoice.FreightTM__Load__r.Account__r.Customer_Id__c;
        //String Job = invoice.FreightTM__Load__r.Name;
        //String JobRef = invoice.Job_Ref_Number__c;
        //String referenceno = '<JobRef>' + JobRef + '</JobRef><Job>' + Job + '</Job>';
        String referenceno = invoice.Job_Ref_Number__c;
        String termname = invoice.Terms__c;                    
        String state = invoice.State__c;  
        
        // Define a map to store the mappings between Type__c values and their codes
        Map<String, String> typeCodeMap = new Map<String, String>{
            'Temperature Controlled Transportation' => '1022',
                'Packing Labor' => '1046',
                'Packing Material' => '1047',
                'Enhanced Service Protection' => '1043',
                'Temperature Controlled Storage' => '1051', 
                'Additional Monthly Storage' => '1051',     
                'Repeat Client Discount' => '1042',
                'Additional Handling' => '1022',
                'Additional Stops' => '1022',
                'Cataloging Wine' => '1020',
                'Parcel Delivery' => '1022',
                'Repack Drop off' => '1022',
                'Unpacking Services' => '1019',
                'Fuel Surcharge' => '1045',
                'Federal Express' => '',                     //needs Id to be set
                'Administrative Processing Fee' => '',       //needs Id to be set
                'Loss Coverage (with no deductible)' => '',  //needs Id to be set
                'Loss Coverage (Waived)' => '',              //needs Id to be set
                'Other Services' => '1032'
                };
                    String mappedTypeCode = '';
                    String sotransitems = '';
        for (FreightTM__Storage_Billing__c lineItem : lineItems) {
            String itemid = lineItem.Type__c;                                          //'I1';
            // Check if the Type__c value exists in the map
            if (typeCodeMap.containsKey(itemid)) {
                // Map the Type__c value to its corresponding code
                mappedTypeCode = typeCodeMap.get(itemid);
            } else {

                mappedTypeCode = lineItem.Name; // Set a default value
            }
            System.debug(mappedTypeCode);
            String itemdesc = lineItem.Description__c;                                      //'Inbound Mixed Case Peritem - 03/15/2024 - Order 116735';
            Boolean taxable = lineItem.Taxable__c;                                           //'true';
            Decimal quantity = lineItem.Number_of_Units__c;                                 //5.00;
            
            String unit ='Each';
            Decimal price = (lineItem.Unit_Price__c != null) ? lineItem.Unit_Price__c : 0;
            //Decimal price = lineItem.Unit_Price__c;  //Amount__c;                                             //3000.00;
            String locationid = lineItem.Location_IDs__c;                                    //'NYW'/WCT;                                 
            System.debug(price);
            /*Date STDate = lineItem.RevRec_Start_Date__c; 
            Integer startYear = STDate.year();
            Integer startMonth = STDate.month();
            Integer startDay = STDate.day();
            String revrecstartdate = '<year>' + startYear + '</year><month>' + startMonth + '</month><day>' + startDay + '</day>';*/
            //Construct sotransitem for each line item  //<revrecstartdate>' + revrecstartdate + '</revrecstartdate>
            String sotransitem = '<itemid>' + mappedTypeCode + '</itemid><itemdesc>' + itemdesc + '</itemdesc><taxable>' + taxable + '</taxable><quantity>' + quantity + '</quantity><unit>' + unit + '</unit><price>' + price + '</price><locationid>' + locationid + '</locationid>';//
            sotransitems += '<sotransitem>' + sotransitem + '</sotransitem>'; 
        }

        
        System.debug(sotransitems);
        String xmlInvoiceRequest = '<?xml version="1.0" encoding="UTF-8"?><request><control><senderid>Your-senderid</senderid><password>Your-Password</password><controlid>test</controlid><uniqueid>false</uniqueid><dtdversion>3.0</dtdversion></control>' +
            '<operation><authentication><login><userid>Your-userid</userid><companyid>Your-companyid</companyid><password>Your-passwordid</password></login></authentication>' +
            '<content>' +
            '<function controlid="3G2DFC86-9899-4283-360X-C789142D2801">' +
            '<create_sotransaction>' +
            '<transactiontype>' + transactiontype + '</transactiontype>' +
            '<datecreated>' + datecreated + '</datecreated>' + //invoice create date
            '<customerid>' + customerid + '</customerid>' +
            '<referenceno>' + referenceno + '</referenceno>' +
            '<termname>' + termname + '</termname>' +
            '<state>' + state + '</state>' +
            '<sotransitems>' + sotransitems + '</sotransitems>' +
            '</create_sotransaction>' +
            '</function></content></operation></request>';
        
        HttpRequest Invoicerequest = new HttpRequest();
        Invoicerequest.setEndpoint('https://api.intacct.com/ia/xml/xmlgw.phtml');
        Invoicerequest.setMethod('POST');
        Invoicerequest.setHeader('Content-Type', 'application/xml');
        Invoicerequest.setHeader('Accept', '*/*');
        
        Invoicerequest.setBody(xmlInvoiceRequest);
        
        Http http = new Http();
        HttpResponse Invoiceresponse = http.send(Invoicerequest);
        system.debug(Invoiceresponse.getStatus());
        system.debug(Invoiceresponse.getBody());
        system.debug(Invoiceresponse.getStatusCode());
        System.debug(Invoicerequest);
        
        // Check response status
        if (Invoiceresponse.getStatusCode() == 200) {
            // Parse the response XML
            Dom.Document doc = new Dom.Document();
            doc.load(Invoiceresponse.getBody());
            Dom.XmlNode resultNode = doc.getRootElement().getChildElement('operation', null).getChildElement('result', null);
            
            // Check if the response status is failure
            if (resultNode.getChildElement('status', null).getText().equalsIgnoreCase('failure')) {
                // Get the error message
                String errorMessage = '';
                for (Dom.XmlNode errorNode : resultNode.getChildElement('errormessage', null).getChildElements()) {
                    errorMessage += errorNode.getChildElement('description', null).getText() + '. ';
                    errorMessage += errorNode.getChildElement('description2', null).getText() + '. ';
                    //errorMessage += errorNode.getChildElement('correction', null).getText() + '. ';
                }
                
                // Display error message in VFP
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, errorMessage));
            } else {
                // Retrieve the values from the response
                String invoiceKey = resultNode.getChildElement('key', null).getText();
                
                // Update the invoice record with the extracted key
                FreightTM__Storage__c updatedInvoice = new FreightTM__Storage__c(
                    Id = invoiceId,
                    Sage_Invoice_Key__c = invoiceKey,
                    Status__c = 'Invoice Sent'
                );
                
                
                // Perform the update
                try {
                    update updatedInvoice;
                    System.debug('Invoice fields updated successfully.');
                    ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.INFO, 'The Invoice with ' + invoiceKey + ' Key number has been created in Sage successfully.'));
                    
                } catch (Exception e) {
                    System.debug('Error updating invoice fields: ' + e.getMessage());
                    // Handle the error appropriately
                }
            }
        } else {
            // Error in creating customer
            System.debug('There was an Error, Please contact the administrator.');
            
        }
        
        
    }
    
    
    public PageReference CreateInvoice() {  
        //InvoiceCreate(invoiceId);
        try {
            InvoiceCreate(invoiceId);
        } catch (Exception ex) {
            // Handle the exception or log it if needed
            System.debug('Error in Sage: ' + ex.getMessage());
        }
        system.debug('id: ' + invoiceId);
        return null;
    }
    
    
    public static void ItemCreate(Id invoiceId) {
        List<FreightTM__Storage_Billing__c> lineItemsToUpdate = new List<FreightTM__Storage_Billing__c>();
        
        // Query the specific invoice
        FreightTM__Storage__c invoice = [SELECT id, Name, Customer__r.Name, Customer__r.Customer_Id__c, Customer__r.Phone, Customer__r.Email__c, 
                                         Customer__r.BillingStreet, Customer__r.BillingCity, Customer__r.BillingState, Customer__r.BillingPostalCode, 
                                         Customer__r.BillingCountry, Customer__r.ShippingStreet, Customer__r.ShippingCity, Customer__r.ShippingState,
                                         Customer__r.ShippingPostalCode, Customer__r.SAGECustomerID__c, Customer__r.Sage_Record_Number__c,
                                         Customer__r.Primary_Contact__c, Sage_Customer_RecordNo__c 
                                         FROM FreightTM__Storage__c WHERE Id = :invoiceId LIMIT 1]; 
        
        // Query only the line items related to the specific invoice
        List<FreightTM__Storage_Billing__c> lineItems = [SELECT Id, Name, Sage_Item_Type__c, Type__c 
                                                         FROM FreightTM__Storage_Billing__c 
                                                         WHERE FreightTM__Storage__c = :invoiceId];
        
        // Iterate over each line item
        for(FreightTM__Storage_Billing__c lineItem : lineItems) {
            
            String senderid = 'Your-senderid';
            String senderpassword = 'Your-Password';
            String userid = 'Your-userid';
            String companyid = 'Your-companyid';
            String passwordid = 'Your-passwordid';
            
            String ITEMID = lineItem.Name;
            String Name = lineItem.Type__c;
            String ITEMTYPE = lineItem.Sage_Item_Type__c != null ? lineItem.Sage_Item_Type__c : '';
            
            String xmlItemRequest = '<?xml version="1.0" encoding="UTF-8"?>' +
                '<request><control><senderid>Your-senderid</senderid><password>Your-Password</password><controlid>test</controlid><uniqueid>false</uniqueid><dtdversion>3.0</dtdversion></control>' +
                '<operation>' +
                '<authentication><login><userid>Your-userid</userid><companyid>Your-companyid</companyid><password>Your-passwordid</password></login></authentication>' +
                '<content>' +
                '<function controlid="3G2DFC86-9899-4283-360X-C789142D2801">' +
                '<create>' +
                '<ITEM>' +
                '<ITEMID>' + ITEMID + '</ITEMID>' +
                '<NAME>' + Name + '</NAME>' +
                '<ITEMTYPE>' + ITEMTYPE + '</ITEMTYPE>' +
                '</ITEM>' +
                '</create></function></content></operation></request>';
            
            HttpRequest Itemrequest = new HttpRequest();
            Itemrequest.setEndpoint('https://api.intacct.com/ia/xml/xmlgw.phtml');
            Itemrequest.setMethod('POST');
            Itemrequest.setHeader('Content-Type', 'application/xml');
            Itemrequest.setHeader('Accept', '*/*');
            Itemrequest.setBody(xmlItemRequest);
            
            Http http = new Http();
            HttpResponse Itemresponse = http.send(Itemrequest);
            System.debug(Itemresponse.getStatus());
            System.debug(Itemresponse.getBody());
            System.debug(Itemresponse.getStatusCode());
            
            // Check if the response is successful
            if (Itemresponse.getStatusCode() == 200) {
                // Parse the response XML to extract the updated fields
                Dom.Document doc = new Dom.Document();
                doc.load(Itemresponse.getBody());
                Dom.XmlNode resultNode = doc.getRootElement().getChildElement('operation', null).getChildElement('result', null);
                
                // Check if the response status is failure
                if (resultNode.getChildElement('status', null).getText().equalsIgnoreCase('failure')) {
                    // Get the error message
                    String errorMessage = '';
                    for (Dom.XmlNode errorNode : resultNode.getChildElement('errormessage', null).getChildElements()) {
                        errorMessage += errorNode.getChildElement('description2', null).getText() + '. ';
                    }
                    
                    // Display error message in VFP
                    ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, errorMessage));
                } else {
                    // Retrieve the values from the response
                    String sageItemRecordNo = resultNode.getChildElement('data', null).getChildElement('item', null).getChildElement('RECORDNO', null).getText();
                    String newItemId = resultNode.getChildElement('data', null).getChildElement('item', null).getChildElement('ITEMID', null).getText();
                    
                    // Update the line item with the response values
                    lineItem.Item_Name__c = newItemId;
                    lineItem.Sage_Item_Record_Number__c = sageItemRecordNo;
                    
                    // Add the line item to the list to be updated
                    lineItemsToUpdate.add(lineItem);
                    ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.INFO, 'The Item with ' + sageItemRecordNo + ' record number has been created in Sage successfully.'));
                }
            } else {
                // Handle the error accordingly
                System.debug('Error in creating item: ' + Itemresponse.getBody());
            }
        }
        
        // Update all the line items after the loop
        update lineItemsToUpdate;
    }    
    
    
    
    
    Public PageReference CreateItem() {
        try {
            ItemCreate(invoiceId);
        } catch (Exception ex) {
            // Handle the exception or log it if needed
            System.debug('Error in Sage: ' + ex.getMessage());
        }
        //ItemCreate(invoiceId);
        return null;
    }
    
    
}