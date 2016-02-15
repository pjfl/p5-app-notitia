SET foreign_key_checks=0;

DROP TABLE IF EXISTS `person`;

CREATE TABLE `person` (
  `id` integer unsigned NOT NULL auto_increment,
  `next_of_kin` integer unsigned NULL,
  `active` enum('0','1') NOT NULL DEFAULT '0',
  `password_expired` enum('0','1') NOT NULL DEFAULT '1',
  `dob` datetime NOT NULL,
  `joined` datetime NOT NULL,
  `resigned` datetime NOT NULL,
  `subscription` datetime NOT NULL,
  `postcode` varchar(16) NOT NULL DEFAULT '',
  `name` varchar(64) NOT NULL DEFAULT '',
  `first_name` varchar(64) NOT NULL DEFAULT '',
  `last_name` varchar(64) NOT NULL DEFAULT '',
  `address` varchar(64) NOT NULL DEFAULT '',
  `email_address` varchar(64) NOT NULL DEFAULT '',
  `mobile_phone` varchar(64) NOT NULL DEFAULT '',
  `home_phone` varchar(64) NOT NULL DEFAULT '',
  `password` varchar(128) NOT NULL DEFAULT '',
  `notes` varchar(255) NULL,
  INDEX `person_idx_next_of_kin` (`next_of_kin`),
  PRIMARY KEY (`id`),
  UNIQUE `person_name` (`name`),
  CONSTRAINT `person_fk_next_of_kin` FOREIGN KEY (`next_of_kin`) REFERENCES `person` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `type`;

CREATE TABLE `type` (
  `id` integer unsigned NOT NULL auto_increment,
  `name` varchar(32) NOT NULL DEFAULT '',
  `type` enum('certification', 'role', 'rota', 'vehicle') NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `endorsement`;

CREATE TABLE `endorsement` (
  `recipient` integer unsigned NOT NULL,
  `points` smallint NOT NULL,
  `endorsed` datetime NOT NULL,
  `code` varchar(16) NOT NULL DEFAULT '',
  `notes` varchar(255) NULL,
  INDEX `endorsement_idx_recipient` (`recipient`),
  PRIMARY KEY (`recipient`, `code`),
  CONSTRAINT `endorsement_fk_recipient` FOREIGN KEY (`recipient`) REFERENCES `person` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `rota`;

CREATE TABLE `rota` (
  `id` integer unsigned NOT NULL auto_increment,
  `date` datetime NOT NULL,
  `type` integer unsigned NOT NULL,
  INDEX `rota_idx_type` (`type`),
  PRIMARY KEY (`id`),
  CONSTRAINT `rota_fk_type` FOREIGN KEY (`type`) REFERENCES `type` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `certification`;

CREATE TABLE `certification` (
  `recipient` integer unsigned NOT NULL,
  `type` integer unsigned NOT NULL,
  `completed` datetime NOT NULL,
  `notes` varchar(255) NULL,
  INDEX `certification_idx_recipient` (`recipient`),
  INDEX `certification_idx_type` (`type`),
  PRIMARY KEY (`recipient`, `type`),
  CONSTRAINT `certification_fk_recipient` FOREIGN KEY (`recipient`) REFERENCES `person` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `certification_fk_type` FOREIGN KEY (`type`) REFERENCES `type` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `role`;

CREATE TABLE `role` (
  `member` integer unsigned NOT NULL,
  `type` integer unsigned NOT NULL,
  INDEX `role_idx_member` (`member`),
  INDEX `role_idx_type` (`type`),
  PRIMARY KEY (`member`, `type`),
  CONSTRAINT `role_fk_member` FOREIGN KEY (`member`) REFERENCES `person` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `role_fk_type` FOREIGN KEY (`type`) REFERENCES `type` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `shift`;

CREATE TABLE `shift` (
  `id` integer unsigned NOT NULL auto_increment,
  `rota` integer unsigned NOT NULL,
  `type` enum('day', 'night') NOT NULL DEFAULT 'day',
  INDEX `shift_idx_rota` (`rota`),
  PRIMARY KEY (`id`),
  CONSTRAINT `shift_fk_rota` FOREIGN KEY (`rota`) REFERENCES `rota` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `vehicle`;

CREATE TABLE `vehicle` (
  `id` integer unsigned NOT NULL auto_increment,
  `type` integer unsigned NOT NULL,
  `owner` integer unsigned NULL,
  `aquired` datetime NOT NULL,
  `disposed` datetime NOT NULL,
  `vrn` varchar(16) NOT NULL DEFAULT '',
  `name` varchar(64) NOT NULL DEFAULT '',
  `notes` varchar(255) NULL,
  INDEX `vehicle_idx_owner` (`owner`),
  INDEX `vehicle_idx_type` (`type`),
  PRIMARY KEY (`id`),
  CONSTRAINT `vehicle_fk_owner` FOREIGN KEY (`owner`) REFERENCES `person` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `vehicle_fk_type` FOREIGN KEY (`type`) REFERENCES `type` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `event`;

CREATE TABLE `event` (
  `id` integer unsigned NOT NULL auto_increment,
  `rota` integer unsigned NOT NULL,
  `owner` integer unsigned NOT NULL,
  `start` datetime NOT NULL,
  `end` datetime NOT NULL,
  `name` varchar(64) NOT NULL DEFAULT '',
  `description` varchar(128) NOT NULL DEFAULT '',
  `notes` varchar(255) NULL,
  INDEX `event_idx_owner` (`owner`),
  INDEX `event_idx_rota` (`rota`),
  PRIMARY KEY (`id`),
  UNIQUE `event_name` (`name`),
  CONSTRAINT `event_fk_owner` FOREIGN KEY (`owner`) REFERENCES `person` (`id`),
  CONSTRAINT `event_fk_rota` FOREIGN KEY (`rota`) REFERENCES `rota` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `participent`;

CREATE TABLE `participent` (
  `event` integer unsigned NOT NULL,
  `participent` integer unsigned NOT NULL,
  INDEX `participent_idx_event` (`event`),
  INDEX `participent_idx_participent` (`participent`),
  PRIMARY KEY (`event`, `participent`),
  CONSTRAINT `participent_fk_event` FOREIGN KEY (`event`) REFERENCES `event` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `participent_fk_participent` FOREIGN KEY (`participent`) REFERENCES `person` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `slot`;

CREATE TABLE `slot` (
  `shift` integer unsigned NOT NULL,
  `type` enum('controller', 'driver', 'rider', '0') NOT NULL DEFAULT '0',
  `subslot` smallint NOT NULL,
  `operator` integer unsigned NOT NULL,
  `bike_requested` enum('0','1') NOT NULL DEFAULT '0',
  `vehicle_assigner` integer unsigned NULL,
  `vehicle` integer unsigned NULL,
  INDEX `slot_idx_operator` (`operator`),
  INDEX `slot_idx_shift` (`shift`),
  INDEX `slot_idx_vehicle` (`vehicle`),
  INDEX `slot_idx_vehicle_assigner` (`vehicle_assigner`),
  PRIMARY KEY (`shift`, `type`, `subslot`),
  CONSTRAINT `slot_fk_operator` FOREIGN KEY (`operator`) REFERENCES `person` (`id`),
  CONSTRAINT `slot_fk_shift` FOREIGN KEY (`shift`) REFERENCES `shift` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `slot_fk_vehicle` FOREIGN KEY (`vehicle`) REFERENCES `vehicle` (`id`),
  CONSTRAINT `slot_fk_vehicle_assigner` FOREIGN KEY (`vehicle_assigner`) REFERENCES `person` (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `transport`;

CREATE TABLE `transport` (
  `event` integer unsigned NOT NULL,
  `vehicle` integer unsigned NOT NULL,
  `vehicle_assigner` integer unsigned NOT NULL,
  INDEX `transport_idx_event` (`event`),
  INDEX `transport_idx_vehicle` (`vehicle`),
  INDEX `transport_idx_vehicle_assigner` (`vehicle_assigner`),
  PRIMARY KEY (`event`, `vehicle`),
  CONSTRAINT `transport_fk_event` FOREIGN KEY (`event`) REFERENCES `event` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `transport_fk_vehicle` FOREIGN KEY (`vehicle`) REFERENCES `vehicle` (`id`),
  CONSTRAINT `transport_fk_vehicle_assigner` FOREIGN KEY (`vehicle_assigner`) REFERENCES `person` (`id`)
) ENGINE=InnoDB;

SET foreign_key_checks=1;

