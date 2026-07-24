FreightGraph AutoFill Installation

This guide assumes FTM is already installed in the Salesforce org.

1. Add the complete AutoFill feature

From the FTM GitHub repository, copy all files inside the AutoFill feature folder into the matching folders of the Salesforce project open in VS Code.

Keep the same Salesforce DX folder structure.

Do not copy individual classes one by one, and do not deploy the complete org repository.

2. Deploy the complete AutoFill package

Deploy all AutoFill files together:

sf project deploy start --manifest manifest/package.xml --target-org YOUR_ORG_ALIAS --wait 90

You can also right-click the AutoFill feature folder in VS Code and select:

SFDX: Deploy Source to Org

Only deploy the files added for AutoFill.

3. Complete the required configuration

After deployment, complete these items.

FreightGraph credentials

Go to:

Setup → Custom Metadata Types → Freight Auth Credentials → Manage Records

Open the Default record and enter the FreightGraph username and password.

If the Default record does not exist, create it with the name:

Default

AutoFill and webhook configuration

Go to:

Setup → Custom Metadata Types

Check these records:

FreightGraph Email Extraction

Webhook Authentication

Enter the correct API URL, API key, and webhook secret supplied for the customer org.

If either record does not exist, create a record named Default.

Use this webhook path:

/services/apexrest/freightgraph/autofill-email-extraction

Load Trigger

Open the existing LoadTrigger.

Confirm that it calls:

FreightLoadSyncHandler.syncCreated(Trigger.new);
FreightLoadSyncHandler.syncUpdated(Trigger.new);
FreightLoadSyncHandler.syncDeleted(Trigger.old);

It must also call AutoFillRejectedLoadDeleteService after a Load update.

If the org already has a LoadTrigger, add these calls to the existing trigger. Do not create a second trigger with the same name.

If the org has no LoadTrigger, deploy the included trigger after confirming that its referenced classes exist.

4. Assign AutoFill access

Assign one of these Permission Sets to the required Salesforce users:

FreightGraph AutoFill User

FreightGraph AutoFill Admin

Path:

Setup → Users → Users → select the user → Permission Set Assignments → Edit Assignments

5. Add AutoFill as a separate Salesforce page

The package already contains the AutoFill page and tab.

Go to:

Setup → App Manager → FTM Lightning App → Edit → Navigation Items

Move AutoFill to Selected Items, then save.

Open the FTM app and confirm that the AutoFill tab appears.

Only if the AutoFill page is missing

Create it manually:

Go to Setup → Lightning App Builder.

Click New.

Select App Page.

Name the page AutoFill.

Select a one-column layout.

Add the loadEmailExtractorAction component.

Save and activate the page.

Add the AutoFill tab to the FTM app navigation.

6. Optional Load record panel

To show AutoFill status directly on a Load record:

Open a Load record.

Click Gear → Edit Page.

Add the AutoFill Load Status Panel component.

Save and activate the page.

7. Final check

Confirm that:

AutoFill opens from the FTM navigation.

The user has the correct Permission Set.

FreightGraph credentials are configured.

The webhook secret and API URL are configured.

The Load trigger contains the AutoFill and FreightGraph sync calls.

A test document can create or update a Load successfully.