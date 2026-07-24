public without sharing class AutoFillWebhookAuthenticator {

    private static final String CONFIG_DEVELOPER_NAME =
        'FreightGraph_Email_Extraction';

    private static final Integer DEFAULT_REPLAY_WINDOW = 300;

    @TestVisible
    private static String testSecret;

    @TestVisible
    private static Integer testReplayWindow;

    @TestVisible
    private static Long testCurrentTimestamp;

    @TestVisible
    private static String testLegacyApiKey;

    public class AuthenticationResult {
        public Boolean valid;
        public Integer statusCode;
        public String code;
        public String message;
        public String deliveryId;
    }

    /**
     * Strict FreightGraph HMAC validation kept for backward compatibility with
     * the existing unit tests and documented V2 contract.
     */
    public static AuthenticationResult authenticate(
        RestRequest request,
        String body
    ) {
        if (request == null) {
            return failure(
                401,
                'INVALID_REQUEST',
                'The webhook request is unavailable.'
            );
        }

        String signatureHeader = getHeaderIgnoreCase(
            request,
            'X-FreightGraph-Signature'
        );

        String timestampHeader = getHeaderIgnoreCase(
            request,
            'X-FreightGraph-Timestamp'
        );

        String deliveryId = getHeaderIgnoreCase(
            request,
            'X-FreightGraph-Delivery-Id'
        );

        if (
            String.isBlank(signatureHeader) ||
            String.isBlank(timestampHeader)
        ) {
            return failure(
                401,
                'MISSING_SIGNATURE',
                'Required webhook signature headers are missing.'
            );
        }

        signatureHeader = signatureHeader.trim();
        timestampHeader = timestampHeader.trim();

        if (!signatureHeader.toLowerCase().startsWith('sha256=')) {
            return failure(
                401,
                'INVALID_SIGNATURE_FORMAT',
                'The signature must begin with sha256=.'
            );
        }

        String suppliedSignatureHex =
            signatureHeader.substringAfter('=')
            .trim()
            .toLowerCase();

        if (!isHexSha256(suppliedSignatureHex)) {
            return failure(
                401,
                'INVALID_SIGNATURE_FORMAT',
                'The signature must contain 64 hexadecimal characters.'
            );
        }

        Long webhookTimestamp;

        try {
            webhookTimestamp = Long.valueOf(timestampHeader);
        } catch (Exception e) {
            return failure(
                401,
                'INVALID_TIMESTAMP',
                'The webhook timestamp is invalid.'
            );
        }

        Configuration configuration;

        try {
            configuration = getConfiguration();
        } catch (Exception e) {
            return failure(
                500,
                'AUTHENTICATION_NOT_CONFIGURED',
                e.getMessage()
            );
        }

        AuthenticationResult replayFailure = validateReplayWindow(
            normalizeTimestampForReplayCheck(webhookTimestamp),
            configuration.replayWindowSeconds
        );

        if (replayFailure != null) {
            return replayFailure;
        }

        return verifyHexSignature(
            suppliedSignatureHex,
            timestampHeader,
            body,
            configuration.secret,
            deliveryId
        );
    }

    /**
     * Compatibility authentication used by both V1 and V2 webhook endpoints.
     * It accepts the strict V2 format first, then common HMAC header/encoding
     * variants, and finally the existing V1 x-api-key configuration.
     */
    public static AuthenticationResult authenticateWebhook(
        RestRequest request,
        String body
    ) {
        AuthenticationResult strictResult = authenticate(request, body);

        if (strictResult.valid == true) {
            return strictResult;
        }

        AuthenticationResult compatibleResult =
            authenticateCompatibleHmac(request, body);

        if (compatibleResult.valid == true) {
            return compatibleResult;
        }

        AuthenticationResult legacyApiKeyResult =
            authenticateLegacyApiKey(request);

        if (legacyApiKeyResult != null) {
            return legacyApiKeyResult;
        }

        if (compatibleResult.code != 'MISSING_SIGNATURE') {
            return compatibleResult;
        }

        return strictResult;
    }

    @TestVisible
    private static AuthenticationResult authenticateCompatibleHmac(
        RestRequest request,
        String body
    ) {
        if (request == null) {
            return failure(
                401,
                'INVALID_REQUEST',
                'The webhook request is unavailable.'
            );
        }

        String signatureHeader = getFirstHeaderIgnoreCase(
            request,
            new List<String>{
                'X-FreightGraph-Signature',
                'X-Webhook-Signature',
                'X-Signature',
                'X-Hub-Signature-256'
            }
        );

        String timestampHeader = getFirstHeaderIgnoreCase(
            request,
            new List<String>{
                'X-FreightGraph-Timestamp',
                'X-Webhook-Timestamp',
                'X-Timestamp'
            }
        );

        String deliveryId = getFirstHeaderIgnoreCase(
            request,
            new List<String>{
                'X-FreightGraph-Delivery-Id',
                'X-Webhook-Delivery-Id',
                'X-Delivery-Id',
                'X-Request-Id'
            }
        );

        if (
            String.isBlank(signatureHeader) ||
            String.isBlank(timestampHeader)
        ) {
            return failure(
                401,
                'MISSING_SIGNATURE',
                'Required webhook signature headers are missing.'
            );
        }

        String suppliedSignature = cleanCompatibleSignature(
            signatureHeader
        );

        if (String.isBlank(suppliedSignature)) {
            return failure(
                401,
                'INVALID_SIGNATURE_FORMAT',
                'The webhook signature is empty.'
            );
        }

        Long timestampSeconds = parseTimestampSeconds(
            timestampHeader.trim()
        );

        if (timestampSeconds == null) {
            return failure(
                401,
                'INVALID_TIMESTAMP',
                'The webhook timestamp is invalid.'
            );
        }

        Configuration configuration;

        try {
            configuration = getConfiguration();
        } catch (Exception e) {
            return failure(
                500,
                'AUTHENTICATION_NOT_CONFIGURED',
                e.getMessage()
            );
        }

        AuthenticationResult replayFailure = validateReplayWindow(
            timestampSeconds,
            configuration.replayWindowSeconds
        );

        if (replayFailure != null) {
            return replayFailure;
        }

        List<String> signingPayloads = buildSigningPayloads(
            timestampHeader.trim(),
            body
        );

        List<String> signingModes = buildSigningModes();
        Boolean suppliedIsHex = isHexSha256(
            suppliedSignature.toLowerCase()
        );
        String normalizedSuppliedBase64 = normalizeBase64(
            suppliedSignature
        );

        for (Integer i = 0; i < signingPayloads.size(); i++) {
            Blob generatedMac = generateMac(
                signingPayloads[i],
                configuration.secret
            );

            String expectedHex = EncodingUtil.convertToHex(
                generatedMac
            ).toLowerCase();

            String expectedBase64 = normalizeBase64(
                EncodingUtil.base64Encode(generatedMac)
            );

            Boolean matched = suppliedIsHex
                ? secureStringEquals(
                    expectedHex,
                    suppliedSignature.toLowerCase()
                )
                : secureStringEquals(
                    expectedBase64,
                    normalizedSuppliedBase64
                );

            if (matched) {
                return success(
                    'AUTHENTICATED',
                    'Webhook signature verified using compatible mode ' +
                    signingModes[i] + '.',
                    deliveryId
                );
            }
        }

        System.debug(
            LoggingLevel.WARN,
            'Compatible webhook signature validation failed. Body length: ' +
            (body == null ? 0 : body.length())
        );

        return failure(
            401,
            'INVALID_SIGNATURE',
            'The webhook signature is invalid.'
        );
    }

    @TestVisible
    private static AuthenticationResult authenticateLegacyApiKey(
        RestRequest request
    ) {
        if (request == null) {
            return null;
        }

        String incomingKey = getFirstHeaderIgnoreCase(
            request,
            new List<String>{
                'x-api-key',
                'X-API-Key',
                'Api-Key'
            }
        );

        if (String.isBlank(incomingKey)) {
            return null;
        }

        try {
            String configuredKey;

            if (Test.isRunningTest() && testLegacyApiKey != null) {
                configuredKey = testLegacyApiKey;
            } else {
                List<Webhook_Auth__mdt> authRows = [
                    SELECT ApiKey__c
                    FROM Webhook_Auth__mdt
                    WHERE DeveloperName = 'Default'
                    LIMIT 1
                ];

                configuredKey = authRows.isEmpty()
                    ? null
                    : authRows[0].ApiKey__c;
            }

            if (String.isBlank(configuredKey)) {
                return failure(
                    500,
                    'AUTHENTICATION_NOT_CONFIGURED',
                    'The legacy webhook API key is not configured.'
                );
            }

            String suppliedKey = incomingKey.trim();
            configuredKey = configuredKey.trim();

            if (!secureStringEquals(configuredKey, suppliedKey)) {
                return failure(
                    401,
                    'INVALID_API_KEY',
                    'The webhook API key is invalid.'
                );
            }

            return success(
                'AUTHENTICATED_LEGACY_API_KEY',
                'Webhook API key verified.',
                getFirstHeaderIgnoreCase(
                    request,
                    new List<String>{
                        'X-FreightGraph-Delivery-Id',
                        'X-Webhook-Delivery-Id',
                        'X-Delivery-Id',
                        'X-Request-Id'
                    }
                )
            );

        } catch (Exception e) {
            return failure(
                500,
                'AUTHENTICATION_NOT_CONFIGURED',
                'The legacy webhook API key could not be read.'
            );
        }
    }

    @TestVisible
    private static AuthenticationResult verifyHexSignature(
        String suppliedSignatureHex,
        String timestampHeader,
        String body,
        String secret,
        String deliveryId
    ) {
        List<String> signingPayloads = buildSigningPayloads(
            timestampHeader,
            body
        );

        List<String> signingModes = buildSigningModes();

        for (Integer i = 0; i < signingPayloads.size(); i++) {
            String expectedSignatureHex =
                EncodingUtil.convertToHex(
                    generateMac(signingPayloads[i], secret)
                ).toLowerCase();

            if (
                secureStringEquals(
                    expectedSignatureHex,
                    suppliedSignatureHex
                )
            ) {
                return success(
                    'AUTHENTICATED',
                    'Webhook signature verified using mode ' +
                    signingModes[i] + '.',
                    deliveryId
                );
            }
        }

        System.debug(
            LoggingLevel.WARN,
            'Webhook signature did not match any supported signing mode. ' +
            'Body length: ' +
            (body == null ? 0 : body.length())
        );

        return failure(
            401,
            'INVALID_SIGNATURE',
            'The webhook signature is invalid.'
        );
    }

    @TestVisible
    private static List<String> buildSigningPayloads(
        String timestampHeader,
        String body
    ) {
        String safeBody = body == null ? '' : body;

        return new List<String>{
            timestampHeader + '.' + safeBody,
            timestampHeader + safeBody,
            safeBody
        };
    }

    @TestVisible
    private static List<String> buildSigningModes() {
        return new List<String>{
            'timestamp_dot_body',
            'timestamp_body',
            'body_only'
        };
    }

    @TestVisible
    private static Blob generateMac(
        String contentToSign,
        String secret
    ) {
        return Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(contentToSign),
            Blob.valueOf(secret == null ? '' : secret)
        );
    }

    @TestVisible
    private static AuthenticationResult validateReplayWindow(
        Long webhookTimestampSeconds,
        Integer replayWindowSeconds
    ) {
        if (webhookTimestampSeconds == null) {
            return failure(
                401,
                'INVALID_TIMESTAMP',
                'The webhook timestamp is invalid.'
            );
        }

        Long currentTimestamp = getCurrentTimestamp();
        Long timestampDifference =
            currentTimestamp - webhookTimestampSeconds;

        if (timestampDifference < 0) {
            timestampDifference = -timestampDifference;
        }

        if (timestampDifference > replayWindowSeconds) {
            return failure(
                401,
                'STALE_WEBHOOK',
                'The webhook timestamp is outside the allowed window.'
            );
        }

        return null;
    }

    @TestVisible
    private static Boolean isHexSha256(String value) {
        if (String.isBlank(value) || value.length() != 64) {
            return false;
        }

        return value.toLowerCase().replaceAll('[0-9a-f]', '') == '';
    }

    @TestVisible
    private static String cleanCompatibleSignature(
        String signatureHeader
    ) {
        if (String.isBlank(signatureHeader)) {
            return null;
        }

        String cleaned = signatureHeader.trim();
        String lower = cleaned.toLowerCase();

        for (String prefix : new List<String>{
            'sha256=',
            'sha256:',
            'hmac-sha256=',
            'hmac-sha256:',
            'v1='
        }) {
            if (lower.startsWith(prefix)) {
                return cleaned.substring(prefix.length()).trim();
            }
        }

        return cleaned;
    }

    @TestVisible
    private static String normalizeBase64(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        return value
            .trim()
            .replace('-', '+')
            .replace('_', '/')
            .replace('=', '');
    }

    @TestVisible
    private static Long parseTimestampSeconds(String timestampHeader) {
        if (String.isBlank(timestampHeader)) {
            return null;
        }

        try {
            return normalizeTimestampForReplayCheck(
                Long.valueOf(timestampHeader.trim())
            );
        } catch (Exception ignoredNumericTimestamp) {
            // Continue with ISO-8601 parsing.
        }

        try {
            Datetime parsedTimestamp = (Datetime) JSON.deserialize(
                JSON.serialize(timestampHeader.trim()),
                Datetime.class
            );

            return parsedTimestamp == null
                ? null
                : parsedTimestamp.getTime() / 1000;
        } catch (Exception ignoredIsoTimestamp) {
            return null;
        }
    }

    @TestVisible
    private static Boolean secureStringEquals(
        String expectedValue,
        String suppliedValue
    ) {
        if (
            expectedValue == null ||
            suppliedValue == null ||
            expectedValue.length() != suppliedValue.length()
        ) {
            return false;
        }

        Integer differences = 0;

        for (
            Integer index = 0;
            index < expectedValue.length();
            index++
        ) {
            if (
                expectedValue.substring(index, index + 1) !=
                suppliedValue.substring(index, index + 1)
            ) {
                differences++;
            }
        }

        return differences == 0;
    }

    private static Configuration getConfiguration() {
        if (
            Test.isRunningTest() &&
            !String.isBlank(testSecret)
        ) {
            Configuration testConfiguration =
                new Configuration();

            testConfiguration.secret = testSecret.trim();
            testConfiguration.replayWindowSeconds =
                testReplayWindow == null
                ? DEFAULT_REPLAY_WINDOW
                : testReplayWindow;

            return testConfiguration;
        }

        List<FreightGraph_Email_Extraction__mdt> metadataRecords = [
            SELECT Active__c,
                   Secret__c,
                   Replay_Window_Seconds__c
            FROM FreightGraph_Email_Extraction__mdt
            WHERE DeveloperName = :CONFIG_DEVELOPER_NAME
            LIMIT 1
        ];

        if (metadataRecords.isEmpty()) {
            throw new AuthenticationConfigurationException(
                'Webhook authentication metadata record "' +
                CONFIG_DEVELOPER_NAME +
                '" was not found.'
            );
        }

        FreightGraph_Email_Extraction__mdt metadata =
            metadataRecords[0];

        if (!metadata.Active__c) {
            throw new AuthenticationConfigurationException(
                'Webhook authentication is not active.'
            );
        }

        if (String.isBlank(metadata.Secret__c)) {
            throw new AuthenticationConfigurationException(
                'The webhook secret is empty.'
            );
        }

        Configuration configuration = new Configuration();
        configuration.secret = metadata.Secret__c.trim();
        configuration.replayWindowSeconds =
            metadata.Replay_Window_Seconds__c == null
            ? DEFAULT_REPLAY_WINDOW
            : metadata.Replay_Window_Seconds__c.intValue();

        if (configuration.replayWindowSeconds <= 0) {
            configuration.replayWindowSeconds =
                DEFAULT_REPLAY_WINDOW;
        }

        return configuration;
    }

    @TestVisible
    private static String getFirstHeaderIgnoreCase(
        RestRequest request,
        List<String> requestedHeaders
    ) {
        if (requestedHeaders == null) {
            return null;
        }

        for (String requestedHeader : requestedHeaders) {
            String value = getHeaderIgnoreCase(
                request,
                requestedHeader
            );

            if (!String.isBlank(value)) {
                return value;
            }
        }

        return null;
    }

    @TestVisible
    private static String getHeaderIgnoreCase(
        RestRequest request,
        String requestedHeader
    ) {
        if (
            request == null ||
            request.headers == null ||
            String.isBlank(requestedHeader)
        ) {
            return null;
        }

        for (String headerName : request.headers.keySet()) {
            if (headerName.equalsIgnoreCase(requestedHeader)) {
                return request.headers.get(headerName);
            }
        }

        return null;
    }

    @TestVisible
    private static Long normalizeTimestampForReplayCheck(
        Long timestamp
    ) {
        if (timestamp == null) {
            return null;
        }

        Long absoluteTimestamp =
            timestamp < 0 ? -timestamp : timestamp;

        if (absoluteTimestamp >= 100000000000L) {
            return timestamp / 1000;
        }

        return timestamp;
    }

    @TestVisible
    private static Long getCurrentTimestamp() {
        if (
            Test.isRunningTest() &&
            testCurrentTimestamp != null
        ) {
            return testCurrentTimestamp;
        }

        return Datetime.now().getTime() / 1000;
    }

    @TestVisible
    private static AuthenticationResult success(
        String code,
        String message,
        String deliveryId
    ) {
        AuthenticationResult result = new AuthenticationResult();
        result.valid = true;
        result.statusCode = 200;
        result.code = code;
        result.message = message;
        result.deliveryId = deliveryId;
        return result;
    }

    @TestVisible
    private static AuthenticationResult failure(
        Integer statusCode,
        String code,
        String message
    ) {
        AuthenticationResult result = new AuthenticationResult();
        result.valid = false;
        result.statusCode = statusCode;
        result.code = code;
        result.message = message;
        return result;
    }

    private class Configuration {
        public String secret;
        public Integer replayWindowSeconds;
    }

    private class AuthenticationConfigurationException
        extends Exception {
    }
}