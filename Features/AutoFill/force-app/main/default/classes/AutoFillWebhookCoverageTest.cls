@IsTest
private class AutoFillWebhookCoverageTest {

    @IsTest
    static void helperMethodsCoverDirectAndCompatibilityPayloads() {
        Map<String, Object> direct = new Map<String, Object>{
            'SalesforceObjectType' => 'Task',
            'ExtractedFields' => new Map<String, Object>{
                'Subject' => 'Direct payload'
            }
        };
        Map<String, Object> prepared = AutoFillWebhook.preparePayload(direct);
        System.assertEquals(direct, prepared);
        System.assertEquals('Webhook', prepared.get('AutoFillSource'));

        Map<String, Object> explicitSource = new Map<String, Object>{
            'ParentObject' => 'Task',
            'Source' => 'Email',
            'ExtractedFields' => new Map<String, Object>{
                'Subject' => 'Existing source'
            }
        };
        System.assertEquals(
            'Email',
            AutoFillWebhook.preparePayload(explicitSource).get('Source')
        );
        System.assertEquals(false, explicitSource.containsKey('AutoFillSource'));

        Map<String, Object> compatibility = AutoFillWebhook.preparePayload(
            new Map<String, Object>{
                'Success' => true,
                'LoadDetails' => new Map<String, Object>{
                    'LoadId' => 'legacy-webhook-coverage',
                    'Origin' => 'Irvine',
                    'Destination' => 'Phoenix'
                }
            }
        );
        System.assertEquals(
            'FreightTM__Load__c',
            compatibility.get('SalesforceObjectType')
        );
        System.assert(
            compatibility.get('ExtractedFields') instanceof Map<String, Object>
        );

        System.assertEquals(false, AutoFillWebhook.isUsableObjectApiName(null));
        System.assertEquals(false, AutoFillWebhook.isUsableObjectApiName(' null '));
        System.assertEquals(true, AutoFillWebhook.isUsableObjectApiName('Task'));
        System.assertEquals(
            null,
            AutoFillWebhook.getDirectValueIgnoreCase(null, null)
        );
        System.assertEquals(
            'value',
            AutoFillWebhook.getDirectValueIgnoreCase(
                new Map<String, Object>{ 'MiXeD' => 'value' },
                new Set<String>{ 'mixed' }
            )
        );
        System.assertEquals(
            null,
            AutoFillWebhook.getDirectValueIgnoreCase(
                new Map<String, Object>{ 'Other' => 'value' },
                new Set<String>{ 'missing' }
            )
        );

        AutoFillWebhook.WebhookResponse created =
            AutoFillWebhook.buildSuccess(null, true);
        System.assertEquals(true, created.success);
        System.assertEquals('CREATED', created.code);

        AutoFillWebhook.WebhookResponse reused =
            AutoFillWebhook.buildSuccess(null, false);
        System.assertEquals('ALREADY_PROCESSED', reused.code);

        AutoFillWebhook.WebhookResponse error =
            AutoFillWebhook.buildError('TEST_ERROR', 'Test message');
        System.assertEquals(false, error.success);
        System.assertEquals('TEST_ERROR', error.code);
        System.assertEquals('Test message', error.message);
    }

    @IsTest
    static void handlePostCreatesResponseWhenRestContextResponseIsNull() {
        RestContext.request = null;
        RestContext.response = null;

        AutoFillWebhook.WebhookResponse result = AutoFillWebhook.handlePost();

        System.assertNotEquals(null, RestContext.response);
        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(false, result.success);
        System.assertEquals('EMPTY_BODY', result.code);
    }
}