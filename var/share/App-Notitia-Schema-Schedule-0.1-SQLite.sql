BEGIN TRANSACTION;

DROP TABLE "person";

CREATE TABLE "person" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "next_of_kin" integer,
  "active" boolean NOT NULL DEFAULT 0,
  "password_expired" boolean NOT NULL DEFAULT 1,
  "dob" datetime NOT NULL,
  "joined" datetime NOT NULL,
  "resigned" datetime NOT NULL,
  "subscription" datetime NOT NULL,
  "postcode" varchar(16) NOT NULL DEFAULT '',
  "name" varchar(64) NOT NULL DEFAULT '',
  "first_name" varchar(64) NOT NULL DEFAULT '',
  "last_name" varchar(64) NOT NULL DEFAULT '',
  "address" varchar(64) NOT NULL DEFAULT '',
  "email_address" varchar(64) NOT NULL DEFAULT '',
  "mobile_phone" varchar(64) NOT NULL DEFAULT '',
  "home_phone" varchar(64) NOT NULL DEFAULT '',
  "password" varchar(128) NOT NULL DEFAULT '',
  "notes" varchar(255),
  FOREIGN KEY ("next_of_kin") REFERENCES "person"("id")
);

CREATE INDEX "person_idx_next_of_kin" ON "person" ("next_of_kin");

CREATE UNIQUE INDEX "person_name" ON "person" ("name");

DROP TABLE "type";

CREATE TABLE "type" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "name" varchar(32) NOT NULL DEFAULT '',
  "type" enum NOT NULL
);

DROP TABLE "endorsement";

CREATE TABLE "endorsement" (
  "recipient" integer NOT NULL,
  "points" smallint NOT NULL,
  "endorsed" datetime NOT NULL,
  "code" varchar(16) NOT NULL DEFAULT '',
  "notes" varchar(255),
  PRIMARY KEY ("recipient", "code"),
  FOREIGN KEY ("recipient") REFERENCES "person"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "endorsement_idx_recipient" ON "endorsement" ("recipient");

DROP TABLE "rota";

CREATE TABLE "rota" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "date" datetime NOT NULL,
  "type" integer NOT NULL,
  FOREIGN KEY ("type") REFERENCES "type"("id")
);

CREATE INDEX "rota_idx_type" ON "rota" ("type");

DROP TABLE "certification";

CREATE TABLE "certification" (
  "recipient" integer NOT NULL,
  "type" integer NOT NULL,
  "completed" datetime NOT NULL,
  "notes" varchar(255),
  PRIMARY KEY ("recipient", "type"),
  FOREIGN KEY ("recipient") REFERENCES "person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("type") REFERENCES "type"("id")
);

CREATE INDEX "certification_idx_recipient" ON "certification" ("recipient");

CREATE INDEX "certification_idx_type" ON "certification" ("type");

DROP TABLE "role";

CREATE TABLE "role" (
  "member" integer NOT NULL,
  "type" integer NOT NULL,
  PRIMARY KEY ("member", "type"),
  FOREIGN KEY ("member") REFERENCES "person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("type") REFERENCES "type"("id")
);

CREATE INDEX "role_idx_member" ON "role" ("member");

CREATE INDEX "role_idx_type" ON "role" ("type");

DROP TABLE "shift";

CREATE TABLE "shift" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "rota" integer NOT NULL,
  "type" enum NOT NULL DEFAULT 'day',
  FOREIGN KEY ("rota") REFERENCES "rota"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "shift_idx_rota" ON "shift" ("rota");

DROP TABLE "vehicle";

CREATE TABLE "vehicle" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "type" integer NOT NULL,
  "owner" integer,
  "aquired" datetime NOT NULL,
  "disposed" datetime NOT NULL,
  "vrn" varchar(16) NOT NULL DEFAULT '',
  "name" varchar(64) NOT NULL DEFAULT '',
  "notes" varchar(255),
  FOREIGN KEY ("owner") REFERENCES "person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("type") REFERENCES "type"("id")
);

CREATE INDEX "vehicle_idx_owner" ON "vehicle" ("owner");

CREATE INDEX "vehicle_idx_type" ON "vehicle" ("type");

DROP TABLE "event";

CREATE TABLE "event" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "rota" integer NOT NULL,
  "owner" integer NOT NULL,
  "start" datetime NOT NULL,
  "end" datetime NOT NULL,
  "name" varchar(64) NOT NULL DEFAULT '',
  "description" varchar(128) NOT NULL DEFAULT '',
  "notes" varchar(255),
  FOREIGN KEY ("owner") REFERENCES "person"("id"),
  FOREIGN KEY ("rota") REFERENCES "rota"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "event_idx_owner" ON "event" ("owner");

CREATE INDEX "event_idx_rota" ON "event" ("rota");

CREATE UNIQUE INDEX "event_name" ON "event" ("name");

DROP TABLE "participent";

CREATE TABLE "participent" (
  "event" integer NOT NULL,
  "participent" integer NOT NULL,
  PRIMARY KEY ("event", "participent"),
  FOREIGN KEY ("event") REFERENCES "event"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("participent") REFERENCES "person"("id")
);

CREATE INDEX "participent_idx_event" ON "participent" ("event");

CREATE INDEX "participent_idx_participent" ON "participent" ("participent");

DROP TABLE "slot";

CREATE TABLE "slot" (
  "shift" integer NOT NULL,
  "type" enum NOT NULL DEFAULT '0',
  "subslot" smallint NOT NULL,
  "operator" integer NOT NULL,
  "bike_requested" boolean NOT NULL DEFAULT 0,
  "vehicle_assigner" integer,
  "vehicle" integer,
  PRIMARY KEY ("shift", "type", "subslot"),
  FOREIGN KEY ("operator") REFERENCES "person"("id"),
  FOREIGN KEY ("shift") REFERENCES "shift"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("vehicle") REFERENCES "vehicle"("id"),
  FOREIGN KEY ("vehicle_assigner") REFERENCES "person"("id")
);

CREATE INDEX "slot_idx_operator" ON "slot" ("operator");

CREATE INDEX "slot_idx_shift" ON "slot" ("shift");

CREATE INDEX "slot_idx_vehicle" ON "slot" ("vehicle");

CREATE INDEX "slot_idx_vehicle_assigner" ON "slot" ("vehicle_assigner");

DROP TABLE "transport";

CREATE TABLE "transport" (
  "event" integer NOT NULL,
  "vehicle" integer NOT NULL,
  "vehicle_assigner" integer NOT NULL,
  PRIMARY KEY ("event", "vehicle"),
  FOREIGN KEY ("event") REFERENCES "event"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("vehicle") REFERENCES "vehicle"("id"),
  FOREIGN KEY ("vehicle_assigner") REFERENCES "person"("id")
);

CREATE INDEX "transport_idx_event" ON "transport" ("event");

CREATE INDEX "transport_idx_vehicle" ON "transport" ("vehicle");

CREATE INDEX "transport_idx_vehicle_assigner" ON "transport" ("vehicle_assigner");

COMMIT;
