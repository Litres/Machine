DROP DATABASE IF EXISTS machine_test;

CREATE DATABASE machine_test;
USE machine_test;

DROP USER 'machine'@'localhost';
CREATE USER 'machine'@'localhost' IDENTIFIED BY 'password';
GRANT USAGE ON *.* TO 'machine' IDENTIFIED BY 'password'; 
GRANT ALL PRIVILEGES ON machine_test.* TO 'machine'@'localhost';

CREATE TABLE test_rmd (
	id tinyint(3) unsigned NOT NULL auto_increment PRIMARY KEY,
	name varchar(255),
	ddate datetime
) ENGINE=InnoDB CHARACTER SET=UTF8;

CREATE TABLE test_rmd_h2 (
	key1 tinyint(3) unsigned NOT NULL,
	xml_text varchar(255),
	p tinyint(3) NOT NULL default 0,
	KEY k (key1),
	FOREIGN KEY (key1) REFERENCES test_rmd (id) ON DELETE CASCADE
) ENGINE=InnoDB CHARACTER SET=UTF8;

CREATE TABLE test_rmd_h3 (
	art tinyint(3) unsigned NOT NULL,
	t tinyint(3) NOT NULL default 0,
	KEY art (art),
	FOREIGN KEY (art) REFERENCES test_rmd (id) ON DELETE CASCADE
) ENGINE=InnoDB CHARACTER SET=UTF8;

INSERT INTO test_rmd VALUES
(1, 'name uno', '2017-01-01 00:00:00'),
(2, 'cheloveki', '2017-02-15 19:06:00'),
(3, 'roboti', '2014-02-15 19:06:00'),
(4, 'faight', '2017-02-15 19:06:00'),
(5, 'chokolate', '2010-01-19 10:06:00'),
(6, 'system of down', '2017-02-15 19:06:00'),
(7, 'lamp', '2017-02-15 19:06:00'),
(8, 'archlinux', '2017-02-15 19:06:00');

INSERT INTO test_rmd_h2 VALUES
(1, '<t1>litres</t1>', 0),
(2, '<tt><boo var="661563"/></tt>', -12),
(3, '<h1>Tema</h1>', 35),
(3, '<ghost in="the shell"/>', 96),
(5, '<jojo/>', -25),
(6, '<moon is="chees"/>', -1),
(6, '<b/>', 0),
(6, '<test x="1"/>', 42);

INSERT INTO test_rmd_h3 VALUES
(1, 111),
(2, 12),
(3, 33),
(4, 44),
(5, 55),
(6, 66),
(7, 77),
(8, 88);
