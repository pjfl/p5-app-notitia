BEGIN TRANSACTION;

DROP TABLE "person";

CREATE TABLE "person" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "next_of_kin_id" integer,
  "active" boolean NOT NULL DEFAULT 0,
  "password_expired" boolean NOT NULL DEFAULT 1,
  "dob" datetime DEFAULT '0000-00-00',
  "joined" datetime DEFAULT '0000-00-00',
  "resigned" datetime DEFAULT '0000-00-00',
  "subscription" datetime DEFAULT '0000-00-00',
  "shortcode" varchar(6) NOT NULL DEFAULT '',
  "name" varchar(64) NOT NULL DEFAULT '',
  "password" varchar(128) NOT NULL DEFAULT '',
  "first_name" varchar(30) NOT NULL DEFAULT '',
  "last_name" varchar(30) NOT NULL DEFAULT '',
  "address" varchar(64) NOT NULL DEFAULT '',
  "postcode" varchar(16) NOT NULL DEFAULT '',
  "email_address" varchar(64) NOT NULL DEFAULT '',
  "mobile_phone" varchar(32) NOT NULL DEFAULT '',
  "home_phone" varchar(32) NOT NULL DEFAULT '',
  "notes" varchar(255) NOT NULL DEFAULT '',
  FOREIGN KEY ("next_of_kin_id") REFERENCES "person"("id")
);

CREATE INDEX "person_idx_next_of_kin_id" ON "person" ("next_of_kin_id");

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
  "endorsed" datetime DEFAULT '0000-00-00',
  "type_code" varchar(25) NOT NULL DEFAULT '',
  "uri" varchar(32) NOT NULL DEFAULT '',
  "notes" varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY ("recipient_id", "type_code"),
  FOREIGN KEY ("recipient_id") REFERENCES "person"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "endorsement_idx_recipient_id" ON "endorsement" ("recipient_id");

CREATE UNIQUE INDEX "endorsement_uri" ON "endorsement" ("uri");

DROP TABLE "rota";

CREATE TABLE "rota" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "type_id" integer NOT NULL,
  "date" datetime DEFAULT '0000-00-00',
  FOREIGN KEY ("type_id") REFERENCES "type"("id")
);

CREATE INDEX "rota_idx_type_id" ON "rota" ("type_id");

CREATE UNIQUE INDEX "rota_type_id_date" ON "rota" ("type_id", "date");

DROP TABLE "slot_criteria";

CREATE TABLE "slot_criteria" (
  "slot_type" enum NOT NULL DEFAULT '0',
  "certification_type_id" integer NOT NULL,
  PRIMARY KEY ("slot_type", "certification_type_id"),
  FOREIGN KEY ("certification_type_id") REFERENCES "type"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "slot_criteria_idx_certification_type_id" ON "slot_criteria" ("certification_type_id");

DROP TABLE "certification";

CREATE TABLE "certification" (
  "recipient_id" integer NOT NULL,
  "type_id" integer NOT NULL,
  "completed" datetime DEFAULT '0000-00-00',
  "notes" varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY ("recipient_id", "type_id"),
  FOREIGN KEY ("recipient_id") REFERENCES "person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("type_id") REFERENCES "type"("id")
);

CREATE INDEX "certification_idx_recipient_id" ON "certification" ("recipient_id");

CREATE INDEX "certification_idx_type_id" ON "certification" ("type_id");

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

DROP TABLE "vehicle";

CREATE TABLE "vehicle" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "type_id" integer NOT NULL,
  "owner_id" integer,
  "aquired" datetime DEFAULT '0000-00-00',
  "disposed" datetime DEFAULT '0000-00-00',
  "vrn" varchar(16) NOT NULL DEFAULT '',
  "name" varchar(64) NOT NULL DEFAULT '',
  "notes" varchar(255) NOT NULL DEFAULT '',
  FOREIGN KEY ("owner_id") REFERENCES "person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("type_id") REFERENCES "type"("id")
);

CREATE INDEX "vehicle_idx_owner_id" ON "vehicle" ("owner_id");

CREATE INDEX "vehicle_idx_type_id" ON "vehicle" ("type_id");

CREATE UNIQUE INDEX "vehicle_vrn" ON "vehicle" ("vrn");

DROP TABLE "event";

CREATE TABLE "event" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "rota_id" integer NOT NULL,
  "owner_id" integer NOT NULL,
  "start_time" varchar(5) NOT NULL DEFAULT '',
  "end_time" varchar(5) NOT NULL DEFAULT '',
  "name" varchar(57) NOT NULL DEFAULT '',
  "uri" varchar(64) NOT NULL DEFAULT '',
  "description" varchar(128) NOT NULL DEFAULT '',
  "notes" varchar(255) NOT NULL DEFAULT '',
  FOREIGN KEY ("owner_id") REFERENCES "person"("id"),
  FOREIGN KEY ("rota_id") REFERENCES "rota"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "event_idx_owner_id" ON "event" ("owner_id");

CREATE INDEX "event_idx_rota_id" ON "event" ("rota_id");

CREATE UNIQUE INDEX "event_uri" ON "event" ("uri");

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

COMMIT;
