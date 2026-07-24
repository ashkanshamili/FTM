FTM Carrier Onboarding Deployment

Overview

This package deploys the FTM Carrier Onboarding form and its related Salesforce metadata.

Before deploying the package, you must replace the Guest User placeholder in the Carrier Sharing Rule with the exact Nickname of the Salesforce Site Guest User in the target org.

Do not enter the Guest User's display name, username, profile name, or Site label. Salesforce requires the Guest User's CommunityNickname value.

1. Get the Code from FTM GitHub

Open the FTM GitHub repository.

Locate the carrierOnboarding source code and all related files.

Clone or download the code into Visual Studio Code.

2. Find the Salesforce Site Guest User Nickname

The Sharing Rule must contain the Nickname of the Guest User connected to the Carrier Onboarding Salesforce Site.

Method A: Find it from Salesforce Setup

Go to Setup → Sites.

Open the Salesforce Site used for Carrier Onboarding.

Click Public Access Settings.

Click View Users.

Open the Site Guest User.

On the User Detail page, find the field named:

Nickname

Copy the exact Nickname value.

The User normally has a name similar to:

Portal Site Site Guest User

That is only the User's display name. Do not place that display name in the Sharing Rule unless it is also the exact value shown in the Nickname field.

Method B: Find it with Developer Console

Open:

Developer Console → Query Editor

First, find the Site and its Guest User ID:

SELECT Id, Name, MasterLabel, GuestUserId
FROM Site

Find the Carrier Onboarding Site and copy its GuestUserId.

Then run:

SELECT Id,
       Name,
       Username,
       CommunityNickname,
       Profile.Name
FROM User
WHERE Id = 'PASTE_GUEST_USER_ID_HERE'

Copy the value returned in:

CommunityNickname

CommunityNickname is the value required by the Sharing Rule's <guestUser> field.

3. Replace the Guest User Nickname in the Sharing Rule

Before deployment, open this file in Visual Studio Code:

force-app/main/default/sharingRules/FreightTM__Carrier__c.sharingRules-meta.xml

Find:

<guestUser>REPLACE_WITH_SITE_GUEST_USER_NICKNAME</guestUser>

Replace only the placeholder with the exact Nickname copied from Salesforce.

Example:

<guestUser>PortalSiteGuest</guestUser>

Do not use values such as:

Portal Site Site Guest User
guest.user@company.com
Portal Site Profile
Carrier Onboarding

unless one of them is the exact value displayed in the User's Nickname field.

Save the XML file before deployment.

If the target org uses a different Salesforce Site, repeat this step using that Site's own Guest User Nickname.

4. Connect VS Code to the Salesforce Org

Open the Salesforce DX project in Visual Studio Code.

Authorize the target Salesforce org.

Confirm that VS Code is connected to the correct org.

Confirm that the Guest User Nickname was replaced in the Sharing Rule XML.

Deploy the complete Carrier Onboarding package and its dependencies.

Deploy with:

sf project deploy start --manifest manifest/package.xml --target-org YOUR_ORG_ALIAS --wait 90

If Salesforce returns this error:

Specify a guest user’s nickname for the guestUser field.

the <guestUser> value is still a display name, an invalid value, or the placeholder was not replaced with the exact CommunityNickname.

5. Configure the Salesforce Site

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

6. Give the Site Access to the Carrier Onboarding Platform Event

From the same Site Public Access Settings:

Open Object Settings.

Find and open:

Carrier_Onboarding_Action__e

Enable Read and Create access.

Give the Site Guest User Read Access and Edit Access to all fields used on Carrier_Onboarding_Action__e.

Save the profile.

The Create permission is required because Carrier Onboarding publishes this Platform Event for document uploads, signatures, and submission actions.

The package includes a focused profile file named:

Portal Site Profile

This profile grants access to the Carrier Onboarding Apex classes, Visualforce page, Carrier object, Platform Event, and fields used by the form.

If the target Site uses a different Guest User profile name, manually apply the same permissions to the profile opened from that Site's Public Access Settings.

7. Give Carrier Object and Field Access

From the Site's Public Access Settings:

Open Object Settings → Carrier.

Enable Read, Create, and Edit.

Enable Read Access and Edit Access for every Carrier field used by the onboarding form.

Pay special attention to managed fields beginning with FreightTM__, including:

FreightTM__On_boarding_Status__c

Confirm access to:

Public_Onboarding_Access__c
Ready_for_Loads__c
Load_Board_Active__c

Save the profile.

Salesforce does not permit Edit Access on formula, system-managed, or otherwise read-only fields.

8. Verify the Carrier Guest User Sharing Rule

The package deploys this Sharing Rule:

Label: Carrier-Onboarding rule
Rule type: Guest user access, based on criteria
Criteria: Public_Onboarding_Access equals True
Share with: The Site Guest User selected by its Nickname
Access level: Read Only

After deployment, go to:

Setup → Sharing Settings → Carrier Sharing Rules

Confirm that Carrier-Onboarding rule exists and shares records with the correct Site Guest User.

The Carrier Onboarding Apex code sets:

Public_Onboarding_Access__c = true

on Carrier records created or updated through the public onboarding form.

9. Add the Carrier Onboarding Status Panel to the Carrier Record Page

The package includes this Lightning Web Component:

Carrier Onboarding Status Panel

To add it:

Open any Carrier record.

Click the Setup gear.

Select Edit Page.

In Lightning App Builder, find Carrier Onboarding Status Panel.

Drag it onto the Carrier record page.

Click Save.

Click Activate if required.

The component displays the Carrier onboarding, document, signature, agreement, compliance, public-access, readiness, and load-board fields.

Field Visibility Included in the Package

The included profile metadata is:

force-app/main/default/profiles/Portal Site Profile.profile-meta.xml

For every Carrier and Carrier_Onboarding_Action__e field included in this package:

Visible = Enabled
Readable = true

For writable custom fields:

Read-Only = Disabled
Editable = true

The profile also contains:

FreightTM__Carrier__c:
Read = true
Create = true
Edit = true
View All Fields = true

Carrier_Onboarding_Action__e:
Read = true
Create = true
View All Fields = true

After deployment, verify the settings through:

Setup
→ Sites
→ Open the Carrier Onboarding Site
→ Public Access Settings
→ Object Settings

Then open both:

Carrier
Carrier Onboarding Action

All package fields should show Visible for Portal Site Profile.

If the target Site uses a Guest User profile with a different profile name, Salesforce will not automatically apply the Portal Site Profile metadata to that different profile. In that case, either rename the profile metadata to match the target Guest User profile or apply the same field permissions manually.

10. Configure the Managed On-boarding Status Picklist

The Carrier Onboarding code uses the following managed picklist values:

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

Because FreightTM__On_boarding_Status__c is a managed restricted picklist, the required values must be available to the Carrier record type.

To configure this:

Go to Setup → Object Manager → Carrier → Record Types.

Open every Carrier record type that can be used by the Site Guest User.

Find On-boarding Status and click Edit.

Move all required values, especially Submitted, into Selected Values.

Save.

In the Site Guest User profile, verify the default Carrier record type.

Restricted Picklist Error

Save failed: On-boarding Status: bad value for restricted picklist field: Submitted

This normally means Submitted exists on the managed field but is not available to the Carrier record type used during public submission.

11. Open the Public Carrier Onboarding Page

After deployment and Site permission setup, open:

https://wise-koala-63tngo-dev-ed.trailblaze.my.salesforce-sites.com/CarrierOnboardingSiteHome

The Carrier Onboarding page should open publicly.

12. Final Verification

Open the public URL in an Incognito browser window.

Complete and save the Carrier form.

Upload the required documents.

Save the signature.

Submit for review.

Confirm that Public_Onboarding_Access__c is enabled on the Carrier.

Confirm that Carrier-Onboarding rule exists in Sharing Settings.

Confirm that the rule references the correct Site Guest User.

Confirm that the Carrier Onboarding Status Panel displays correctly on the Carrier record page.