---
author: admin
created: 2016-12-30 12:02:56 +0000
roles:
   - any
---

<style> h6 { text-decoration: underline; } </style>

This menu gives access to the general site administration functions. These are
further segregated in to Job Daemon, Logs and Types menus.

###### Job Daemon

This simply gives the status of the job daemon which processes outgoing emails,
SMS messages etc.  


###### Logs 

This gives access to the server side logs. There are five logs in all:

* activity - keeps a record of users activity on the site
* job daemon - the activity of the job daemon, messages sent etc.
* schema - changes to the underlying system data
* server - the events in the notitia server itself.
* utilities - background services and command line - records activities of the command line tools used on the site (rarely used)



###### Processes

This enables control of the background processes supporting the site - the job daemon itself and events that trigger notification emails or messages

###### Types

As noted below, some duties need to have certain certifications to be allowed
on the rota. Slot Roles here allows Administrator users to define the
certifications for those duties.

![ManagementR]([%links.assets%]management-roles.png)
