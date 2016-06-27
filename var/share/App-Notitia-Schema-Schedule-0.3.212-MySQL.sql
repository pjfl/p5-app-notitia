SET foreign_key_checks=0;

DROP TABLE IF EXISTS `job`;

CREATE TABLE `job` (
  `id` integer unsigned NOT NULL auto_increment,
  `name` varchar(32) NOT NULL DEFAULT '',
  `command` text NOT NULL DEFAULT '',
  PRIMARY KEY (`id`)
);

DROP TABLE IF EXISTS `person`;

CREATE TABLE `person` (
  `id` integer unsigned NOT NULL auto_increment,
  `next_of_kin_id` integer unsigned NULL,
  `active` enum('0','1') NOT NULL DEFAULT '0',
  `password_expired` enum('0','1') NOT NULL DEFAULT '1',
  `badge_expires` datetime NULL,
  `dob` datetime NULL,
  `joined` datetime NULL,
  `resigned` datetime NULL,
  `subscription` datetime NULL,
  `badge_id` smallint NULL,
  `rows_per_page` smallint NOT NULL DEFAULT 20,
  `shortcode` varchar(8) NOT NULL DEFAULT '',
  `name` varchar(64) NOT NULL DEFAULT '',
  `password` varchar(128) NOT NULL DEFAULT '',
  `first_name` varchar(32) NOT NULL DEFAULT '',
  `last_name` varchar(32) NOT NULL DEFAULT '',
  `address` varchar(64) NOT NULL DEFAULT '',
  `postcode` varchar(16) NOT NULL DEFAULT '',
  `location` varchar(24) NOT NULL DEFAULT '',
  `coordinates` varchar(16) NOT NULL DEFAULT '',
  `email_address` varchar(64) NOT NULL DEFAULT '',
  `mobile_phone` varchar(16) NOT NULL DEFAULT '',
  `home_phone` varchar(16) NOT NULL DEFAULT '',
  `totp_secret` varchar(16) NOT NULL DEFAULT '',
  `region` varchar(1) NOT NULL DEFAULT '',
  `notes` varchar(255) NOT NULL DEFAULT '',
  INDEX `person_idx_next_of_kin_id` (`next_of_kin_id`),
  PRIMARY KEY (`id`),
  UNIQUE `person_badge_id` (`badge_id`),
  UNIQUE `person_email_address` (`email_address`),
  UNIQUE `person_name` (`name`),
  UNIQUE `person_shortcode` (`shortcode`),
  CONSTRAINT `person_fk_next_of_kin_id` FOREIGN KEY (`next_of_kin_id`) REFERENCES `person` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `type`;

CREATE TABLE `type` (
  `id` integer unsigned NOT NULL auto_increment,
  `name` varchar(32) NOT NULL DEFAULT '',
  `type_class` enum('certification', 'event', 'role', 'rota', 'vehicle') NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE `type_name_type_class` (`name`, `type_class`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `endorsement`;

CREATE TABLE `endorsement` (
  `recipient_id` integer unsigned NOT NULL,
  `points` smallint NOT NULL,
  `endorsed` datetime NOT NULL,
  `type_code` varchar(25) NOT NULL DEFAULT '',
  `uri` varchar(32) NOT NULL DEFAULT '',
  `notes` varchar(255) NOT NULL DEFAULT '',
  INDEX `endorsement_idx_recipient_id` (`recipient_id`),
  PRIMARY KEY (`recipient_id`, `type_code`, `endorsed`),
  UNIQUE `endorsement_uri` (`uri`),
  CONSTRAINT `endorsement_fk_recipient_id` FOREIGN KEY (`recipient_id`) REFERENCES `person` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `rota`;

CREATE TABLE `rota` (
  `id` integer unsigned NOT NULL auto_increment,
  `type_id` integer unsigned NOT NULL,
  `date` datetime NULL,
  INDEX `rota_idx_type_id` (`type_id`),
  INDEX `rota_idx_date` (`date`),
  PRIMARY KEY (`id`),
  UNIQUE `rota_type_id_date` (`type_id`, `date`),
  CONSTRAINT `rota_fk_type_id` FOREIGN KEY (`type_id`) REFERENCES `type` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `slot_criteria`;

CREATE TABLE `slot_criteria` (
  `slot_type` enum('controller', 'rider', 'driver', '0') NOT NULL DEFAULT '0',
  `certification_type_id` integer unsigned NOT NULL,
  INDEX `slot_criteria_idx_certification_type_id` (`certification_type_id`),
  PRIMARY KEY (`slot_type`, `certification_type_id`),
  CONSTRAINT `slot_criteria_fk_certification_type_id` FOREIGN KEY (`certification_type_id`) REFERENCES `type` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `certification`;

CREATE TABLE `certification` (
  `recipient_id` integer unsigned NOT NULL,
  `type_id` integer unsigned NOT NULL,
  `completed` datetime NULL,
  `notes` varchar(255) NOT NULL DEFAULT '',
  INDEX `certification_idx_recipient_id` (`recipient_id`),
  INDEX `certification_idx_type_id` (`type_id`),
  PRIMARY KEY (`recipient_id`, `type_id`),
  CONSTRAINT `certification_fk_recipient_id` FOREIGN KEY (`recipient_id`) REFERENCES `person` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `certification_fk_type_id` FOREIGN KEY (`type_id`) REFERENCES `type` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `role`;

CREATE TABLE `role` (
  `member_id` integer unsigned NOT NULL,
  `type_id` integer unsigned NOT NULL,
  INDEX `role_idx_member_id` (`member_id`),
  INDEX `role_idx_type_id` (`type_id`),
  PRIMARY KEY (`member_id`, `type_id`),
  CONSTRAINT `role_fk_member_id` FOREIGN KEY (`member_id`) REFERENCES `person` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `role_fk_type_id` FOREIGN KEY (`type_id`) REFERENCES `type` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `shift`;

CREATE TABLE `shift` (
  `id` integer unsigned NOT NULL auto_increment,
  `rota_id` integer unsigned NOT NULL,
  `type_name` enum('day', 'night') NOT NULL DEFAULT 'day',
  INDEX `shift_idx_rota_id` (`rota_id`),
  PRIMARY KEY (`id`),
  CONSTRAINT `shift_fk_rota_id` FOREIGN KEY (`rota_id`) REFERENCES `rota` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `vehicle`;

CREATE TABLE `vehicle` (
  `id` integer unsigned NOT NULL auto_increment,
  `type_id` integer unsigned NOT NULL,
  `owner_id` integer unsigned NULL,
  `aquired` datetime NULL,
  `disposed` datetime NULL,
  `colour` varchar(16) NOT NULL DEFAULT '',
  `vrn` varchar(16) NOT NULL DEFAULT '',
  `name` varchar(64) NOT NULL DEFAULT '',
  `notes` varchar(255) NOT NULL DEFAULT '',
  INDEX `vehicle_idx_owner_id` (`owner_id`),
  INDEX `vehicle_idx_type_id` (`type_id`),
  PRIMARY KEY (`id`),
  UNIQUE `vehicle_vrn` (`vrn`),
  CONSTRAINT `vehicle_fk_owner_id` FOREIGN KEY (`owner_id`) REFERENCES `person` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `vehicle_fk_type_id` FOREIGN KEY (`type_id`) REFERENCES `type` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `event`;

CREATE TABLE `event` (
  `id` integer unsigned NOT NULL auto_increment,
  `event_type_id` integer unsigned NOT NULL,
  `owner_id` integer unsigned NOT NULL,
  `start_rota_id` integer unsigned NOT NULL,
  `end_rota_id` integer unsigned NULL,
  `vehicle_id` integer unsigned NULL,
  `max_participents` smallint NULL,
  `start_time` varchar(5) NOT NULL DEFAULT '',
  `end_time` varchar(5) NOT NULL DEFAULT '',
  `name` varchar(57) NOT NULL DEFAULT '',
  `uri` varchar(64) NOT NULL DEFAULT '',
  `description` varchar(128) NOT NULL DEFAULT '',
  `notes` varchar(255) NOT NULL DEFAULT '',
  INDEX `event_idx_end_rota_id` (`end_rota_id`),
  INDEX `event_idx_event_type_id` (`event_type_id`),
  INDEX `event_idx_owner_id` (`owner_id`),
  INDEX `event_idx_start_rota_id` (`start_rota_id`),
  INDEX `event_idx_vehicle_id` (`vehicle_id`),
  PRIMARY KEY (`id`),
  UNIQUE `event_uri` (`uri`),
  CONSTRAINT `event_fk_end_rota_id` FOREIGN KEY (`end_rota_id`) REFERENCES `rota` (`id`),
  CONSTRAINT `event_fk_event_type_id` FOREIGN KEY (`event_type_id`) REFERENCES `type` (`id`),
  CONSTRAINT `event_fk_owner_id` FOREIGN KEY (`owner_id`) REFERENCES `person` (`id`),
  CONSTRAINT `event_fk_start_rota_id` FOREIGN KEY (`start_rota_id`) REFERENCES `rota` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `event_fk_vehicle_id` FOREIGN KEY (`vehicle_id`) REFERENCES `vehicle` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `participent`;

CREATE TABLE `participent` (
  `event_id` integer unsigned NOT NULL,
  `participent_id` integer unsigned NOT NULL,
  INDEX `participent_idx_event_id` (`event_id`),
  INDEX `participent_idx_participent_id` (`participent_id`),
  PRIMARY KEY (`event_id`, `participent_id`),
  CONSTRAINT `participent_fk_event_id` FOREIGN KEY (`event_id`) REFERENCES `event` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `participent_fk_participent_id` FOREIGN KEY (`participent_id`) REFERENCES `person` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `slot`;

CREATE TABLE `slot` (
  `shift_id` integer unsigned NOT NULL,
  `operator_id` integer unsigned NOT NULL,
  `type_name` enum('controller', 'rider', 'driver', '0') NOT NULL DEFAULT '0',
  `subslot` smallint NOT NULL,
  `bike_requested` enum('0','1') NOT NULL DEFAULT '0',
  `vehicle_assigner_id` integer unsigned NULL,
  `vehicle_id` integer unsigned NULL,
  INDEX `slot_idx_operator_id` (`operator_id`),
  INDEX `slot_idx_shift_id` (`shift_id`),
  INDEX `slot_idx_vehicle_id` (`vehicle_id`),
  INDEX `slot_idx_vehicle_assigner_id` (`vehicle_assigner_id`),
  PRIMARY KEY (`shift_id`, `type_name`, `subslot`),
  CONSTRAINT `slot_fk_operator_id` FOREIGN KEY (`operator_id`) REFERENCES `person` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `slot_fk_shift_id` FOREIGN KEY (`shift_id`) REFERENCES `shift` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `slot_fk_vehicle_id` FOREIGN KEY (`vehicle_id`) REFERENCES `vehicle` (`id`),
  CONSTRAINT `slot_fk_vehicle_assigner_id` FOREIGN KEY (`vehicle_assigner_id`) REFERENCES `person` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `transport`;

CREATE TABLE `transport` (
  `event_id` integer unsigned NOT NULL,
  `vehicle_id` integer unsigned NOT NULL,
  `vehicle_assigner_id` integer unsigned NOT NULL,
  INDEX `transport_idx_event_id` (`event_id`),
  INDEX `transport_idx_vehicle_id` (`vehicle_id`),
  INDEX `transport_idx_vehicle_assigner_id` (`vehicle_assigner_id`),
  PRIMARY KEY (`event_id`, `vehicle_id`),
  CONSTRAINT `transport_fk_event_id` FOREIGN KEY (`event_id`) REFERENCES `event` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `transport_fk_vehicle_id` FOREIGN KEY (`vehicle_id`) REFERENCES `vehicle` (`id`),
  CONSTRAINT `transport_fk_vehicle_assigner_id` FOREIGN KEY (`vehicle_assigner_id`) REFERENCES `person` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `vehicle_request`;

CREATE TABLE `vehicle_request` (
  `event_id` integer unsigned NOT NULL,
  `type_id` integer unsigned NOT NULL,
  `quantity` smallint NOT NULL,
  INDEX `vehicle_request_idx_event_id` (`event_id`),
  INDEX `vehicle_request_idx_type_id` (`type_id`),
  PRIMARY KEY (`event_id`, `type_id`),
  CONSTRAINT `vehicle_request_fk_event_id` FOREIGN KEY (`event_id`) REFERENCES `event` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `vehicle_request_fk_type_id` FOREIGN KEY (`type_id`) REFERENCES `type` (`id`)
) ENGINE=InnoDB;

SET foreign_key_checks=1;

