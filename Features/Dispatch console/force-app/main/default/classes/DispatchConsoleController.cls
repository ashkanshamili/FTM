public without sharing class DispatchConsoleController {
    private static final Integer DEFAULT_PAGE_SIZE = 25;
    private static final Integer MAX_PAGE_SIZE = 100;

    private static final String LOAD_FIELDS =
        'Id, Name, CreatedDate,' +
        ' FreightTM__Pickup_Address__c, FreightTM__Pickup_City__c,' +
        ' FreightTM__Pickup_State__c, FreightTM__Pickup_Zip_Code__c,' +
        ' FreightTM__Pickup_Country__c, FreightTM__Delivery_Address__c,' +
        ' FreightTM__Delivery_City__c, FreightTM__Delivery_State__c,' +
        ' FreightTM__Delivery_Zip_Code__c, FreightTM__Delivery_Country__c,' +
        ' FreightTM__Status__c, FreightTM__Pickup_Date__c,' +
        ' FreightTM__Delivery_Date__c, FreightTM__Carrier_Obj__c,' +
        ' FreightTM__Carrier_Obj__r.Name,' +
        ' FreightTM__Carrier_Obj__r.FreightTM__Email__c,' +
        ' FreightTM__Driver__c, FreightTM__Driver__r.Name,' +
        ' Driver_Phone_Number__c, Driver_Phone_Carrier__c,' +
        ' Driver_Portal_Link__c, FreightTM__Truck__c,' +
        ' FreightTM__Truck__r.Name, FreightTM__Invoice_Status__c,' +
        ' FreightTM__Gross_Margin__c, FreightTM__Gross_Margin_Percent__c,' +
        ' Exception_Reason__c, POD_Received__c, FreightTM__Bill_Status__c';

    /**
     * Backward-compatible method. The new Dispatch LWCs use getLoadPage and
     * getResourcePage, so the browser no longer receives every table at once.
     */
    @AuraEnabled(cacheable=true)
    public static DispatchData getDispatchData(String stateCode) {
        DispatchData data = new DispatchData();
        String loadWhere = buildLoadWhere(stateCode, null, 'all', 'All', 'loadBoard');

        data.loads = Database.query(
            'SELECT ' + LOAD_FIELDS +
            ' FROM FreightTM__Load__c' + loadWhere +
            ' ORDER BY CreatedDate DESC, Id DESC LIMIT 25'
        );

        data.trucks = queryTruckPage(stateCode, null, 25, null, null, 'first');
        data.drivers = queryDriverPage(stateCode, null, 25, null, null, 'first');
        data.carriers = queryCarrierPage(stateCode, null, 25, null, null, 'first');
        return data;
    }

    @AuraEnabled
    public static LoadPageResult getLoadPage(
        String context,
        String stateCode,
        String searchKey,
        String viewName,
        String statusFilter,
        Integer pageSize,
        Datetime cursorCreatedDate,
        Id cursorId,
        String direction,
        Boolean includeSummary
    ) {
        Integer safePageSize = normalizePageSize(pageSize);
        String safeDirection = normalizeDirection(direction);
        String whereClause = buildLoadWhere(
            stateCode,
            searchKey,
            viewName,
            statusFilter,
            context
        );

        Integer totalCount = Database.countQuery(
            'SELECT COUNT() FROM FreightTM__Load__c' + whereClause
        );

        String pageWhere = appendCursorCondition(
            whereClause,
            cursorCreatedDate,
            cursorId,
            safeDirection
        );
        Boolean ascending = safeDirection == 'previous' || safeDirection == 'last';
        String orderDirection = ascending ? 'ASC' : 'DESC';
        Integer queryPageSize = pageLimitForDirection(
            totalCount, safePageSize, safeDirection
        );

        List<FreightTM__Load__c> records = Database.query(
            'SELECT ' + LOAD_FIELDS +
            ' FROM FreightTM__Load__c' + pageWhere +
            ' ORDER BY CreatedDate ' + orderDirection +
            ', Id ' + orderDirection +
            ' LIMIT ' + queryPageSize
        );

        if (ascending) {
            records = reverseLoads(records);
        }

        LoadPageResult result = new LoadPageResult();
        result.records = records;
        result.totalCount = totalCount;
        result.pageSize = safePageSize;
        result.statuses = includeSummary == true
            ? getAvailableLoadStatuses(stateCode)
            : new List<String>();
        result.summary = includeSummary == true
            ? buildLoadSummary(stateCode)
            : null;
        return result;
    }

    @AuraEnabled
    public static ResourcePageResult getResourcePage(
        String resourceType,
        String stateCode,
        String searchKey,
        Integer pageSize,
        Datetime cursorCreatedDate,
        Id cursorId,
        String direction,
        Boolean includeCounts
    ) {
        Integer safePageSize = normalizePageSize(pageSize);
        String safeDirection = normalizeDirection(direction);
        ResourcePageResult result = new ResourcePageResult();
        result.resourceType = resourceType;
        result.pageSize = safePageSize;
        if (includeCounts == true) {
            result.truckCount = Database.countQuery(
                'SELECT COUNT() FROM FreightTM__Truck__c' + buildTruckWhere(stateCode, null)
            );
            result.driverCount = Database.countQuery(
                'SELECT COUNT() FROM FreightTM__Employee__c' + buildDriverWhere(stateCode, null)
            );
            result.carrierCount = Database.countQuery(
                'SELECT COUNT() FROM FreightTM__Carrier__c' + buildCarrierWhere(stateCode, null)
            );
        }

        if (resourceType == 'Driver') {
            String whereClause = buildDriverWhere(stateCode, searchKey);
            result.totalCount = Database.countQuery(
                'SELECT COUNT() FROM FreightTM__Employee__c' + whereClause
            );
            Integer queryPageSize = pageLimitForDirection(
                result.totalCount, safePageSize, safeDirection
            );
            result.drivers = queryDriverPage(
                stateCode,
                searchKey,
                queryPageSize,
                cursorCreatedDate,
                cursorId,
                safeDirection
            );
        } else if (resourceType == 'Carrier') {
            String whereClause = buildCarrierWhere(stateCode, searchKey);
            result.totalCount = Database.countQuery(
                'SELECT COUNT() FROM FreightTM__Carrier__c' + whereClause
            );
            Integer queryPageSize = pageLimitForDirection(
                result.totalCount, safePageSize, safeDirection
            );
            result.carriers = queryCarrierPage(
                stateCode,
                searchKey,
                queryPageSize,
                cursorCreatedDate,
                cursorId,
                safeDirection
            );
        } else {
            result.resourceType = 'Truck';
            String whereClause = buildTruckWhere(stateCode, searchKey);
            result.totalCount = Database.countQuery(
                'SELECT COUNT() FROM FreightTM__Truck__c' + whereClause
            );
            Integer queryPageSize = pageLimitForDirection(
                result.totalCount, safePageSize, safeDirection
            );
            result.trucks = queryTruckPage(
                stateCode,
                searchKey,
                queryPageSize,
                cursorCreatedDate,
                cursorId,
                safeDirection
            );
        }
        return result;
    }

    private static List<FreightTM__Truck__c> queryTruckPage(
        String stateCode,
        String searchKey,
        Integer pageSize,
        Datetime cursorCreatedDate,
        Id cursorId,
        String direction
    ) {
        Boolean ascending = direction == 'previous' || direction == 'last';
        String orderDirection = ascending ? 'ASC' : 'DESC';
        String whereClause = appendCursorCondition(
            buildTruckWhere(stateCode, searchKey),
            cursorCreatedDate,
            cursorId,
            direction
        );

        List<FreightTM__Truck__c> rows = Database.query(
            'SELECT Id, Name, CreatedDate, State_Province__c,' +
            ' FreightTM__Unladen_Weight__c, FreightTM__Type__c,' +
            ' FreightTM__Active__c, FreightTM__License_Plate__c,' +
            ' FreightTM__License_Plate_State__c, FreightTM__Make__c,' +
            ' FreightTM__Model__c, FreightTM__Status__c,' +
            ' FreightTM__Driver__c, FreightTM__Driver__r.Name' +
            ' FROM FreightTM__Truck__c' + whereClause +
            ' ORDER BY CreatedDate ' + orderDirection +
            ', Id ' + orderDirection +
            ' LIMIT ' + pageSize
        );
        return ascending ? reverseTrucks(rows) : rows;
    }

    private static List<FreightTM__Employee__c> queryDriverPage(
        String stateCode,
        String searchKey,
        Integer pageSize,
        Datetime cursorCreatedDate,
        Id cursorId,
        String direction
    ) {
        Boolean ascending = direction == 'previous' || direction == 'last';
        String orderDirection = ascending ? 'ASC' : 'DESC';
        String whereClause = appendCursorCondition(
            buildDriverWhere(stateCode, searchKey),
            cursorCreatedDate,
            cursorId,
            direction
        );

        List<FreightTM__Employee__c> rows = Database.query(
            'SELECT Id, Name, CreatedDate, Status__c,' +
            ' FreightTM__First_Name__c, FreightTM__Type__c,' +
            ' FreightTM__Active__c, FreightTM__Phone__c,' +
            ' FreightTM__Email__c, FreightTM__City__c,' +
            ' FreightTM__State__c, FreightTM__Zip_Code__c' +
            ' FROM FreightTM__Employee__c' + whereClause +
            ' ORDER BY CreatedDate ' + orderDirection +
            ', Id ' + orderDirection +
            ' LIMIT ' + pageSize
        );
        return ascending ? reverseDrivers(rows) : rows;
    }

    private static List<FreightTM__Carrier__c> queryCarrierPage(
        String stateCode,
        String searchKey,
        Integer pageSize,
        Datetime cursorCreatedDate,
        Id cursorId,
        String direction
    ) {
        Boolean ascending = direction == 'previous' || direction == 'last';
        String orderDirection = ascending ? 'ASC' : 'DESC';
        String whereClause = appendCursorCondition(
            buildCarrierWhere(stateCode, searchKey),
            cursorCreatedDate,
            cursorId,
            direction
        );

        List<FreightTM__Carrier__c> rows = Database.query(
            'SELECT Id, Name, CreatedDate, FreightTM__Phone__c,' +
            ' FreightTM__Email__c, FreightTM__Primary_Contact__c,' +
            ' FreightTM__Billing_Address__c, FreightTM__Billing_City__c,' +
            ' FreightTM__Billing_State_Province__c,' +
            ' FreightTM__Billing_Zip_Code__c,' +
            ' FreightTM__Billing_Country__c, FreightTM__State_Province__c,' +
            ' FreightTM__On_boarding_Status__c, FreightTM__USDOT_Number__c,' +
            ' FreightTM__MC_MX_FF_Number__c' +
            ' FROM FreightTM__Carrier__c' + whereClause +
            ' ORDER BY CreatedDate ' + orderDirection +
            ', Id ' + orderDirection +
            ' LIMIT ' + pageSize
        );
        return ascending ? reverseCarriers(rows) : rows;
    }

    private static String buildLoadWhere(
        String stateCode,
        String searchKey,
        String viewName,
        String statusFilter,
        String context
    ) {
        List<String> filters = new List<String>();

        if (!String.isBlank(stateCode)) {
            String stateValue = quote(stateCode.trim());
            filters.add(
                '(FreightTM__Pickup_State__c = ' + stateValue +
                ' OR FreightTM__Delivery_State__c = ' + stateValue + ')'
            );
        }

        if (!String.isBlank(searchKey)) {
            String cleanSearch = searchKey.trim();
            if (Pattern.matches('^[0-9]{3}$', cleanSearch)) {
                String zipValue = quote(cleanSearch + '%');
                filters.add(
                    '(FreightTM__Pickup_Zip_Code__c LIKE ' + zipValue +
                    ' OR FreightTM__Delivery_Zip_Code__c LIKE ' + zipValue + ')'
                );
            } else {
                String likeValue = quote('%' + cleanSearch + '%');
                String exactValue = quote(cleanSearch);
                filters.add(
                    '(Name LIKE ' + likeValue +
                    ' OR FreightTM__Pickup_City__c LIKE ' + likeValue +
                    ' OR FreightTM__Pickup_State__c = ' + exactValue +
                    ' OR FreightTM__Delivery_City__c LIKE ' + likeValue +
                    ' OR FreightTM__Delivery_State__c = ' + exactValue +
                    ' OR FreightTM__Status__c = ' + exactValue +
                    ' OR FreightTM__Invoice_Status__c = ' + exactValue +
                    ' OR FreightTM__Bill_Status__c = ' + exactValue +
                    ' OR FreightTM__Carrier_Obj__r.Name LIKE ' + likeValue +
                    ' OR FreightTM__Driver__r.Name LIKE ' + likeValue +
                    ' OR FreightTM__Truck__r.Name LIKE ' + likeValue + ')'
                );
            }
        }

        if (!String.isBlank(statusFilter) && statusFilter != 'All') {
            filters.add('FreightTM__Status__c = ' + quote(statusFilter));
        }

        String safeView = String.isBlank(viewName) ? 'all' : viewName;
        if (safeView == 'exceptions') {
            filters.add(exceptionCondition());
        } else if (safeView == 'invoiceReady' || safeView == 'readyToInvoice') {
            filters.add(invoiceReadyCondition());
        } else if (safeView == 'unassigned') {
            filters.add(
                '(FreightTM__Carrier_Obj__c = null' +
                ' AND FreightTM__Driver__c = null' +
                ' AND FreightTM__Truck__c = null)'
            );
        } else if (safeView == 'lowMargin') {
            filters.add(lowMarginCondition());
        } else if (safeView == 'profitable') {
            filters.add(profitableMarginCondition());
        } else if (safeView == 'missingPod') {
            filters.add('(POD_Received__c = false OR POD_Received__c = null)');
        } else if (safeView == 'waiting') {
            filters.add(documentWaitingCondition());
        } else if (safeView == 'complete') {
            filters.add(documentCompleteCondition());
        } else if (safeView == 'ready') {
            filters.add(
                '(POD_Received__c = true' +
                ' OR FreightTM__Bill_Status__c IN (\'POD Received\', \'Bill/POD Received\'))'
            );
        }

        return filters.isEmpty()
            ? ''
            : ' WHERE ' + String.join(filters, ' AND ');
    }

    private static String buildTruckWhere(String stateCode, String searchKey) {
        List<String> filters = new List<String>();
        if (!String.isBlank(stateCode)) {
            filters.add('State_Province__c = ' + quote(stateCode.trim()));
        }
        if (!String.isBlank(searchKey)) {
            String value = quote('%' + searchKey.trim() + '%');
            filters.add(
                '(Name LIKE ' + value +
                ' OR FreightTM__License_Plate__c LIKE ' + value +
                ' OR FreightTM__Driver__r.Name LIKE ' + value + ')'
            );
        }
        return filters.isEmpty() ? '' : ' WHERE ' + String.join(filters, ' AND ');
    }

    private static String buildDriverWhere(String stateCode, String searchKey) {
        List<String> filters = new List<String>();
        if (!String.isBlank(stateCode)) {
            filters.add('FreightTM__State__c = ' + quote(stateCode.trim()));
        }
        if (!String.isBlank(searchKey)) {
            String value = quote('%' + searchKey.trim() + '%');
            filters.add(
                '(Name LIKE ' + value +
                ' OR FreightTM__First_Name__c LIKE ' + value +
                ' OR FreightTM__Phone__c LIKE ' + value +
                ' OR FreightTM__Email__c LIKE ' + value +
                ' OR FreightTM__City__c LIKE ' + value +
                ')'
            );
        }
        return filters.isEmpty() ? '' : ' WHERE ' + String.join(filters, ' AND ');
    }

    private static String buildCarrierWhere(String stateCode, String searchKey) {
        List<String> filters = new List<String>();
        if (!String.isBlank(stateCode)) {
            String stateValue = quote(stateCode.trim());
            filters.add(
                '(FreightTM__Billing_State_Province__c = ' + stateValue +
                ' OR FreightTM__State_Province__c = ' + stateValue + ')'
            );
        }
        if (!String.isBlank(searchKey)) {
            String value = quote('%' + searchKey.trim() + '%');
            filters.add(
                '(Name LIKE ' + value +
                ' OR FreightTM__Phone__c LIKE ' + value +
                ' OR FreightTM__Email__c LIKE ' + value +
                ' OR FreightTM__Billing_City__c LIKE ' + value +
                ' OR FreightTM__MC_MX_FF_Number__c LIKE ' + value + ')'
            );
        }
        return filters.isEmpty() ? '' : ' WHERE ' + String.join(filters, ' AND ');
    }

    private static String buildCursorCondition(
        Datetime cursorCreatedDate,
        Id cursorId,
        String direction
    ) {
        if (cursorCreatedDate == null || cursorId == null ||
            direction == 'first' || direction == 'last') {
            return '';
        }

        String operatorValue = direction == 'previous' ? '>' : '<';
        String condition =
            '(CreatedDate ' + operatorValue + ' :cursorCreatedDate' +
            ' OR (CreatedDate = :cursorCreatedDate' +
            ' AND Id ' + operatorValue + ' :cursorId))';

        return condition;
    }

    private static String appendCursorCondition(
        String baseWhere,
        Datetime cursorCreatedDate,
        Id cursorId,
        String direction
    ) {
        String cursorCondition = buildCursorCondition(
            cursorCreatedDate,
            cursorId,
            direction
        );

        return String.isBlank(cursorCondition)
            ? baseWhere
            : appendCondition(baseWhere, cursorCondition);
    }

    private static LoadSummary buildLoadSummary(String stateCode) {
        String baseWhere = buildLoadWhere(stateCode, null, 'all', 'All', 'loadBoard');
        LoadSummary summary = new LoadSummary();

        List<AggregateResult> totalRows = Database.query(
            'SELECT COUNT(Id) totalCount,' +
            ' AVG(FreightTM__Gross_Margin_Percent__c) avgMargin,' +
            ' SUM(FreightTM__Gross_Margin__c) totalGrossMargin' +
            ' FROM FreightTM__Load__c' + baseWhere
        );
        AggregateResult totals = totalRows[0];

        summary.totalLoads = integerValue(totals.get('totalCount'));
        summary.avgMarginPercent = normalizePercent(decimalValue(totals.get('avgMargin')));
        summary.totalGrossMargin = decimalValue(totals.get('totalGrossMargin'));
        summary.exceptionCount = countWithCondition(baseWhere, exceptionCondition());
        summary.invoiceReadyCount = countWithCondition(baseWhere, invoiceReadyCondition());
        summary.lowMarginCount = countWithCondition(baseWhere, lowMarginCondition());
        summary.missingPodCount = countWithCondition(
            baseWhere,
            '(POD_Received__c = false OR POD_Received__c = null)'
        );
        summary.readyToInvoiceCount = countWithCondition(baseWhere, invoiceReadyCondition());
        summary.waitingDocumentCount = countWithCondition(baseWhere, documentWaitingCondition());
        summary.completeDocumentCount = countWithCondition(baseWhere, documentCompleteCondition());

        List<AggregateResult> riskRows = Database.query(
            'SELECT SUM(FreightTM__Gross_Margin__c) riskValue' +
            ' FROM FreightTM__Load__c' + appendCondition(baseWhere, lowMarginCondition())
        );
        AggregateResult risk = riskRows[0];
        summary.marginAtRisk = decimalValue(risk.get('riskValue'));

        summary.excellentMarginCount = countWithCondition(baseWhere, excellentMarginCondition());
        summary.healthyMarginCount = countWithCondition(baseWhere, healthyMarginCondition());
        summary.watchMarginCount = countWithCondition(baseWhere, watchMarginCondition());

        List<FreightTM__Load__c> bestRows = Database.query(
            'SELECT Id, Name, FreightTM__Gross_Margin_Percent__c' +
            ' FROM FreightTM__Load__c' +
            appendCondition(baseWhere, 'FreightTM__Gross_Margin_Percent__c != null') +
            ' ORDER BY FreightTM__Gross_Margin_Percent__c DESC LIMIT 1'
        );
        if (!bestRows.isEmpty()) {
            summary.bestMarginLoad = bestRows[0].Name;
            summary.bestMarginPercent = normalizePercent(
                bestRows[0].FreightTM__Gross_Margin_Percent__c
            );
        }

        summary.onTimePercent = summary.totalLoads == 0
            ? 0
            : ((Decimal)(summary.totalLoads - summary.exceptionCount) /
                summary.totalLoads) * 100;
        return summary;
    }

    private static List<String> getAvailableLoadStatuses(String stateCode) {
        String baseWhere = buildLoadWhere(stateCode, null, 'all', 'All', 'assignment');
        String statusCondition = 'FreightTM__Status__c != null';
        List<AggregateResult> rows = Database.query(
            'SELECT FreightTM__Status__c statusValue' +
            ' FROM FreightTM__Load__c' + appendCondition(baseWhere, statusCondition) +
            ' GROUP BY FreightTM__Status__c' +
            ' ORDER BY FreightTM__Status__c LIMIT 200'
        );
        List<String> statuses = new List<String>();
        for (AggregateResult row : rows) {
            statuses.add((String) row.get('statusValue'));
        }
        return statuses;
    }

    private static Integer countWithCondition(String baseWhere, String condition) {
        return Database.countQuery(
            'SELECT COUNT() FROM FreightTM__Load__c' +
            appendCondition(baseWhere, condition)
        );
    }

    private static String appendCondition(String baseWhere, String condition) {
        return String.isBlank(baseWhere)
            ? ' WHERE ' + condition
            : baseWhere + ' AND ' + condition;
    }

    private static String exceptionCondition() {
        String statusCondition =
            'FreightTM__Status__c IN (' +
            '\'Closed Delayed\', \'Delayed\', \'Late\',' +
            ' \'Exception\', \'On Hold\', \'At Risk\', \'Claim\'' +
            ')';

        Schema.SObjectField reasonField =
            Schema.SObjectType.FreightTM__Load__c.fields.getMap().get('Exception_Reason__c');
        Boolean reasonIsFilterable = reasonField != null &&
            reasonField.getDescribe().isFilterable();

        return reasonIsFilterable
            ? '(Exception_Reason__c != null OR ' + statusCondition + ')'
            : '(' + statusCondition + ')';
    }

    private static String invoiceReadyCondition() {
        return '(' +
            'POD_Received__c = true AND (' +
            'FreightTM__Bill_Status__c IN (\'POD Received\', \'Bill/POD Received\')' +
            ' OR FreightTM__Invoice_Status__c IN (' +
            '\'Ready\', \'Ready to Invoice\', \'Approved\', \'Invoiced\'' +
            ')' +
            '))';
    }

    private static String documentWaitingCondition() {
        return '(' +
            'POD_Received__c = true AND (' +
            'FreightTM__Bill_Status__c IN (\'Variance\', \'Claim\', \'Claims\')' +
            ' OR FreightTM__Invoice_Status__c IN (' +
            '\'Hold\', \'On Hold\', \'Rejected\'' +
            ')' +
            '))';
    }

    private static String documentCompleteCondition() {
        return '(' +
            'POD_Received__c = true' +
            ' AND (FreightTM__Bill_Status__c = null OR ' +
            'FreightTM__Bill_Status__c NOT IN (' +
            '\'POD Received\', \'Bill/POD Received\',' +
            ' \'Variance\', \'Claim\', \'Claims\'' +
            '))' +
            ' AND (FreightTM__Invoice_Status__c = null OR ' +
            'FreightTM__Invoice_Status__c NOT IN (' +
            '\'Ready\', \'Ready to Invoice\', \'Approved\',' +
            ' \'Invoiced\', \'Hold\', \'On Hold\', \'Rejected\'' +
            '))' +
            ')';
    }

    private static String lowMarginCondition() {
        return '(' +
            'FreightTM__Gross_Margin_Percent__c != null AND (' +
            'FreightTM__Gross_Margin_Percent__c < 0.15' +
            ' OR (FreightTM__Gross_Margin_Percent__c > 1' +
            ' AND FreightTM__Gross_Margin_Percent__c < 15)' +
            '))';
    }

    private static String profitableMarginCondition() {
        return '(' +
            '(FreightTM__Gross_Margin_Percent__c >= 0.25' +
            ' AND FreightTM__Gross_Margin_Percent__c <= 1)' +
            ' OR FreightTM__Gross_Margin_Percent__c >= 25' +
            ')';
    }

    private static String watchMarginCondition() {
        return '(' +
            '(FreightTM__Gross_Margin_Percent__c >= 0.15' +
            ' AND FreightTM__Gross_Margin_Percent__c < 0.20)' +
            ' OR (FreightTM__Gross_Margin_Percent__c >= 15' +
            ' AND FreightTM__Gross_Margin_Percent__c < 20)' +
            ')';
    }

    private static String healthyMarginCondition() {
        return '(' +
            '(FreightTM__Gross_Margin_Percent__c >= 0.20' +
            ' AND FreightTM__Gross_Margin_Percent__c < 0.30)' +
            ' OR (FreightTM__Gross_Margin_Percent__c >= 20' +
            ' AND FreightTM__Gross_Margin_Percent__c < 30)' +
            ')';
    }

    private static String excellentMarginCondition() {
        return '(' +
            '(FreightTM__Gross_Margin_Percent__c >= 0.30' +
            ' AND FreightTM__Gross_Margin_Percent__c <= 1)' +
            ' OR FreightTM__Gross_Margin_Percent__c >= 30' +
            ')';
    }

    private static Integer pageLimitForDirection(
        Integer totalCount,
        Integer pageSize,
        String direction
    ) {
        if (direction != 'last' || totalCount == null || totalCount <= 0) {
            return pageSize;
        }
        Integer remainder = Math.mod(totalCount, pageSize);
        return remainder == 0 ? pageSize : remainder;
    }

    private static Integer normalizePageSize(Integer requestedPageSize) {
        if (requestedPageSize == null || requestedPageSize <= 0) {
            return DEFAULT_PAGE_SIZE;
        }
        return requestedPageSize > MAX_PAGE_SIZE ? MAX_PAGE_SIZE : requestedPageSize;
    }

    private static String normalizeDirection(String direction) {
        Set<String> allowed = new Set<String>{ 'first', 'next', 'previous', 'last' };
        return allowed.contains(direction) ? direction : 'first';
    }

    private static String quote(String value) {
        return '\'' + String.escapeSingleQuotes(value == null ? '' : value) + '\'';
    }

    private static Decimal decimalValue(Object value) {
        return value == null ? 0 : (Decimal) value;
    }

    private static Integer integerValue(Object value) {
        return value == null ? 0 : Integer.valueOf(String.valueOf(value));
    }

    private static Decimal normalizePercent(Decimal value) {
        if (value == null) {
            return 0;
        }
        Decimal absoluteValue = value < 0 ? -value : value;
        return absoluteValue <= 1 ? value * 100 : value;
    }

    private static List<FreightTM__Load__c> reverseLoads(List<FreightTM__Load__c> source) {
        List<FreightTM__Load__c> result = new List<FreightTM__Load__c>();
        for (Integer indexValue = source.size() - 1; indexValue >= 0; indexValue--) {
            result.add(source[indexValue]);
        }
        return result;
    }

    private static List<FreightTM__Truck__c> reverseTrucks(List<FreightTM__Truck__c> source) {
        List<FreightTM__Truck__c> result = new List<FreightTM__Truck__c>();
        for (Integer indexValue = source.size() - 1; indexValue >= 0; indexValue--) {
            result.add(source[indexValue]);
        }
        return result;
    }

    private static List<FreightTM__Employee__c> reverseDrivers(List<FreightTM__Employee__c> source) {
        List<FreightTM__Employee__c> result = new List<FreightTM__Employee__c>();
        for (Integer indexValue = source.size() - 1; indexValue >= 0; indexValue--) {
            result.add(source[indexValue]);
        }
        return result;
    }

    private static List<FreightTM__Carrier__c> reverseCarriers(List<FreightTM__Carrier__c> source) {
        List<FreightTM__Carrier__c> result = new List<FreightTM__Carrier__c>();
        for (Integer indexValue = source.size() - 1; indexValue >= 0; indexValue--) {
            result.add(source[indexValue]);
        }
        return result;
    }

    public class DispatchData {
        @AuraEnabled public List<FreightTM__Truck__c> trucks { get; set; }
        @AuraEnabled public List<FreightTM__Employee__c> drivers { get; set; }
        @AuraEnabled public List<FreightTM__Carrier__c> carriers { get; set; }
        @AuraEnabled public List<FreightTM__Load__c> loads { get; set; }

        public DispatchData() {
            trucks = new List<FreightTM__Truck__c>();
            drivers = new List<FreightTM__Employee__c>();
            carriers = new List<FreightTM__Carrier__c>();
            loads = new List<FreightTM__Load__c>();
        }
    }

    public class LoadPageResult {
        @AuraEnabled public List<FreightTM__Load__c> records { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public Integer pageSize { get; set; }
        @AuraEnabled public List<String> statuses { get; set; }
        @AuraEnabled public LoadSummary summary { get; set; }

        public LoadPageResult() {
            records = new List<FreightTM__Load__c>();
            statuses = new List<String>();
            totalCount = 0;
        }
    }

    public class ResourcePageResult {
        @AuraEnabled public String resourceType { get; set; }
        @AuraEnabled public List<FreightTM__Truck__c> trucks { get; set; }
        @AuraEnabled public List<FreightTM__Employee__c> drivers { get; set; }
        @AuraEnabled public List<FreightTM__Carrier__c> carriers { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public Integer pageSize { get; set; }
        @AuraEnabled public Integer truckCount { get; set; }
        @AuraEnabled public Integer driverCount { get; set; }
        @AuraEnabled public Integer carrierCount { get; set; }

        public ResourcePageResult() {
            trucks = new List<FreightTM__Truck__c>();
            drivers = new List<FreightTM__Employee__c>();
            carriers = new List<FreightTM__Carrier__c>();
            totalCount = 0;
            truckCount = 0;
            driverCount = 0;
            carrierCount = 0;
        }
    }

    public class LoadSummary {
        @AuraEnabled public Integer totalLoads { get; set; }
        @AuraEnabled public Integer exceptionCount { get; set; }
        @AuraEnabled public Integer invoiceReadyCount { get; set; }
        @AuraEnabled public Decimal avgMarginPercent { get; set; }
        @AuraEnabled public Decimal onTimePercent { get; set; }
        @AuraEnabled public Decimal totalGrossMargin { get; set; }
        @AuraEnabled public Integer lowMarginCount { get; set; }
        @AuraEnabled public Decimal marginAtRisk { get; set; }
        @AuraEnabled public Decimal bestMarginPercent { get; set; }
        @AuraEnabled public String bestMarginLoad { get; set; }
        @AuraEnabled public Integer missingPodCount { get; set; }
        @AuraEnabled public Integer readyToInvoiceCount { get; set; }
        @AuraEnabled public Integer waitingDocumentCount { get; set; }
        @AuraEnabled public Integer completeDocumentCount { get; set; }
        @AuraEnabled public Integer excellentMarginCount { get; set; }
        @AuraEnabled public Integer healthyMarginCount { get; set; }
        @AuraEnabled public Integer watchMarginCount { get; set; }

        public LoadSummary() {
            totalLoads = 0;
            exceptionCount = 0;
            invoiceReadyCount = 0;
            avgMarginPercent = 0;
            onTimePercent = 0;
            totalGrossMargin = 0;
            lowMarginCount = 0;
            marginAtRisk = 0;
            bestMarginPercent = 0;
            bestMarginLoad = 'No margin data';
            missingPodCount = 0;
            readyToInvoiceCount = 0;
            waitingDocumentCount = 0;
            completeDocumentCount = 0;
            excellentMarginCount = 0;
            healthyMarginCount = 0;
            watchMarginCount = 0;
        }
    }

    @AuraEnabled
    public static void assignToLoads(List<Id> loadIds, Id selectedRecordId, String selectedType) {
        if (loadIds == null || loadIds.isEmpty()) {
            throw new AuraHandledException('Please select at least one load.');
        }
        if (selectedRecordId == null) {
            throw new AuraHandledException('Please select a truck, driver, or carrier.');
        }
        if (String.isBlank(selectedType)) {
            throw new AuraHandledException('Selected type is required.');
        }

        List<FreightTM__Load__c> loadsToUpdate = new List<FreightTM__Load__c>();
        for (Id loadId : loadIds) {
            FreightTM__Load__c loadRecord = new FreightTM__Load__c(Id = loadId);
            if (selectedType == 'Driver') {
                loadRecord.FreightTM__Driver__c = selectedRecordId;
            } else if (selectedType == 'Truck') {
                loadRecord.FreightTM__Truck__c = selectedRecordId;
            } else if (selectedType == 'Carrier') {
                loadRecord.FreightTM__Carrier_Obj__c = selectedRecordId;
            } else {
                throw new AuraHandledException('Invalid selected type: ' + selectedType);
            }
            loadsToUpdate.add(loadRecord);
        }
        update loadsToUpdate;
    }

    @AuraEnabled
    public static void pingDriver(
        Id loadId,
        Id driverId,
        String phoneNumber,
        String carrier
    ) {
        if (loadId == null) {
            throw new AuraHandledException('A Load record is required.');
        }
        if (driverId == null) {
            throw new AuraHandledException('Please select a driver.');
        }
        if (String.isBlank(phoneNumber)) {
            throw new AuraHandledException('Please enter the driver phone number.');
        }
        if (String.isBlank(carrier)) {
            throw new AuraHandledException('Please select the driver phone carrier.');
        }

        String cleanPhone = phoneNumber.replaceAll('[^0-9]', '');
        if (String.isBlank(cleanPhone)) {
            throw new AuraHandledException('Please enter a valid driver phone number.');
        }

        FreightTM__Load__c loadRecord = [
            SELECT Id, FreightTM__Driver__c, Driver_Portal_Link__c
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];
        if (String.isBlank(loadRecord.Driver_Portal_Link__c)) {
            throw new AuraHandledException('The Driver Portal Link is blank for this Load.');
        }

        try {
            update new FreightTM__Employee__c(
                Id = driverId,
                FreightTM__Phone__c = cleanPhone
            );
            if (loadRecord.FreightTM__Driver__c != driverId) {
                loadRecord.FreightTM__Driver__c = driverId;
                update loadRecord;
            }
            System.enqueueJob(
                new DriverPortalSmsQueueable(new Set<Id>{ loadRecord.Id })
            );
        } catch (DmlException exceptionRecord) {
            throw new AuraHandledException(exceptionRecord.getDmlMessage(0));
        } catch (Exception exceptionRecord) {
            throw new AuraHandledException(
                'Unable to ping the driver: ' + exceptionRecord.getMessage()
            );
        }
    }

    @AuraEnabled
    public static Id saveInvoicePdfToLoad(Id loadId) {
        if (loadId == null) {
            throw new AuraHandledException('A Load record is required.');
        }

        FreightTM__Load__c loadRecord = [
            SELECT Id, Name
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];

        Blob pdfBody;
        if (Test.isRunningTest()) {
            pdfBody = Blob.valueOf('Invoice test PDF');
        } else {
            PageReference invoicePage = new PageReference('/apex/Invoice');
            invoicePage.getParameters().put('id', String.valueOf(loadId));
            pdfBody = invoicePage.getContentAsPDF();
        }

        String safeLoadName = String.isBlank(loadRecord.Name)
            ? String.valueOf(loadRecord.Id)
            : loadRecord.Name;

        ContentVersion versionRecord = new ContentVersion(
            Title = 'Invoice - ' + safeLoadName,
            PathOnClient = 'Invoice-' + safeLoadName + '.pdf',
            VersionData = pdfBody,
            FirstPublishLocationId = loadRecord.Id
        );
        insert versionRecord;

        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :versionRecord.Id
            LIMIT 1
        ].ContentDocumentId;
    }

    @AuraEnabled
    public static void sendRateConEmailToCarrier(
        Id loadId,
        String toEmail,
        String subject,
        String body
    ) {
        if (loadId == null) {
            throw new AuraHandledException('A Load record is required.');
        }
        if (String.isBlank(toEmail)) {
            throw new AuraHandledException('Recipient email is required.');
        }

        FreightTM__Load__c loadRecord = [
            SELECT Id, Name
            FROM FreightTM__Load__c
            WHERE Id = :loadId
            LIMIT 1
        ];

        Blob pdfBody;
        if (Test.isRunningTest()) {
            pdfBody = Blob.valueOf('Rate Confirmation test PDF');
        } else {
            PageReference rateConPage = new PageReference('/apex/RateCon');
            rateConPage.getParameters().put('id', String.valueOf(loadId));
            pdfBody = rateConPage.getContentAsPDF();
        }

        Messaging.EmailFileAttachment attachment =
            new Messaging.EmailFileAttachment();
        attachment.setFileName(
            'Rate_Con#' +
            (String.isBlank(loadRecord.Name)
                ? String.valueOf(loadRecord.Id)
                : loadRecord.Name) +
            '.pdf'
        );
        attachment.setContentType('application/pdf');
        attachment.setBody(pdfBody);

        Messaging.SingleEmailMessage email =
            new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ toEmail.trim() });
        email.setSubject(
            String.isBlank(subject)
                ? 'Rate Confirmation'
                : subject
        );
        email.setPlainTextBody(
            String.isBlank(body)
                ? 'Please find the rate confirmation attached.'
                : body
        );
        email.setFileAttachments(
            new List<Messaging.EmailFileAttachment>{ attachment }
        );
        email.setSaveAsActivity(false);

        Messaging.SendEmailResult[] results =
            Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{ email }
            );

        if (
            results == null ||
            results.isEmpty() ||
            !results[0].isSuccess()
        ) {
            String message = 'The Rate Confirmation email could not be sent.';
            if (
                results != null &&
                !results.isEmpty() &&
                results[0].getErrors() != null &&
                !results[0].getErrors().isEmpty()
            ) {
                message += ' ' + results[0].getErrors()[0].getMessage();
            }
            throw new AuraHandledException(message);
        }
    }

}