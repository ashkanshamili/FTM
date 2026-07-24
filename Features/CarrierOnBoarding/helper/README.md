FTM Carrier Onboarding Deployment

Overview

This package deploys the FTM Carrier Onboarding form and its related Salesforce metadata.

1. Get the Code from FTM GitHub

Open the FTM GitHub repository.

Locate the carrierOnboarding source code and all related files.

Clone or download the code into Visual Studio Code.

2. Connect VS Code to the Salesforce Org

Open the Salesforce DX project in Visual Studio Code.

Authorize the target Salesforce org.

Confirm that VS Code is connected to the correct org.

Deploy the complete Carrier Onboarding package and its dependencies.

3. Configure the Salesforce Site

Go to Setup → Sites.

Open the Site used for Carrier Onboarding.

Open Site Visualforce Pages → Edit.

Add CarrierOnboardingSiteHome.

Open Public Access Settings.

Under Enabled Apex Class Access, add:

CarrierOnboardingController

CarrierOnboardingActionHandler

CarrierOnboardingUploadJob

Confirm that CarrierOnboardingSiteHome is enabled under Visualforce Page Access.

Give the Site Access to the Carrier Onboarding Platform Event

From the same Site Public Access Settings:

Open Object Settings.

Find and open:

Carrier_Onboarding_Action__e

Enable Read and Create access.

Give the Site Guest User Read Access and Edit Access to all fields used on Carrier_Onboarding_Action__e.

Save the profile.

The Create permission is required because the Carrier Onboarding process publishes this Platform Event for document upload and onboarding actions. If this access is missing, submission, document processing, or related onboarding actions may fail.

The package includes a focused profile file named:

Portal Site Profile

This profile grants the Site Guest User access to the Carrier Onboarding Apex classes, Visualforce page, Carrier object, Carrier_Onboarding_Action__e Platform Event, and all fields used by the form. If the target Site uses a different Guest User profile name, apply the same permissions manually to that Site's Public Access Settings profile.

4. Give Carrier Object and Field Access

From the Site's Public Access Settings:

Open Object Settings → Carrier.

Enable Read, Create, and Edit.

Enable Read Access and Edit Access for every Carrier field used by the onboarding form.

Pay special attention to the managed fields beginning with FreightTM__, including FreightTM__On_boarding_Status__c.

Save the profile.

The included Portal Site Profile metadata sets Read/Edit access for the fields used by the form and sets viewAllFields for the Carrier object. Salesforce does not permit Edit Access on formula, system-managed, or otherwise read-only fields.

5. Configure the Managed On-boarding Status Picklist

The Carrier Onboarding code contains the following exact managed picklist API values:

New
Packet Sent
Paperwork Signed
Not Complete
Compliant
Draft
Submitted
Agreement Pending
Documents Pending
Compliance Review
Approved
Rejected
Expired / Needs Update
Ready for Loads

The main form submission uses Submitted. Document and signature processing also uses Not Complete, Paperwork Signed, and Documents Pending.

Because FreightTM__On_boarding_Status__c is a managed restricted picklist, the package cannot redefine its managed values in a subscriber org. The values are included as exact constants in the Apex code, but the target org must make them available to the Carrier record type.

To configure this:

Go to Setup → Object Manager → Carrier → Record Types.

Open every Carrier record type that can be used by the Site Guest User.

Find On-boarding Status and click Edit.

Move all required values, especially Submitted, into Selected Values.

Save.

In the Site Guest User profile, verify the default Carrier record type.

Restricted Picklist Error

Save failed: On-boarding Status: bad value for restricted picklist field: Submitted

This normally means Submitted exists on the managed field but is not available to the Carrier record type used during the public submission. The updated Apex first uses Submitted. If Salesforce rejects it for the active record type, the code retries with an active fallback so the Carrier data is not lost. The correct long-term fix is still to make Submitted available to the applicable Carrier record type.

6. Open the Public Carrier Onboarding Page

After deployment and Site permission setup, open:

https://wise-koala-63tngo-dev-ed.trailblaze.my.salesforce-sites.com/CarrierOnboardingSiteHome

The Carrier Onboarding page should open publicly.

