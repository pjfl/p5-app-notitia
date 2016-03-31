SET foreign_key_checks=0;

DROP TABLE IF EXISTS `person`;

CREATE TABLE `person` (
  `id` integer unsigned NOT NULL auto_increment,
  `next_of_kin` integer unsigned NULL,
  `active` enum('0','1') NOT NULL DEFAULT '0',
  `password_expired` enum('0','1') NOT NULL DEFAULT '1',
  `dob` datetime NULL DEFAULT '0000-00-00',
  `joined` datetime NULL DEFAULT '0000-00-00',
  `resigned` datetime NULL DEFAULT '0000-00-00',
  `subscription` datetime NULL DEFAULT '0000-00-00',
  `shortcode` varchar(6) NOT NULL DEFAULT '',
  `name` varchar(64) NOT NULL DEFAULT '',
  `password` varchar(128) NOT NULL DEFAULT '',
  `first_name` varchar(30) NOT NULL DEFAULT '',
  `last_name` varchar(30) NOT NULL DEFAULT '',
  `address` varchar(64) NOT NULL DEFAULT '',
  `postcode` varchar(16) NOT NULL DEFAULT '',
  `email_address` varchar(64) NOT NULL DEFAULT '',
  `mobile_phone` varchar(32) NOT NULL DEFAULT '',
  `home_phone` varchar(32) NOT NULL DEFAULT '',
  `notes` varchar(255) NOT NULL DEFAULT '',
  INDEX `person_idx_next_of_kin` (`next_of_kin`),
  PRIMARY KEY (`id`),
  UNIQUE `person_email_address` (`email_address`),
  UNIQUE `person_name` (`name`),
  UNIQUE `person_shortcode` (`shortcode`),
  CONSTRAINT `person_fk_next_of_kin` FOREIGN KEY (`next_of_kin`) REFERENCES `person` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `type`;

CREATE TABLE `type` (
  `id` integer unsigned NOT NULL auto_increment,
  `name` varchar(32) NOT NULL DEFAULT '',
  `type_class` enum('certification', 'role', 'rota', 'vehicle') NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE `type_name_type_class` (`name`, `type_class`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `endorsement`;

CREATE TABLE `endorsement` (
  `recipient_id` integer unsigned NOT NULL,
  `points` smallint NOT NULL,
  `endorsed` datetime NULL DEFAULT '0000-00-00',
  `type_code` varchar(25) NOT NULL DEFAULT '',
  `uri` varchar(32) NOT NULL DEFAULT '',
  `notes` varchar(255) NOT NULL DEFAULT '',
  INDEX `endorsement_idx_recipient_id` (`recipient_id`),
  PRIMARY KEY (`recipient_id`, `type_code`),
  UNIQUE `endorsement_uri` (`uri`),
  CONSTRAINT `endorsement_fk_recipient_id` FOREIGN KEY (`recipient_id`) REFERENCES `person` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `rota`;

CREATE TABLE `rota` (
  `id` integer unsigned NOT NULL auto_increment,
  `type_id` integer unsigned NOT NULL,
  `date` datetime NULL DEFAULT '0000-00-00',
  INDEX `rota_idx_type_id` (`type_id`),
  PRIMARY KEY (`id`),
  UNIQUE `rota_type_id_date` (`type_id`, `date`),
  CONSTRAINT `rota_fk_type_id` FOREIGN KEY (`type_id`) REFERENCES `type` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `certification`;

CREATE TABLE `certification` (
  `recipient_id` integer unsigned NOT NULL,
  `type_id` integer unsigned NOT NULL,
  `completed` datetime NULL DEFAULT '0000-00-00',
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
  `aquired` datetime NULL DEFAULT '0000-00-00',
  `disposed` datetime NULL DEFAULT '0000-00-00',
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
  `rota_id` integer unsigned NOT NULL,
  `owner_id` integer unsigned NOT NULL,
  `start_time` varchar(5) NOT NULL DEFAULT '',
  `end_time` varchar(5) NOT NULL DEFAULT '',
  `name` varchar(57) NOT NULL DEFAULT '',
  `uri` varchar(64) NOT NULL DEFAULT '',
  `description` varchar(128) NOT NULL DEFAULT '',
  `notes` varchar(255) NOT NULL DEFAULT '',
  INDEX `event_idx_owner_id` (`owner_id`),
  INDEX `event_idx_rota_id` (`rota_id`),
  PRIMARY KEY (`id`),
  UNIQUE `event_uri` (`uri`),
  CONSTRAINT `event_fk_owner_id` FOREIGN KEY (`owner_id`) REFERENCES `person` (`id`),
  CONSTRAINT `event_fk_rota_id` FOREIGN KEY (`rota_id`) REFERENCES `rota` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
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

DROP TABLE IF EXISTS `vehicle_request`;

CREATE TABLE `vehicle_request` (
  `event_id` integer unsigned NOT NULL,
  `type_id` integer unsigned NOT NULL,
  `quantity` smallint NOT NULL,
  INDEX `vehicle_request_idx_event_id` (`event_id`),
  INDEX `vehicle_request_idx_type_id` (`type_id`),
  PRIMARY KEY (`event_id`, `type_id`),
  CONSTRAINT `vehicle_request_fk_event_id` FOREIGN KEY (`event_id`) REFERENCES `event` (`id`),
  CONSTRAINT `vehicle_request_fk_type_id` FOREIGN KEY (`type_id`) REFERENCES `type` (`id`)
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
  CONSTRAINT `slot_fk_operator_id` FOREIGN KEY (`operator_id`) REFERENCES `person` (`id`),
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

SET foreign_key_checks=1;

