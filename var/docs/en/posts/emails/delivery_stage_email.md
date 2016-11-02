---
author: admin
created: 2016-11-02 21:28:31 +0000
title: Delivery Stage
subject: New Delivery Request Stage
roles:
   - editor
---

Dear [% first_name %],

A delivery request stage has been created for you by [% controller %]

The pick up location is [% beginning %] and the drop off location is
[% ending %]

The request priority is [% priority %] and the collection eta. is
[% collection_eta %]
[% FOR package IN packages -%]

*   [% package.0 %] x [% package.1 %] : [% package.2 %]

[% END -%]
This request was sent on the [% called %]

Regards
