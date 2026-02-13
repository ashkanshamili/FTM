public class PostLoadDat2Controller {
    public String result { get; set; }
    public Id     pageId { get; set; }  
    public String datPostId { get; set; }
    
    // Constructor to pick up the Id from the VF URL ?id=<Load_Id>
    public PostLoadDat2Controller() {
        pageId = ApexPages.currentPage().getParameters().get('id');
        
        // fetch DAT_Post_Id__c so we can show/hide the Update button
        try {
            FreightTM__Load__c L = [
                SELECT Id, Name, DAT_Post_Id__c
                FROM FreightTM__Load__c
                WHERE Id = :pageId
                LIMIT 1
            ];
            datPostId = L.DAT_Post_Id__c;
        } catch (Exception e) {
            datPostId = null;
        }
        
    }
    
    public void executePostLoad() {
        System.debug('**[DEBUG]** PostLoadDat2Controller.executePostLoad called');
        result = PostLoadDat2.execute();
        System.debug('**[DEBUG]** Result set in controller: ' + result);
        
        // -------- NEW: catch the specific date/lead-time token and show your message
        /*if (result == PostLoadDat2.DATE_RULE_FAIL_TOKEN) {
            result = '<span style="color: red;">❌ Failed to post load. The Checked IN and Checked OUT fields should not be null.</span>';
            return;
        }
        if (result == PostLoadDat2.DATE_RULE_FAIL_TOKEN_Pickup) {
            result = '<span style="color: red;">❌ Failed to post load. The Checked IN date should be at least 2 days in further.</span>';
            return;
        }
        if (result == PostLoadDat2.DATE_RULE_FAIL_TOKEN_Delivery) {
            result = '<span style="color: red;">❌ Failed to post load. The Checked OUT date should not be less than the Checked IN date.</span>';
            return;
        }*/
        // ------- END OF THE NEW: catch the specific date/lead-time token and show your message
        
        if (result == null) {
            result = '<span style="color: red;">❌ Failed to post load. Please check all the required fields.</span>';
            return;
        }
        
        // parse the JSON
        Map<String,Object> resp         = (Map<String,Object>) JSON.deserializeUntyped(result);
        String               id         = (String) resp.get('id');
        String               shipmentId = (String) resp.get('shipmentId');
        Map<String,Object>   ownership  = (Map<String,Object>) resp.get('ownership');
        String               companyId  = String.valueOf( ownership.get('companyId') );
        String               officeId   = String.valueOf( ownership.get('officeId') );
        String               userId     = String.valueOf( ownership.get('userId') );
        
        // lane → origin / destination
        Map<String,Object> lane       = (Map<String,Object>) resp.get('lane');
        Map<String,Object> originMap  = (Map<String,Object>) lane.get('origin');
        Map<String,Object> destMap    = (Map<String,Object>) lane.get('destination');
        String origin = originMap.get('city')     + ', '
            + originMap.get('county')   + ', '
            + originMap.get('stateProv')+ ', '
            + originMap.get('postalCode');
        String destination = destMap.get('city')     + ', '
            + destMap.get('county')   + ', '
            + destMap.get('stateProv')+ ', '
            + destMap.get('postalCode');
        
        // posterInfo → contactMethods
        Map<String,Object>       posterInfo = (Map<String,Object>) resp.get('posterInfo');
        List<Object>             cmList     = (List<Object>) posterInfo.get('contactMethods');
        String phoneVal = '';
        String emailVal = '';
        for (Object o : cmList) {
            Map<String,Object> cm = (Map<String,Object>) o;
            String method = (String) cm.get('method');
            String val    = (String) cm.get('value');
            if (method == 'PRIMARY_PHONE') {
                phoneVal = val.startsWith('tel:') ? val.substring(4) : val;
            } else if (method == 'EMAIL') {
                emailVal = val;
            }
        }
        
        // posterInfo → company → address
        Map<String,Object> compMap  = (Map<String,Object>) posterInfo.get('company');
        String             compName = (String) compMap.get('name');
        Map<String,Object> addrMap  = (Map<String,Object>) compMap.get('address');
        String compAddr = addrMap.get('city')          + ', '
            + addrMap.get('stateOrProvince')+ ', '
            + addrMap.get('postalCode')    + ', '
            + addrMap.get('countryCode');
        
        // build the HTML result
        result = 
            '✅ <b style="color: green;">Your load has been posted successfully to DAT</b><br/>' +
            '• <b>id</b>: '          + id          + '<br/>' +
            '• <b>shipmentId</b>: '  + shipmentId  + '<br/>' +
            '• <b>companyId</b>: '   + companyId   + '<br/>' +
            '• <b>officeId</b>: '    + officeId    + '<br/>' +
            '• <b>userId</b>: '      + userId      + '<br/>' +
            '• <b>origin</b>: '      + origin      + '<br/>' +
            '• <b>destination</b>: ' + destination + '<br/>' +
            '• <b>contactMethods</b>:<br/>' +
            '&nbsp;&nbsp;Phone: '    + phoneVal    + '<br/>' +
            '&nbsp;&nbsp;Email: '    + emailVal    + '<br/>' +
            '• <b>company</b>: '     + compName    + '<br/>' +
            '• <b>company address</b>: ' + compAddr;
        
        // now build a plain-text description for the Task
        String textDesc = 
            '✔ Your load has been posted successfully to DAT\n'
            + 'id: '          + id          + '\n'
            + 'shipmentId: '  + shipmentId  + '\n'
            + 'companyId: '   + companyId   + '\n'
            + 'officeId: '    + officeId    + '\n'
            + 'userId: '      + userId      + '\n'
            + 'origin: '      + origin      + '\n'
            + 'destination: ' + destination + '\n'
            + 'Phone: '       + phoneVal    + '\n'
            + 'Email: '       + emailVal    + '\n'
            + 'company: '     + compName    + '\n'
            + 'company address: ' + compAddr;
        
        // --- NEW: Create a completed Task on the Load record ---
        Task t = new Task(
            Subject     = 'DAT Load Posted: ' + id,
            WhatId      = pageId,           // relates to your FreightTM__Load__c
            //Description = String.isBlank(result) ? 'DAT post succeeded: ' + shipmentId : result,
            Description = textDesc,
            Status      = 'Completed',
            Priority    = 'Normal'
        );
        insert t;
    }
    
    public void executeUpdateLoad() {
        System.debug('**[DEBUG]** PostLoadDat2Controller.executeUpdateLoad called');
        
        if (String.isBlank(datPostId)) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'This load has not been posted to DAT yet. Post first, then update.'
            ));
            return;
        }
        
        String respJson;
        try {
            respJson = UpdateLoadDat2.execute(pageId, datPostId);
        } catch (Exception e) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                '❌ Update failed: ' + e.getMessage()
            ));
            return;
        }
        
        if (String.isBlank(respJson)) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                '❌ Update failed with no response.'
            ));
            return;
        }
        
        // helper renders HTML and logs a Task
        parseResponseAndRender(respJson, 'DAT Load Updated: ');
    }
    
    public void executeDeleteLoad() {
        System.debug('**[DEBUG]** PostLoadDat2Controller.executeDeleteLoad called');
        
        if (String.isBlank(datPostId)) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'This load has not been posted to DAT yet. Nothing to delete.'
            ));
            return;
        }
        
        String respJson;
        try {
            respJson = DeleteLoadDat2.execute(pageId, datPostId);
        } catch (Exception e) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                '❌ Delete failed: ' + e.getMessage()
            ));
            return;
        }
        
        // parse the simple status JSON returned by DeleteLoadDat2
        String statusTxt = 'deleted';
        String codeTxt   = '';
        String bodyTxt   = '';
        try {
            Map<String,Object> m = (Map<String,Object>) JSON.deserializeUntyped(respJson);
            statusTxt = (String) m.get('status');         // "deleted" or "deleted_or_missing"
            codeTxt   = String.valueOf(m.get('code'));    // 200/202/204/404...
            bodyTxt   = (m.containsKey('body') && m.get('body') != null) ? String.valueOf(m.get('body')) : '';
        } catch (Exception ignore) {}
        
        // consider these as successful deletes
        Boolean wasDeleted = (statusTxt == 'deleted' || statusTxt == 'deleted_or_missing'
                              || codeTxt == '200' || codeTxt == '202' || codeTxt == '204' || codeTxt == '404');
        
        // optional banner message
        if (wasDeleted) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.CONFIRM,
                '✅ Your load has been deleted on DAT'
            ));
        }
        
        // Render a visible confirmation
        String successLine = wasDeleted ? '✅ <b style="color:green;">Your load has been deleted on DAT</b><br/>' : '';
        result =
            successLine +
            '🗑️ <b style="color:#d9534f;">DAT post delete result</b><br/>' +
            '• <b>id</b>: ' + datPostId + '<br/>' +
            '• <b>status</b>: ' + statusTxt + (String.isBlank(codeTxt) ? '' : ' (HTTP ' + codeTxt + ')') +
            (String.isBlank(bodyTxt) ? '' : '<br/>• <b>body</b>: <pre style="white-space:pre-wrap;margin:0;">' + bodyTxt.escapeHtml4() + '</pre>');
        
        // After successful delete, hide Update/Delete buttons on this page
        if (wasDeleted) {
            datPostId = null;
        }
    }

    
    // -------- helpers used ONLY by Update flow --------
    private void parseResponseAndRender(String jsonBody, String taskSubjectPrefix) {
        Map<String,Object> resp = (Map<String,Object>) JSON.deserializeUntyped(jsonBody);
        
        String id         = (String) resp.get('id');
        String shipmentId = (String) resp.get('shipmentId');
        
        Map<String,Object> ownership = (Map<String,Object>) resp.get('ownership');
        String companyId = ownership != null ? safeStr(ownership.get('companyId')) : '';
        String officeId  = ownership != null ? safeStr(ownership.get('officeId'))  : '';
        String userId    = ownership != null ? safeStr(ownership.get('userId'))    : '';
        
        Map<String,Object> lane      = (Map<String,Object>) resp.get('lane');
        Map<String,Object> originMap = lane != null ? (Map<String,Object>) lane.get('origin') : null;
        Map<String,Object> destMap   = lane != null ? (Map<String,Object>) lane.get('destination') : null;
        
        String origin = (originMap != null ? safeStr(originMap.get('city')) : '')
            + ', ' + (originMap != null ? safeStr(originMap.get('county')) : '')
            + ', ' + (originMap != null ? safeStr(originMap.get('stateProv')) : '')
            + ', ' + (originMap != null ? safeStr(originMap.get('postalCode')) : '');
        
        String destination = (destMap != null ? safeStr(destMap.get('city')) : '')
            + ', ' + (destMap != null ? safeStr(destMap.get('county')) : '')
            + ', ' + (destMap != null ? safeStr(destMap.get('stateProv')) : '')
            + ', ' + (destMap != null ? safeStr(destMap.get('postalCode')) : '');
        
        Map<String,Object> posterInfo = (Map<String,Object>) resp.get('posterInfo');
        List<Object> cmList = posterInfo != null ? (List<Object>) posterInfo.get('contactMethods') : null;
        
        String phoneVal = '';
        String emailVal = '';
        if (cmList != null) {
            for (Object o : cmList) {
                Map<String,Object> cm = (Map<String,Object>) o;
                String method = (String) cm.get('method');
                String val    = (String) cm.get('value');
                if (method == 'PRIMARY_PHONE') {
                    phoneVal = (val != null && val.startsWith('tel:')) ? val.substring(4) : safeStr(val);
                } else if (method == 'EMAIL') {
                    emailVal = safeStr(val);
                }
            }
        }
        
        Map<String,Object> compMap = posterInfo != null ? (Map<String,Object>) posterInfo.get('company') : null;
        String compName = compMap != null ? safeStr(compMap.get('name')) : '';
        Map<String,Object> addrMap = compMap != null ? (Map<String,Object>) compMap.get('address') : null;
        
        String compAddr = (addrMap != null ? safeStr(addrMap.get('city')) : '')
            + ', ' + (addrMap != null ? safeStr(addrMap.get('stateOrProvince')) : '')
            + ', ' + (addrMap != null ? safeStr(addrMap.get('postalCode')) : '')
            + ', ' + (addrMap != null ? safeStr(addrMap.get('countryCode')) : '');
        
        result =
            '✅ <b style="color: green;">Your load has been updated on DAT</b><br/>' +
            '• <b>id</b>: '          + safeStr(id)         + '<br/>' +
            '• <b>shipmentId</b>: '  + safeStr(shipmentId) + '<br/>' +
            '• <b>companyId</b>: '   + companyId           + '<br/>' +
            '• <b>officeId</b>: '    + officeId            + '<br/>' +
            '• <b>userId</b>: '      + userId              + '<br/>' +
            '• <b>origin</b>: '      + origin              + '<br/>' +
            '• <b>destination</b>: ' + destination         + '<br/>' +
            '• <b>contactMethods</b>:<br/>' +
            '&nbsp;&nbsp;Phone: '    + phoneVal            + '<br/>' +
            '&nbsp;&nbsp;Email: '    + emailVal            + '<br/>' +
            '• <b>company</b>: '     + compName            + '<br/>' +
            '• <b>company address</b>: ' + compAddr;
        
        Task t = new Task(
            Subject   = taskSubjectPrefix + safeStr(id),
            WhatId    = pageId,
            Description =
            'id: '           + safeStr(id)         + '\n' +
            'shipmentId: '   + safeStr(shipmentId) + '\n' +
            'companyId: '    + companyId           + '\n' +
            'officeId: '     + officeId            + '\n' +
            'userId: '       + userId              + '\n' +
            'origin: '       + origin              + '\n' +
            'destination: '  + destination         + '\n' +
            'Phone: '        + phoneVal            + '\n' +
            'Email: '        + emailVal            + '\n' +
            'company: '      + compName            + '\n' +
            'company address: ' + compAddr,
            Status    = 'Completed',
            Priority  = 'Normal'
        );
        insert t;
    }
    
    private static String safeStr(Object o) {
        return (o == null) ? '' : String.valueOf(o);
    }
}