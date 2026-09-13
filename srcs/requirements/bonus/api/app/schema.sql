-- srcs/requirements/bonus/api/app/schema.sql
-- Applied on every boot by db.migrate(). Every statement is idempotent.

-- A flight is a named batch of packets dispatched from one cabinet of the
-- machine room to another. Status advances with age on the API's minute tick.
CREATE TABLE IF NOT EXISTS flights (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  callsign    VARCHAR(16)  NOT NULL,
  origin      VARCHAR(16)  NOT NULL,
  destination VARCHAR(16)  NOT NULL,
  status      ENUM('boarding','en-route','landed','diverted') NOT NULL DEFAULT 'boarding',
  payload_kb  INT UNSIGNED NOT NULL DEFAULT 1,
  note        VARCHAR(140) NOT NULL DEFAULT '',
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_flights_callsign (callsign),
  KEY ix_flights_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS guestbook (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  handle     VARCHAR(24)  NOT NULL,
  message    VARCHAR(280) NOT NULL,
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY ix_guestbook_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Durable copy of the Redis counters (Redis here has no persistence and evicts
-- under memory pressure). Written through every few seconds, read back on boot.
CREATE TABLE IF NOT EXISTS stats (
  name       VARCHAR(32)     NOT NULL PRIMARY KEY,
  value      BIGINT UNSIGNED NOT NULL DEFAULT 0,
  updated_at TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Seed: the first departures board. INSERT IGNORE keys on the unique callsign,
-- so a second boot changes nothing.
INSERT IGNORE INTO flights (callsign, origin, destination, status, payload_kb, note) VALUES
  ('PKT-0001', 'nginx',     'wordpress', 'landed',  14, 'first TLS handshake of the day, stamped'),
  ('PKT-0002', 'wordpress', 'mariadb',   'landed',  3,  'SELECT option_value FROM wp_options'),
  ('PKT-0003', 'mariadb',   'wordpress', 'landed',  212,'rowset hauled up by the dolphin'),
  ('PKT-0004', 'wordpress', 'redis',     'landed',  1,  'object cache warm-up'),
  ('PKT-0005', 'redis',     'wordpress', 'landed',  1,  'cache hit, imp did not wake'),
  ('PKT-0006', 'nginx',     'web',       'landed',  27, 'static bytes off disk'),
  ('PKT-0007', 'nginx',     'api',       'landed',  2,  'GET /api/v1/healthz'),
  ('PKT-0008', 'api',       'mariadb',   'landed',  5,  'schema applied, idempotent'),
  ('PKT-0009', 'api',       'redis',     'landed',  1,  'counters hydrated');
