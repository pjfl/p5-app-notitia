---
author: admin
created: 2016-07-10 14:58:25 +0000
roles:
   - any
---

The Management Menu gives access to General Administration, Events, People and
Vehicle management functions.

#### Admin

This menu gives access to the general site administration functions. These are
further segregated in to Job Daemon, Logs and Types menus.

##### Job Daemon

This simply gives the status of the job daemon which processes outgoing emails,
SMS messages etc.

##### Logs

This gives access to the server side logs. There are five logs in all:

* activity - keeps a record of users activity on the site
* command line - records activities of the command line tools used on the site (rarely used)
* job daemon - the activity of the job daemon, messages sent etc.
* schema - changes to the underlying system data
* server - the events in the notitia server itself.

##### Types

As noted below, some duties need to have certain certifications to be allowed
on the rota. Slot Roles here allows Administrator users to define the
certifications for those duties.

![ManagementR]([%links.assets%]management-roles.png)

#### Events

Administratoion of past and current events. Here events can be created and
edited, vehicles requested, participants limited etc.

#### People

From here, assuming you have the appropriate Roles, you can add or edit peoples
details, add or remove roles, add or remove certifications and for riders and
drivers, add/remove licence endorsement records.

![ManagementP]([%links.assets%]management-people.png)

##### Roles

There are many "roles" defined in the system that control what a user is
allowed to do in the system and what their duties include in the organisation.

![ManagementR]([%links.assets%]management-rolelist.png)

##### General operational roles:

*  Controller
*  Driver
*  Rider
*  Fund Raiser

##### Administrative roles:

*  Administrator - General access to the system admin functions. This does not allow access to everything, but does allow sufficient access to add or remove further roles.
*  Address Viewer - Access to everyone's contact details
*  Editor - Access to create/delete/edit documentation pages
*  Event Manager - Access to add/delete/edit events.
*  Person Manager - Access to view and edit everyone's personal information, and to manage their roles, certifications etc.
*  Rota Manager - Access to edit the main rota, assign vehicles.
*  Training Manager - Access to the certifications and personal documents, assign certifications.

##### Certifications

To perform certain functions, people need to have some certifications; evidence
that they have the appropriate qualifications or training. A rider, for
instance, normally requires 4 certifications to be able to claim a rider slot
on the rota - "Cat. A licence", "Advanced Motorcycle", "Route" (training) and
"GMP" (training).

![ManagementC]([%links.assets%]management-certifications.png)

Also on the certifications page is access to the personal document store. This
is where documentary evidence of accreditations (IAM pass certs, DVLA
transripts etc) can be stored, viewed and retrieved.

##### Endorsements

For riders and drivers, we keep a record of any endorsements on their licence.

![ManagementE]([%links.assets%]management-endorsements.png)

#### Reports

This menu gives access to general statistical reports.

##### People

This gives the raw counts of duties that everyone has done in a given period as
controller, rider, driver, or events attended.

##### People Meta

This gives the overall count of types of members in a given period.

##### Slot Report

A view of the approximate capacity fulfilled, that is, how many of the duty
slots we filled.

##### Vehicle Report

How many shifts/events each vehicle has done in a given period.

#### Vehicles

This menu allows access to the details of all the vehicles in the system.

![ManagementV]([%links.assets%]management-vehicles.png)

Some will be "personal" vehicles that users own that they may use for
occasional duty, others will be vehicles owned and maintained by the
organisation.  For "Service" vehicles, here we can define events for the
vehicle (12k mile service for instance) so that it will be unavailable for
allocation and will appear on the rota.

![ManagementVEvent]([%links.assets%]management-vevent.png)
