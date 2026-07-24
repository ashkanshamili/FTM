@IsTest
private class AutoFillWebhookAuthenticatorCoverageTest {
    private static final String SECRET = 'coverage-secret';
    private static final Long NOW_SECONDS = 1716292845L;

    private static void configure() {
        AutoFillWebhookAuthenticator.testSecret = SECRET;
        AutoFillWebhookAuthenticator.testReplayWindow = 300;
        AutoFillWebhookAuthenticator.testCurrentTimestamp = NOW_SECONDS;
        AutoFillWebhookAuthenticator.testLegacyApiKey = null;
    }

    private static String hexMac(String payload) {
        return EncodingUtil.convertToHex(
            Crypto.generateMac(
                'HmacSHA256',
                Blob.valueOf(payload),
                Blob.valueOf(SECRET)
            )
        ).toLowerCase();
    }

    private static String base64Mac(String payload) {
        return EncodingUtil.base64Encode(
            Crypto.generateMac(
                'HmacSHA256',
                Blob.valueOf(payload),
                Blob.valueOf(SECRET)
            )
        );
    }

    @IsTest
    static void compatibleHmacAcceptsAlternateHeadersAndSigningModes() {
        configure();
        String body = '{"Success":true}';
        String timestamp = String.valueOf(NOW_SECONDS);

        RestRequest timestampBodyRequest = new RestRequest();
        timestampBodyRequest.addHeader('X-Webhook-Timestamp', timestamp);
        timestampBodyRequest.addHeader(
            'X-Signature',
            'sha256:' + hexMac(timestamp + body)
        );
        timestampBodyRequest.addHeader('X-Request-Id', 'coverage-delivery-1');

        AutoFillWebhookAuthenticator.AuthenticationResult timestampBodyResult =
            AutoFillWebhookAuthenticator.authenticateCompatibleHmac(
                timestampBodyRequest,
                body
            );

        System.assertEquals(true, timestampBodyResult.valid);
        System.assertEquals('coverage-delivery-1', timestampBodyResult.deliveryId);
        System.assert(timestampBodyResult.message.contains('timestamp_body'));

        String urlSafeBase64 = base64Mac(body)
            .replace('+', '-')
            .replace('/', '_')
            .replace('=', '');
        RestRequest bodyOnlyRequest = new RestRequest();
        bodyOnlyRequest.addHeader('X-Timestamp', timestamp + '000');
        bodyOnlyRequest.addHeader(
            'X-Hub-Signature-256',
            'v1=' + urlSafeBase64
        );

        AutoFillWebhookAuthenticator.AuthenticationResult bodyOnlyResult =
            AutoFillWebhookAuthenticator.authenticateCompatibleHmac(
                bodyOnlyRequest,
                body
            );

        System.assertEquals(true, bodyOnlyResult.valid);
        System.assert(bodyOnlyResult.message.contains('body_only'));
    }

    @IsTest
    static void compatibleHmacCoversFailuresAndIsoTimestamp() {
        configure();
        String body = '{}';
        String isoTimestamp = '2024-05-21T12:00:45.000Z';
        AutoFillWebhookAuthenticator.testCurrentTimestamp =
            Datetime.valueOfGmt('2024-05-21 12:00:45').getTime() / 1000;

        RestRequest emptySignature = new RestRequest();
        emptySignature.addHeader('X-Webhook-Timestamp', isoTimestamp);
        emptySignature.addHeader('X-Webhook-Signature', 'sha256=   ');
        System.assertEquals(
            'INVALID_SIGNATURE_FORMAT',
            AutoFillWebhookAuthenticator.authenticateCompatibleHmac(
                emptySignature,
                body
            ).code
        );

        RestRequest invalidTimestamp = new RestRequest();
        invalidTimestamp.addHeader('X-Timestamp', 'not-a-time');
        invalidTimestamp.addHeader('X-Signature', 'anything');
        System.assertEquals(
            'INVALID_TIMESTAMP',
            AutoFillWebhookAuthenticator.authenticateCompatibleHmac(
                invalidTimestamp,
                body
            ).code
        );

        RestRequest wrongSignature = new RestRequest();
        wrongSignature.addHeader('X-Timestamp', isoTimestamp);
        wrongSignature.addHeader(
            'X-Signature',
            EncodingUtil.base64Encode(Blob.valueOf('wrong-signature'))
        );
        System.assertEquals(
            'INVALID_SIGNATURE',
            AutoFillWebhookAuthenticator.authenticateCompatibleHmac(
                wrongSignature,
                body
            ).code
        );

        System.assertEquals(
            'INVALID_REQUEST',
            AutoFillWebhookAuthenticator.authenticateCompatibleHmac(
                null,
                body
            ).code
        );
    }

    @IsTest
    static void legacyApiKeySupportsValidInvalidAndMissingConfiguration() {
        configure();
        RestRequest request = new RestRequest();
        request.addHeader('x-api-key', 'legacy-secret');
        request.addHeader('X-Delivery-Id', 'legacy-delivery');

        AutoFillWebhookAuthenticator.testLegacyApiKey = 'legacy-secret';
        AutoFillWebhookAuthenticator.AuthenticationResult valid =
            AutoFillWebhookAuthenticator.authenticateWebhook(request, '{}');
        System.assertEquals(true, valid.valid);
        System.assertEquals('AUTHENTICATED_LEGACY_API_KEY', valid.code);
        System.assertEquals('legacy-delivery', valid.deliveryId);

        AutoFillWebhookAuthenticator.testLegacyApiKey = 'different-secret';
        AutoFillWebhookAuthenticator.AuthenticationResult invalid =
            AutoFillWebhookAuthenticator.authenticateLegacyApiKey(request);
        System.assertEquals(false, invalid.valid);
        System.assertEquals('INVALID_API_KEY', invalid.code);

        AutoFillWebhookAuthenticator.testLegacyApiKey = '   ';
        AutoFillWebhookAuthenticator.AuthenticationResult unconfigured =
            AutoFillWebhookAuthenticator.authenticateLegacyApiKey(request);
        System.assertEquals(
            'AUTHENTICATION_NOT_CONFIGURED',
            unconfigured.code
        );

        System.assertEquals(
            null,
            AutoFillWebhookAuthenticator.authenticateLegacyApiKey(
                new RestRequest()
            )
        );
        System.assertEquals(
            null,
            AutoFillWebhookAuthenticator.authenticateLegacyApiKey(null)
        );
    }

    @IsTest
    static void helperMethodsCoverBoundaryBranches() {
        configure();

        System.assertEquals(
            new List<String>{ '10.body', '10body', 'body' },
            AutoFillWebhookAuthenticator.buildSigningPayloads('10', 'body')
        );
        System.assertEquals(
            new List<String>{ '10.', '10', '' },
            AutoFillWebhookAuthenticator.buildSigningPayloads('10', null)
        );
        System.assertEquals(
            3,
            AutoFillWebhookAuthenticator.buildSigningModes().size()
        );
        System.assertNotEquals(
            null,
            AutoFillWebhookAuthenticator.generateMac('content', SECRET)
        );

        System.assertEquals(
            false,
            AutoFillWebhookAuthenticator.isHexSha256(null)
        );
        System.assertEquals(
            false,
            AutoFillWebhookAuthenticator.isHexSha256('abc')
        );
        System.assertEquals(
            true,
            AutoFillWebhookAuthenticator.isHexSha256(
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' +
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
            )
        );

        System.assertEquals(
            null,
            AutoFillWebhookAuthenticator.cleanCompatibleSignature(null)
        );
        System.assertEquals(
            'abc',
            AutoFillWebhookAuthenticator.cleanCompatibleSignature(
                'HMAC-SHA256: abc'
            )
        );
        System.assertEquals(
            'plain',
            AutoFillWebhookAuthenticator.cleanCompatibleSignature(' plain ')
        );
        System.assertEquals(
            null,
            AutoFillWebhookAuthenticator.normalizeBase64(null)
        );
        System.assertEquals(
            'a+b/c',
            AutoFillWebhookAuthenticator.normalizeBase64('a-b_c==')
        );

        System.assertEquals(
            NOW_SECONDS,
            AutoFillWebhookAuthenticator.parseTimestampSeconds(
                String.valueOf(NOW_SECONDS) + '000'
            )
        );
        System.assertEquals(
            null,
            AutoFillWebhookAuthenticator.parseTimestampSeconds(null)
        );
        System.assertEquals(
            null,
            AutoFillWebhookAuthenticator.parseTimestampSeconds('bad')
        );

        System.assertEquals(
            'INVALID_TIMESTAMP',
            AutoFillWebhookAuthenticator.validateReplayWindow(null, 300).code
        );
        System.assertEquals(
            'STALE_WEBHOOK',
            AutoFillWebhookAuthenticator.validateReplayWindow(
                NOW_SECONDS + 301,
                300
            ).code
        );
        System.assertEquals(
            null,
            AutoFillWebhookAuthenticator.validateReplayWindow(
                NOW_SECONDS,
                300
            )
        );

        RestRequest request = new RestRequest();
        request.addHeader('x-custom-header', 'value');
        System.assertEquals(
            'value',
            AutoFillWebhookAuthenticator.getHeaderIgnoreCase(
                request,
                'X-Custom-Header'
            )
        );
        System.assertEquals(
            null,
            AutoFillWebhookAuthenticator.getHeaderIgnoreCase(null, 'x')
        );
        System.assertEquals(
            null,
            AutoFillWebhookAuthenticator.getHeaderIgnoreCase(request, null)
        );
        System.assertEquals(
            null,
            AutoFillWebhookAuthenticator.getFirstHeaderIgnoreCase(
                request,
                null
            )
        );
        System.assertEquals(
            null,
            AutoFillWebhookAuthenticator.getFirstHeaderIgnoreCase(
                request,
                new List<String>{ 'missing' }
            )
        );

        System.assertEquals(
            NOW_SECONDS,
            AutoFillWebhookAuthenticator.getCurrentTimestamp()
        );
        System.assertEquals(
            'OK',
            AutoFillWebhookAuthenticator.success('OK', 'done', 'id').code
        );
        System.assertEquals(
            418,
            AutoFillWebhookAuthenticator.failure(418, 'NO', 'no').statusCode
        );
    }

    @IsTest
    static void strictVerifierCoversAllSigningModesAndInvalidSignature() {
        configure();
        String timestamp = String.valueOf(NOW_SECONDS);
        String body = '{"test":true}';

        AutoFillWebhookAuthenticator.AuthenticationResult bodyOnly =
            AutoFillWebhookAuthenticator.verifyHexSignature(
                hexMac(body),
                timestamp,
                body,
                SECRET,
                'direct-delivery'
            );
        System.assertEquals(true, bodyOnly.valid);
        System.assert(bodyOnly.message.contains('body_only'));

        AutoFillWebhookAuthenticator.AuthenticationResult invalid =
            AutoFillWebhookAuthenticator.verifyHexSignature(
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' +
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                timestamp,
                body,
                SECRET,
                null
            );
        System.assertEquals('INVALID_SIGNATURE', invalid.code);
    }
}