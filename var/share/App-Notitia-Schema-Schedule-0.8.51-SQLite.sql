BEGIN TRANSACTION;

DROP TABLE "customer";

CREATE TABLE "customer" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "name" varchar(64) NOT NULL DEFAULT ''
);

CREATE UNIQUE INDEX "customer_name" ON "customer" ("name");

DROP TABLE "job";

CREATE TABLE "job" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "name" varchar(32) NOT NULL DEFAULT '',
  "command" varchar(1024)
);

DROP TABLE "location";

CREATE TABLE "location" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "address" varchar(64) NOT NULL DEFAULT '',
  "postcode" varchar(16),
  "location" varchar(24),
  "coordinates" varchar(16)
);

CREATE UNIQUE INDEX "location_address_postcode" ON "location" ("address", "postcode");

DROP TABLE "person";

CREATE TABLE "person" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "next_of_kin_id" integer,
  "active" boolean NOT NULL DEFAULT 0,
  "password_expired" boolean NOT NULL DEFAULT 1,
  "badge_expires" datetime,
  "dob" datetime,
  "joined" datetime,
  "resigned" datetime,
  "subscription" datetime,
  "badge_id" smallint,
  "rows_per_page" smallint NOT NULL DEFAULT 20,
  "shortcode" varchar(8) NOT NULL DEFAULT '',
  "name" varchar(64) NOT NULL DEFAULT '',
  "password" varchar(128) NOT NULL DEFAULT '',
  "first_name" varchar(32) NOT NULL DEFAULT '',
  "last_name" varchar(32) NOT NULL DEFAULT '',
  "address" varchar(64) NOT NULL DEFAULT '',
  "postcode" varchar(16) NOT NULL DEFAULT '',
  "location" varchar(24) NOT NULL DEFAULT '',
  "coordinates" varchar(16) NOT NULL DEFAULT '',
  "email_address" varchar(64) NOT NULL DEFAULT '',
  "mobile_phone" varchar(16) NOT NULL DEFAULT '',
  "home_phone" varchar(16) NOT NULL DEFAULT '',
  "totp_secret" varchar(16) NOT NULL DEFAULT '',
  "region" varchar(1) NOT NULL DEFAULT '',
  "notes" varchar(255) NOT NULL DEFAULT '',
  FOREIGN KEY ("next_of_kin_id") REFERENCES "person"("id")
);

CREATE INDEX "person_idx_next_of_kin_id" ON "person" ("next_of_kin_id");

CREATE UNIQUE INDEX "person_badge_id" ON "person" ("badge_id");

CREATE UNIQUE INDEX "person_email_address" ON "person" ("email_address");

CREATE UNIQUE INDEX "person_name" ON "person" ("name");

CREATE UNIQUE INDEX "person_shortcode" ON "person" ("shortcode");

DROP TABLE "type";

CREATE TABLE "type" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "name" varchar(32) NOT NULL DEFAULT '',
  "type_class" enum NOT NULL
);

CREATE UNIQUE INDEX "type_name_type_class" ON "type" ("name", "type_class");

DROP TABLE "endorsement";

CREATE TABLE "endorsement" (
  "recipient_id" integer NOT NULL,
  "points" smallint NOT NULL,
  "endorsed" datetime NOT NULL,
  "type_code" varchar(25) NOT NULL DEFAULT '',
  "uri" varchar(32) NOT NULL DEFAULT '',
  "notes" varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY ("recipient_id", "type_code", "endorsed"),
  FOREIGN KEY ("recipient_id") REFERENCES "person"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "endorsement_idx_recipient_id" ON "endorsement" ("recipient_id");

CREATE UNIQUE INDEX "endorsement_uri" ON "endorsement" ("uri");

DROP TABLE "rota";

CREATE TABLE "rota" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "type_id" integer NOT NULL,
  "date" datetime,
  FOREIGN KEY ("type_id") REFERENCES "type"("id")
);

CREATE INDEX "rota_idx_type_id" ON "rota" ("type_id");

CREATE INDEX "rota_idx_date" ON "rota" ("date");

CREATE UNIQUE INDEX "rota_type_id_date" ON "rota" ("type_id", "date");

DROP TABLE "slot_criteria";

CREATE TABLE "slot_criteria" (
  "slot_type" enum NOT NULL DEFAULT '0',
  "certification_type_id" integer NOT NULL,
  PRIMARY KEY ("slot_type", "certification_type_id"),
  FOREIGN KEY ("certification_type_id") REFERENCES "type"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "slot_criteria_idx_certification_type_id" ON "slot_criteria" ("certification_type_id");

DROP TABLE "unsubscribe";

CREATE TABLE "unsubscribe" (
  "recipient_id" integer NOT NULL,
  "sink" varchar(16) NOT NULL DEFAULT 'email',
  "action" varchar(32) NOT NULL DEFAULT '',
  PRIMARY KEY ("recipient_id", "sink", "action"),
  FOREIGN KEY ("recipient_id") REFERENCES "person"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "unsubscribe_idx_recipient_id" ON "unsubscribe" ("recipient_id");

DROP TABLE "certification";

CREATE TABLE "certification" (
  "recipient_id" integer NOT NULL,
  "type_id" integer NOT NULL,
  "completed" datetime,
  "notes" varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY ("recipient_id", "type_id"),
  FOREIGN KEY ("recipient_id") REFERENCES "person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("type_id") REFERENCES "type"("id")
);

CREATE INDEX "certification_idx_recipient_id" ON "certification" ("recipient_id");

CREATE INDEX "certification_idx_type_id" ON "certification" ("type_id");

DROP TABLE "incident";

CREATE TABLE "incident" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "raised" datetime,
  "controller_id" integer NOT NULL,
  "category_id" integer NOT NULL,
  "committee_member_id" integer,
  "committee_informed" datetime,
  "title" varchar(64) NOT NULL DEFAULT '',
  "reporter" varchar(64) NOT NULL DEFAULT '',
  "reporter_phone" varchar(16) NOT NULL DEFAULT '',
  "category_other" varchar(16) NOT NULL DEFAULT '',
  "notes" varchar(255) NOT NULL DEFAULT '',
  FOREIGN KEY ("category_id") REFERENCES "type"("id"),
  FOREIGN KEY ("committee_member_id") REFERENCES "person"("id"),
  FOREIGN KEY ("controller_id") REFERENCES "person"("id")
);

CREATE INDEX "incident_idx_category_id" ON "incident" ("category_id");

CREATE INDEX "incident_idx_committee_member_id" ON "incident" ("committee_member_id");

CREATE INDEX "incident_idx_controller_id" ON "incident" ("controller_id");

CREATE UNIQUE INDEX "incident_title_raised" ON "incident" ("title", "raised");

DROP TABLE "role";

CREATE TABLE "role" (
  "member_id" integer NOT NULL,
  "type_id" integer NOT NULL,
  PRIMARY KEY ("member_id", "type_id"),
  FOREIGN KEY ("member_id") REFERENCES "person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("type_id") REFERENCES "type"("id")
);

CREATE INDEX "role_idx_member_id" ON "role" ("member_id");

CREATE INDEX "role_idx_type_id" ON "role" ("type_id");

DROP TABLE "shift";

CREATE TABLE "shift" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "rota_id" integer NOT NULL,
  "type_name" enum NOT NULL DEFAULT 'day',
  FOREIGN KEY ("rota_id") REFERENCES "rota"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "shift_idx_rota_id" ON "shift" ("rota_id");

DROP TABLE "training";

CREATE TABLE "training" (
  "recipient_id" integer NOT NULL,
  "course_type_id" integer NOT NULL,
  "status" enum NOT NULL DEFAULT 'enroled',
  "enroled" datetime,
  "started" datetime,
  "completed" datetime,
  "expired" datetime,
  PRIMARY KEY ("recipient_id", "course_type_id"),
  FOREIGN KEY ("course_type_id") REFERENCES "type"("id"),
  FOREIGN KEY ("recipient_id") REFERENCES "person"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "training_idx_course_type_id" ON "training" ("course_type_id");

CREATE INDEX "training_idx_recipient_id" ON "training" ("recipient_id");

DROP TABLE "vehicle";

CREATE TABLE "vehicle" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "type_id" integer NOT NULL,
  "owner_id" integer,
  "aquired" datetime,
  "disposed" datetime,
  "colour" varchar(16) NOT NULL DEFAULT '',
  "vrn" varchar(16) NOT NULL DEFAULT '',
  "name" varchar(64) NOT NULL DEFAULT '',
  "notes" varchar(255) NOT NULL DEFAULT '',
  FOREIGN KEY ("owner_id") REFERENCES "person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("type_id") REFERENCES "type"("id")
);

CREATE INDEX "vehicle_idx_owner_id" ON "vehicle" ("owner_id");

CREATE INDEX "vehicle_idx_type_id" ON "vehicle" ("type_id");

CREATE UNIQUE INDEX "vehicle_vrn" ON "vehicle" ("vrn");

DROP TABLE "incident_party";

CREATE TABLE "incident_party" (
  "incident_id" integer NOT NULL,
  "incident_party_id" integer NOT NULL,
  PRIMARY KEY ("incident_id", "incident_party_id"),
  FOREIGN KEY ("incident_id") REFERENCES "incident"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("incident_party_id") REFERENCES "person"("id")
);

CREATE INDEX "incident_party_idx_incident_id" ON "incident_party" ("incident_id");

CREATE INDEX "incident_party_idx_incident_party_id" ON "incident_party" ("incident_party_id");

DROP TABLE "journey";

CREATE TABLE "journey" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "completed" boolean NOT NULL DEFAULT 0,
  "priority" enum NOT NULL DEFAULT 'routine',
  "original_priority" enum NOT NULL DEFAULT 'routine',
  "created" datetime,
  "requested" datetime,
  "delivered" datetime,
  "controller_id" integer NOT NULL,
  "customer_id" integer NOT NULL,
  "pickup_id" integer NOT NULL,
  "dropoff_id" integer NOT NULL,
  "notes" varchar(255) NOT NULL DEFAULT '',
  FOREIGN KEY ("controller_id") REFERENCES "person"("id"),
  FOREIGN KEY ("customer_id") REFERENCES "customer"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("dropoff_id") REFERENCES "location"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("pickup_id") REFERENCES "location"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "journey_idx_controller_id" ON "journey" ("controller_id");

CREATE INDEX "journey_idx_customer_id" ON "journey" ("customer_id");

CREATE INDEX "journey_idx_dropoff_id" ON "journey" ("dropoff_id");

CREATE INDEX "journey_idx_pickup_id" ON "journey" ("pickup_id");

DROP TABLE "event";

CREATE TABLE "event" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "event_type_id" integer NOT NULL,
  "owner_id" integer NOT NULL,
  "start_rota_id" integer NOT NULL,
  "end_rota_id" integer,
  "vehicle_id" integer,
  "course_type_id" integer,
  "location_id" integer,
  "max_participents" smallint,
  "start_time" varchar(5) NOT NULL DEFAULT '',
  "end_time" varchar(5) NOT NULL DEFAULT '',
  "name" varchar(57) NOT NULL DEFAULT '',
  "uri" varchar(64) NOT NULL DEFAULT '',
  "description" varchar(128) NOT NULL DEFAULT '',
  "notes" varchar(255) NOT NULL DEFAULT '',
  FOREIGN KEY ("course_type_id") REFERENCES "type"("id"),
  FOREIGN KEY ("end_rota_id") REFERENCES "rota"("id"),
  FOREIGN KEY ("event_type_id") REFERENCES "type"("id"),
  FOREIGN KEY ("location_id") REFERENCES "location"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("owner_id") REFERENCES "person"("id"),
  FOREIGN KEY ("start_rota_id") REFERENCES "rota"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("vehicle_id") REFERENCES "vehicle"("id")
);

CREATE INDEX "event_idx_course_type_id" ON "event" ("course_type_id");

CREATE INDEX "event_idx_end_rota_id" ON "event" ("end_rota_id");

CREATE INDEX "event_idx_event_type_id" ON "event" ("event_type_id");

CREATE INDEX "event_idx_location_id" ON "event" ("location_id");

CREATE INDEX "event_idx_owner_id" ON "event" ("owner_id");

CREATE INDEX "event_idx_start_rota_id" ON "event" ("start_rota_id");

CREATE INDEX "event_idx_vehicle_id" ON "event" ("vehicle_id");

CREATE UNIQUE INDEX "event_uri" ON "event" ("uri");

DROP TABLE "package";

CREATE TABLE "package" (
  "journey_id" integer NOT NULL,
  "package_type_id" integer NOT NULL,
  "quantity" smallint NOT NULL DEFAULT 0,
  "description" varchar(64) NOT NULL DEFAULT '',
  PRIMARY KEY ("journey_id", "package_type_id"),
  FOREIGN KEY ("journey_id") REFERENCES "journey"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("package_type_id") REFERENCES "type"("id")
);

CREATE INDEX "package_idx_journey_id" ON "package" ("journey_id");

CREATE INDEX "package_idx_package_type_id" ON "package" ("package_type_id");

DROP TABLE "slot";

CREATE TABLE "slot" (
  "shift_id" integer NOT NULL,
  "operator_id" integer NOT NULL,
  "type_name" enum NOT NULL DEFAULT '0',
  "subslot" smallint NOT NULL,
  "bike_requested" boolean NOT NULL DEFAULT 0,
  "vehicle_assigner_id" integer,
  "vehicle_id" integer,
  PRIMARY KEY ("shift_id", "type_name", "subslot"),
  FOREIGN KEY ("operator_id") REFERENCES "person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("shift_id") REFERENCES "shift"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("vehicle_id") REFERENCES "vehicle"("id"),
  FOREIGN KEY ("vehicle_assigner_id") REFERENCES "person"("id")
);

CREATE INDEX "slot_idx_operator_id" ON "slot" ("operator_id");

CREATE INDEX "slot_idx_shift_id" ON "slot" ("shift_id");

CREATE INDEX "slot_idx_vehicle_id" ON "slot" ("vehicle_id");

CREATE INDEX "slot_idx_vehicle_assigner_id" ON "slot" ("vehicle_assigner_id");

DROP TABLE "leg";

CREATE TABLE "leg" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "journey_id" integer NOT NULL,
  "operator_id" integer NOT NULL,
  "beginning_id" integer NOT NULL,
  "ending_id" integer NOT NULL,
  "vehicle_id" integer,
  "created" datetime,
  "called" datetime,
  "collection_eta" datetime,
  "collected" datetime,
  "delivered" datetime,
  "on_station" datetime,
  FOREIGN KEY ("beginning_id") REFERENCES "location"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("ending_id") REFERENCES "location"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("journey_id") REFERENCES "journey"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("operator_id") REFERENCES "person"("id"),
  FOREIGN KEY ("vehicle_id") REFERENCES "vehicle"("id")
);

CREATE INDEX "leg_idx_beginning_id" ON "leg" ("beginning_id");

CREATE INDEX "leg_idx_ending_id" ON "leg" ("ending_id");

CREATE INDEX "leg_idx_journey_id" ON "leg" ("journey_id");

CREATE INDEX "leg_idx_operator_id" ON "leg" ("operator_id");

CREATE INDEX "leg_idx_vehicle_id" ON "leg" ("vehicle_id");

DROP TABLE "participent";

CREATE TABLE "participent" (
  "event_id" integer NOT NULL,
  "participent_id" integer NOT NULL,
  PRIMARY KEY ("event_id", "participent_id"),
  FOREIGN KEY ("event_id") REFERENCES "event"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("participent_id") REFERENCES "person"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "participent_idx_event_id" ON "participent" ("event_id");

CREATE INDEX "participent_idx_participent_id" ON "participent" ("participent_id");

DROP TABLE "trainer";

CREATE TABLE "trainer" (
  "trainer_id" integer NOT NULL,
  "event_id" integer NOT NULL,
  PRIMARY KEY ("trainer_id", "event_id"),
  FOREIGN KEY ("event_id") REFERENCES "event"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("trainer_id") REFERENCES "person"("id")
);

CREATE INDEX "trainer_idx_event_id" ON "trainer" ("event_id");

CREATE INDEX "trainer_idx_trainer_id" ON "trainer" ("trainer_id");

DROP TABLE "transport";

CREATE TABLE "transport" (
  "event_id" integer NOT NULL,
  "vehicle_id" integer NOT NULL,
  "vehicle_assigner_id" integer NOT NULL,
  PRIMARY KEY ("event_id", "vehicle_id"),
  FOREIGN KEY ("event_id") REFERENCES "event"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("vehicle_id") REFERENCES "vehicle"("id"),
  FOREIGN KEY ("vehicle_assigner_id") REFERENCES "person"("id")
);

CREATE INDEX "transport_idx_event_id" ON "transport" ("event_id");

CREATE INDEX "transport_idx_vehicle_id" ON "transport" ("vehicle_id");

CREATE INDEX "transport_idx_vehicle_assigner_id" ON "transport" ("vehicle_assigner_id");

DROP TABLE "vehicle_request";

CREATE TABLE "vehicle_request" (
  "event_id" integer NOT NULL,
  "type_id" integer NOT NULL,
  "quantity" smallint NOT NULL,
  PRIMARY KEY ("event_id", "type_id"),
  FOREIGN KEY ("event_id") REFERENCES "event"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("type_id") REFERENCES "type"("id")
);

CREATE INDEX "vehicle_request_idx_event_id" ON "vehicle_request" ("event_id");

CREATE INDEX "vehicle_request_idx_type_id" ON "vehicle_request" ("type_id");

COMMIT;
