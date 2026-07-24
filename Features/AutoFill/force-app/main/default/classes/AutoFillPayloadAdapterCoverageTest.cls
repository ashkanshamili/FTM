@IsTest
private class AutoFillPayloadAdapterCoverageTest {

    @IsTest
    static void normalizesNestedStringPayloadAndCanonicalValues() {
        Map<String, Object> nestedPayload = new Map<String, Object>{
            'Succeeded' => 'yes',
            'ParentObject' => 'shipment',
            'DocumentId' => 'adapter-doc-001',
            'DocType' => 'BOL',
            'OverallConfidence' => 0.91,
            'ClassificationConfidence' => 88,
            'IsComplete' => 'true',
            'RequiredFieldsMissing' => new List<Object>(),
            'Metadata' => new Map<String, Object>{ 'pipeline' => 'v2' },
            'AutoFillSource' => 'Email',
            'Fields' => new List<Object>{
                new Map<String, Object>{
                    'FieldName' => 'Origin',
                    'Value' => 'Austin',
                    'Confidence' => 95
                },
                new Map<String, Object>{
                    'Name' => 'Destination',
                    'Value' => 'Dallas'
                }
            }
        };
        Object rawPayload = new List<Object>{
            new Map<String, Object>{
                'Response' => JSON.serialize(nestedPayload)
            }
        };

        Map<String, Object> normalized =
            AutoFillWebhookPayloadAdapter.normalize(rawPayload);
        Map<String, Object> fields =
            (Map<String, Object>) normalized.get('ExtractedFields');

        System.assertEquals(true, normalized.get('Success'));
        System.assertEquals(
            'FreightTM__Load__c',
            normalized.get('SalesforceObjectType')
        );
        System.assertEquals('adapter-doc-001', normalized.get('ItemId'));
        System.assertEquals('BOL', normalized.get('DetectedDocumentType'));
        System.assertEquals(0.91, normalized.get('Confidence'));
        System.assertEquals(88, normalized.get('ClassificationConfidence'));
        System.assertEquals('true', normalized.get('AllFieldsDetected'));
        System.assertEquals('Email', normalized.get('AutoFillSource'));
        System.assert(fields.containsKey('Origin'));
        System.assert(fields.containsKey('Destination'));
        System.assert(fields.get('Origin') instanceof Map<String, Object>);
    }

    @IsTest
    static void convertsLegacyLoadEnvelopeAndDefaultsWebhookSource() {
        Map<String, Object> normalized =
            AutoFillWebhookPayloadAdapter.normalize(
                new Map<String, Object>{
                    'Success' => true,
                    'LoadDetails' => new Map<String, Object>{
                        'LoadId' => 'legacy-001',
                        'Origin' => 'Irvine',
                        'OriginState' => 'CA',
                        'Destination' => 'Phoenix',
                        'DestinationState' => 'AZ',
                        'PickupDate' => String.valueOf(Date.today()),
                        'DeliveryDate' => String.valueOf(Date.today().addDays(1)),
                        'EquipmentType' => 'Van',
                        'EmptyValue' => 'null',
                        'CustomLegacyValue' => 'kept'
                    }
                }
            );

        Map<String, Object> fields =
            (Map<String, Object>) normalized.get('ExtractedFields');

        System.assertEquals(
            'FreightTM__Load__c',
            normalized.get('SalesforceObjectType')
        );
        System.assertEquals('Webhook', normalized.get('AutoFillSource'));
        System.assertEquals(
            'Irvine',
            fields.get('FreightTM__Pickup_City__c')
        );
        System.assertEquals(
            'Phoenix',
            fields.get('FreightTM__Delivery_City__c')
        );
        System.assertEquals('kept', fields.get('CustomLegacyValue'));
        System.assertEquals(false, fields.containsKey('EmptyValue'));
    }

    @IsTest
    static void rejectsFailureAndMissingFieldPayloads() {
        Boolean failureThrown = false;
        try {
            AutoFillWebhookPayloadAdapter.normalize(
                new Map<String, Object>{
                    'Success' => false,
                    'ErrorMessage' => 'Extraction failed in coverage test'
                }
            );
        } catch (AutoFillWebhookPayloadAdapter.PayloadException e) {
            failureThrown = true;
            System.assertEquals(
                'Extraction failed in coverage test',
                e.getMessage()
            );
        }
        System.assertEquals(true, failureThrown);

        Boolean defaultFailureThrown = false;
        try {
            AutoFillWebhookPayloadAdapter.normalize(
                new Map<String, Object>{
                    'Succeeded' => 'no',
                    'Payload' => new Map<String, Object>()
                }
            );
        } catch (AutoFillWebhookPayloadAdapter.PayloadException e) {
            defaultFailureThrown = true;
            System.assert(e.getMessage().contains('reported'));
        }
        System.assertEquals(true, defaultFailureThrown);

        for (Object invalidPayload : new List<Object>{
            null,
            'not-json',
            new Map<String, Object>{ 'Unrelated' => 'value' }
        }) {
            Boolean thrown = false;
            try {
                AutoFillWebhookPayloadAdapter.normalize(invalidPayload);
            } catch (AutoFillWebhookPayloadAdapter.PayloadException e) {
                thrown = true;
            }

        }
    }

    @IsTest
    static void helperMethodsCoverSearchConversionAndMergeBranches() {
        System.assertEquals(
            null,
            AutoFillWebhookPayloadAdapter.findPayloadCandidate(null, 0)
        );
        System.assertEquals(
            null,
            AutoFillWebhookPayloadAdapter.findPayloadCandidate(
                new Map<String, Object>(),
                7
            )
        );
        System.assertEquals(
            false,
            AutoFillWebhookPayloadAdapter.looksLikePayload(null)
        );
        System.assertEquals(
            false,
            AutoFillWebhookPayloadAdapter.looksLikePayload(
                new Map<String, Object>()
            )
        );
        System.assertEquals(
            true,
            AutoFillWebhookPayloadAdapter.looksLikePayload(
                new Map<String, Object>{
                    'Origin' => 'A',
                    'Destination' => 'B'
                }
            )
        );

        System.assertEquals(
            0,
            AutoFillWebhookPayloadAdapter.convertLegacyLoadFields(null).size()
        );
        Map<String, Object> converted =
            AutoFillWebhookPayloadAdapter.convertLegacyLoadFields(
                new Map<String, Object>{
                    'Origin' => 'A',
                    'Metadata' => 'ignored',
                    'Unknown_Field__c' => 'kept',
                    'Blank' => ' '
                }
            );
        System.assertEquals(
            'A',
            converted.get('FreightTM__Pickup_City__c')
        );
        System.assertEquals('kept', converted.get('Unknown_Field__c'));
        System.assertEquals(false, converted.containsKey('Metadata'));
        System.assert(
            AutoFillWebhookPayloadAdapter.getLegacyLoadFieldMappings().size() > 20
        );

        Map<String, Object> extractedFromRows =
            AutoFillWebhookPayloadAdapter.extractFieldsMap(
                new List<Object>{
                    'skip',
                    new Map<String, Object>{ 'Value' => 'no name' },
                    new Map<String, Object>{ 'Name' => '  ', 'Value' => 'blank' },
                    new Map<String, Object>{ 'Name' => 'Simple', 'Value' => 1 },
                    new Map<String, Object>{ 'Label' => 'Whole Row' },
                    JSON.serialize(
                        new Map<String, Object>{
                            'Key' => 'Scored',
                            'Text' => 'value',
                            'Score' => 77
                        }
                    )
                }
            );
        System.assertEquals(3, extractedFromRows.size());
        System.assertEquals(1, extractedFromRows.get('Simple'));
        System.assert(
            extractedFromRows.get('Whole Row') instanceof Map<String, Object>
        );
        System.assert(
            extractedFromRows.get('Scored') instanceof Map<String, Object>
        );
        System.assertEquals(
            0,
            AutoFillWebhookPayloadAdapter.extractFieldsMap('plain').size()
        );

        Map<String, Object> target = new Map<String, Object>{
            'Pickup City' => 'original'
        };
        AutoFillWebhookPayloadAdapter.mergeFields(
            target,
            new Map<String, Object>{
                'pickup-city' => 'duplicate',
                'Delivery City' => 'new',
                ' ' => 'ignored'
            }
        );
        System.assertEquals('original', target.get('Pickup City'));
        System.assertEquals('new', target.get('Delivery City'));
        AutoFillWebhookPayloadAdapter.mergeFields(null, target);
        AutoFillWebhookPayloadAdapter.mergeFields(target, null);

        Map<String, Object> copyTarget = new Map<String, Object>{
            'ItemId' => 'existing'
        };
        AutoFillWebhookPayloadAdapter.copyCanonicalValue(
            new Map<String, Object>{ 'DocumentId' => 'new' },
            copyTarget,
            'ItemId',
            new Set<String>{ 'documentid' }
        );
        System.assertEquals('existing', copyTarget.get('ItemId'));
        AutoFillWebhookPayloadAdapter.copyCanonicalValue(
            new Map<String, Object>{ 'DocType' => 'POD' },
            copyTarget,
            'DetectedDocumentType',
            new Set<String>{ 'doctype' }
        );
        System.assertEquals('POD', copyTarget.get('DetectedDocumentType'));
        AutoFillWebhookPayloadAdapter.copyCanonicalValue(
            null,
            copyTarget,
            'X',
            new Set<String>{ 'x' }
        );
    }

    @IsTest
    static void helperMethodsCoverObjectResolutionAndUtilityBranches() {
        Map<String, Object> metadataRoot = new Map<String, Object>{
            'Metadata' => new Map<String, Object>{
                'ObjectGraph' => new Map<String, Object>{
                    'Parent' => new Map<String, Object>{
                        'ObjectApiName' => 'Task'
                    }
                }
            }
        };
        System.assertEquals(
            'Task',
            AutoFillWebhookPayloadAdapter.resolveExplicitObjectApiName(
                metadataRoot,
                metadataRoot
            )
        );
        System.assertEquals(
            null,
            AutoFillWebhookPayloadAdapter.resolveExplicitObjectApiName(
                new Map<String, Object>(),
                new Map<String, Object>()
            )
        );
        System.assertEquals(
            'FreightTM__Load__c',
            AutoFillWebhookPayloadAdapter.canonicalizeObjectApiName(' Loads ')
        );
        System.assertEquals(
            'Task',
            AutoFillWebhookPayloadAdapter.canonicalizeObjectApiName(' Task ')
        );
        System.assertEquals(
            null,
            AutoFillWebhookPayloadAdapter.canonicalizeObjectApiName(null)
        );

        System.assertEquals(
            true,
            AutoFillWebhookPayloadAdapter.isLegacyLoadEnvelope(
                new Map<String, Object>(),
                new Map<String, Object>(),
                new Map<String, Object>{ 'Origin' => 'A' },
                new Map<String, Object>()
            )
        );
        System.assertEquals(
            true,
            AutoFillWebhookPayloadAdapter.isLegacyLoadEnvelope(
                new Map<String, Object>{ 'PipelineVersion' => '2' },
                new Map<String, Object>(),
                null,
                new Map<String, Object>()
            )
        );
        System.assertEquals(
            true,
            AutoFillWebhookPayloadAdapter.isLegacyLoadEnvelope(
                new Map<String, Object>(),
                new Map<String, Object>(),
                null,
                new Map<String, Object>{ 'Pickup City' => 'A' }
            )
        );
        System.assertEquals(
            false,
            AutoFillWebhookPayloadAdapter.isLegacyLoadEnvelope(
                new Map<String, Object>(),
                new Map<String, Object>(),
                null,
                new Map<String, Object>{ 'Subject' => 'A' }
            )
        );

        Map<String, Object> original = new Map<String, Object>{
            'Nested' => new Map<String, Object>{ 'Value' => 1 }
        };
        Map<String, Object> cloned =
            AutoFillWebhookPayloadAdapter.deepCloneMap(original);
        ((Map<String, Object>) cloned.get('Nested')).put('Value', 2);
        System.assertEquals(
            1,
            ((Map<String, Object>) original.get('Nested')).get('Value')
        );
        System.assertEquals(
            0,
            AutoFillWebhookPayloadAdapter.deepCloneMap(null).size()
        );

        System.assert(
            AutoFillWebhookPayloadAdapter.decodeJsonValue('{"a":1}', 0)
            instanceof Map<String, Object>
        );
        System.assertEquals(
            'plain',
            AutoFillWebhookPayloadAdapter.decodeJsonValue('plain', 0)
        );
        System.assertEquals(
            '{bad',
            AutoFillWebhookPayloadAdapter.decodeJsonValue('{bad', 0)
        );
        System.assertEquals(
            '[1]',
            AutoFillWebhookPayloadAdapter.decodeJsonValue('[1]', 7)
        );
        System.assertEquals(
            5,
            AutoFillWebhookPayloadAdapter.decodeJsonValue(5, 0)
        );

        Map<String, Object> decodedMap = AutoFillWebhookPayloadAdapter.asMap(
            new List<Object>{ 'skip', '{"a":1}' }
        );
        System.assertNotEquals(null, decodedMap);
        System.assertEquals(1, decodedMap.get('a'));
        System.assertEquals(
            null,
            AutoFillWebhookPayloadAdapter.asMap('plain')
        );

        Map<String, Object> source = new Map<String, Object>{
            'Nested' => new List<Object>{
                new Map<String, Object>{ 'Requested-Key' => 'found' }
            }
        };
        System.assertEquals(
            'found',
            AutoFillWebhookPayloadAdapter.findFirstValue(
                source,
                new Set<String>{ 'requestedkey' },
                0
            )
        );
        System.assertEquals(
            null,
            AutoFillWebhookPayloadAdapter.findFirstValue(
                source,
                new Set<String>{ 'missing' },
                7
            )
        );
        System.assertEquals(
            null,
            AutoFillWebhookPayloadAdapter.findDirectValue(null, null)
        );
        System.assertEquals(
            null,
            AutoFillWebhookPayloadAdapter.findDirectMap(
                source,
                new Set<String>{ 'missing' }
            )
        );
        System.assertEquals(
            true,
            AutoFillWebhookPayloadAdapter.hasDirectKey(
                new Map<String, Object>{ 'Auto Fill Source' => 'Email' },
                'AutoFillSource'
            )
        );
        System.assertEquals(
            false,
            AutoFillWebhookPayloadAdapter.hasDirectKey(null, 'x')
        );
        System.assertEquals(
            false,
            AutoFillWebhookPayloadAdapter.hasDirectKey(source, null)
        );

        System.assertEquals(false, AutoFillWebhookPayloadAdapter.parseBoolean(null));
        System.assertEquals(true, AutoFillWebhookPayloadAdapter.parseBoolean(true));
        System.assertEquals(true, AutoFillWebhookPayloadAdapter.parseBoolean('completed'));
        System.assertEquals(false, AutoFillWebhookPayloadAdapter.parseBoolean('no'));
        System.assertEquals(true, AutoFillWebhookPayloadAdapter.isEmptyValue(null));
        System.assertEquals(true, AutoFillWebhookPayloadAdapter.isEmptyValue(' null '));
        System.assertEquals(true, AutoFillWebhookPayloadAdapter.isEmptyValue(new Map<String, Object>()));
        System.assertEquals(true, AutoFillWebhookPayloadAdapter.isEmptyValue(new List<Object>()));
        System.assertEquals(false, AutoFillWebhookPayloadAdapter.isEmptyValue(1));
        System.assertEquals('', AutoFillWebhookPayloadAdapter.normalizeKey(null));
        System.assertEquals('autofillsourcec', AutoFillWebhookPayloadAdapter.normalizeKey('AutoFill Source__c'));
    }
}