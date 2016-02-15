DROP TABLE "person" CASCADE;
CREATE TABLE "person" (
  "id" serial NOT NULL,
  "next_of_kin" integer,
  "active" boolean DEFAULT '0' NOT NULL,
  "password_expired" boolean DEFAULT '1' NOT NULL,
  "dob" timestamp NOT NULL,
  "joined" timestamp NOT NULL,
  "resigned" timestamp NOT NULL,
  "subscription" timestamp NOT NULL,
  "postcode" character varying(16) DEFAULT '' NOT NULL,
  "name" character varying(64) DEFAULT '' NOT NULL,
  "first_name" character varying(64) DEFAULT '' NOT NULL,
  "last_name" character varying(64) DEFAULT '' NOT NULL,
  "address" character varying(64) DEFAULT '' NOT NULL,
  "email_address" character varying(64) DEFAULT '' NOT NULL,
  "mobile_phone" character varying(64) DEFAULT '' NOT NULL,
  "home_phone" character varying(64) DEFAULT '' NOT NULL,
  "password" character varying(128) DEFAULT '' NOT NULL,
  "notes" character varying(255),
  PRIMARY KEY ("id"),
  CONSTRAINT "person_name" UNIQUE ("name")
);
CREATE INDEX "person_idx_next_of_kin" on "person" ("next_of_kin");

DROP TABLE "type" CASCADE;
CREATE TABLE "type" (
  "id" serial NOT NULL,
  "name" character varying(32) DEFAULT '' NOT NULL,
  "type" character varying NOT NULL,
  PRIMARY KEY ("id")
);

DROP TABLE "endorsement" CASCADE;
CREATE TABLE "endorsement" (
  "recipient" integer NOT NULL,
  "points" smallint NOT NULL,
  "endorsed" timestamp NOT NULL,
  "code" character varying(16) DEFAULT '' NOT NULL,
  "notes" character varying(255),
  PRIMARY KEY ("recipient", "code")
);
CREATE INDEX "endorsement_idx_recipient" on "endorsement" ("recipient");

DROP TABLE "rota" CASCADE;
CREATE TABLE "rota" (
  "id" serial NOT NULL,
  "date" timestamp NOT NULL,
  "type" integer NOT NULL,
  PRIMARY KEY ("id")
);
CREATE INDEX "rota_idx_type" on "rota" ("type");

DROP TABLE "certification" CASCADE;
CREATE TABLE "certification" (
  "recipient" integer NOT NULL,
  "type" integer NOT NULL,
  "completed" timestamp NOT NULL,
  "notes" character varying(255),
  PRIMARY KEY ("recipient", "type")
);
CREATE INDEX "certification_idx_recipient" on "certification" ("recipient");
CREATE INDEX "certification_idx_type" on "certification" ("type");

DROP TABLE "role" CASCADE;
CREATE TABLE "role" (
  "member" integer NOT NULL,
  "type" integer NOT NULL,
  PRIMARY KEY ("member", "type")
);
CREATE INDEX "role_idx_member" on "role" ("member");
CREATE INDEX "role_idx_type" on "role" ("type");

DROP TABLE "shift" CASCADE;
CREATE TABLE "shift" (
  "id" serial NOT NULL,
  "rota" integer NOT NULL,
  "type" character varying DEFAULT 'day' NOT NULL,
  PRIMARY KEY ("id")
);
CREATE INDEX "shift_idx_rota" on "shift" ("rota");

DROP TABLE "vehicle" CASCADE;
CREATE TABLE "vehicle" (
  "id" serial NOT NULL,
  "type" integer NOT NULL,
  "owner" integer,
  "aquired" timestamp NOT NULL,
  "disposed" timestamp NOT NULL,
  "vrn" character varying(16) DEFAULT '' NOT NULL,
  "name" character varying(64) DEFAULT '' NOT NULL,
  "notes" character varying(255),
  PRIMARY KEY ("id")
);
CREATE INDEX "vehicle_idx_owner" on "vehicle" ("owner");
CREATE INDEX "vehicle_idx_type" on "vehicle" ("type");

DROP TABLE "event" CASCADE;
CREATE TABLE "event" (
  "id" serial NOT NULL,
  "rota" integer NOT NULL,
  "owner" integer NOT NULL,
  "start" timestamp NOT NULL,
  "end" timestamp NOT NULL,
  "name" character varying(64) DEFAULT '' NOT NULL,
  "description" character varying(128) DEFAULT '' NOT NULL,
  "notes" character varying(255),
  PRIMARY KEY ("id"),
  CONSTRAINT "event_name" UNIQUE ("name")
);
CREATE INDEX "event_idx_owner" on "event" ("owner");
CREATE INDEX "event_idx_rota" on "event" ("rota");

DROP TABLE "participent" CASCADE;
CREATE TABLE "participent" (
  "event" integer NOT NULL,
  "participent" integer NOT NULL,
  PRIMARY KEY ("event", "participent")
);
CREATE INDEX "participent_idx_event" on "participent" ("event");
CREATE INDEX "participent_idx_participent" on "participent" ("participent");

DROP TABLE "slot" CASCADE;
CREATE TABLE "slot" (
  "shift" integer NOT NULL,
  "type" character varying DEFAULT '0' NOT NULL,
  "subslot" smallint NOT NULL,
  "operator" integer NOT NULL,
  "bike_requested" boolean DEFAULT '0' NOT NULL,
  "vehicle_assigner" integer,
  "vehicle" integer,
  PRIMARY KEY ("shift", "type", "subslot")
);
CREATE INDEX "slot_idx_operator" on "slot" ("operator");
CREATE INDEX "slot_idx_shift" on "slot" ("shift");
CREATE INDEX "slot_idx_vehicle" on "slot" ("vehicle");
CREATE INDEX "slot_idx_vehicle_assigner" on "slot" ("vehicle_assigner");

DROP TABLE "transport" CASCADE;
CREATE TABLE "transport" (
  "event" integer NOT NULL,
  "vehicle" integer NOT NULL,
  "vehicle_assigner" integer NOT NULL,
  PRIMARY KEY ("event", "vehicle")
);
CREATE INDEX "transport_idx_event" on "transport" ("event");
CREATE INDEX "transport_idx_vehicle" on "transport" ("vehicle");
CREATE INDEX "transport_idx_vehicle_assigner" on "transport" ("vehicle_assigner");

ALTER TABLE "person" ADD CONSTRAINT "person_fk_next_of_kin" FOREIGN KEY ("next_of_kin")
  REFERENCES "person" ("id") DEFERRABLE;

ALTER TABLE "endorsement" ADD CONSTRAINT "endorsement_fk_recipient" FOREIGN KEY ("recipient")
  REFERENCES "person" ("id") ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE;

ALTER TABLE "rota" ADD CONSTRAINT "rota_fk_type" FOREIGN KEY ("type")
  REFERENCES "type" ("id") DEFERRABLE;

ALTER TABLE "certification" ADD CONSTRAINT "certification_fk_recipient" FOREIGN KEY ("recipient")
  REFERENCES "person" ("id") ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE;

ALTER TABLE "certification" ADD CONSTRAINT "certification_fk_type" FOREIGN KEY ("type")
  REFERENCES "type" ("id") DEFERRABLE;

ALTER TABLE "role" ADD CONSTRAINT "role_fk_member" FOREIGN KEY ("member")
  REFERENCES "person" ("id") ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE;

ALTER TABLE "role" ADD CONSTRAINT "role_fk_type" FOREIGN KEY ("type")
  REFERENCES "type" ("id") DEFERRABLE;

ALTER TABLE "shift" ADD CONSTRAINT "shift_fk_rota" FOREIGN KEY ("rota")
  REFERENCES "rota" ("id") ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE;

ALTER TABLE "vehicle" ADD CONSTRAINT "vehicle_fk_owner" FOREIGN KEY ("owner")
  REFERENCES "person" ("id") ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE;

ALTER TABLE "vehicle" ADD CONSTRAINT "vehicle_fk_type" FOREIGN KEY ("type")
  REFERENCES "type" ("id") DEFERRABLE;

ALTER TABLE "event" ADD CONSTRAINT "event_fk_owner" FOREIGN KEY ("owner")
  REFERENCES "person" ("id") DEFERRABLE;

ALTER TABLE "event" ADD CONSTRAINT "event_fk_rota" FOREIGN KEY ("rota")
  REFERENCES "rota" ("id") ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE;

ALTER TABLE "participent" ADD CONSTRAINT "participent_fk_event" FOREIGN KEY ("event")
  REFERENCES "event" ("id") ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE;

ALTER TABLE "participent" ADD CONSTRAINT "participent_fk_participent" FOREIGN KEY ("participent")
  REFERENCES "person" ("id") DEFERRABLE;

ALTER TABLE "slot" ADD CONSTRAINT "slot_fk_operator" FOREIGN KEY ("operator")
  REFERENCES "person" ("id") DEFERRABLE;

ALTER TABLE "slot" ADD CONSTRAINT "slot_fk_shift" FOREIGN KEY ("shift")
  REFERENCES "shift" ("id") ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE;

ALTER TABLE "slot" ADD CONSTRAINT "slot_fk_vehicle" FOREIGN KEY ("vehicle")
  REFERENCES "vehicle" ("id") DEFERRABLE;

ALTER TABLE "slot" ADD CONSTRAINT "slot_fk_vehicle_assigner" FOREIGN KEY ("vehicle_assigner")
  REFERENCES "person" ("id") DEFERRABLE;

ALTER TABLE "transport" ADD CONSTRAINT "transport_fk_event" FOREIGN KEY ("event")
  REFERENCES "event" ("id") ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE;

ALTER TABLE "transport" ADD CONSTRAINT "transport_fk_vehicle" FOREIGN KEY ("vehicle")
  REFERENCES "vehicle" ("id") DEFERRABLE;

ALTER TABLE "transport" ADD CONSTRAINT "transport_fk_vehicle_assigner" FOREIGN KEY ("vehicle_assigner")
  REFERENCES "person" ("id") DEFERRABLE;

