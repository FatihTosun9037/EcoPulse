-- EcoPulse OSB veritabanı
-- telemetry_data (machine_id, timestamp) bileşik indeksi hızlı büyüyen tablo içindir.

CREATE DATABASE IF NOT EXISTS ecopulse
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE ecopulse;

CREATE TABLE IF NOT EXISTS machines (
  machine_id INT AUTO_INCREMENT PRIMARY KEY,
  machine_name VARCHAR(100) NOT NULL,
  location VARCHAR(100) NULL,
  nominal_current FLOAT NOT NULL,
  max_temperature FLOAT NOT NULL,
  surface_area_m2 FLOAT NOT NULL DEFAULT 2.0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS telemetry_data (
  data_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  machine_id INT NOT NULL,
  voltage FLOAT NOT NULL,
  current_amp FLOAT NOT NULL,
  temperature FLOAT NOT NULL,
  active_power_kw FLOAT NOT NULL,
  timestamp DATETIME NOT NULL,
  INDEX idx_machine_time (machine_id, timestamp),
  CONSTRAINT fk_telemetry_machine
    FOREIGN KEY (machine_id) REFERENCES machines (machine_id)
    ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS anomalies (
  anomaly_id INT AUTO_INCREMENT PRIMARY KEY,
  machine_id INT NOT NULL,
  anomaly_type VARCHAR(50) NOT NULL,
  severity VARCHAR(20) NOT NULL,
  financial_loss_tl FLOAT NOT NULL,
  co2_impact_kg FLOAT NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME NOT NULL,
  INDEX idx_anomalies_status (status),
  INDEX idx_anomalies_open (machine_id, anomaly_type, status),
  CONSTRAINT fk_anomalies_machine
    FOREIGN KEY (machine_id) REFERENCES machines (machine_id)
    ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS work_orders (
  work_order_id INT AUTO_INCREMENT PRIMARY KEY,
  anomaly_id INT NOT NULL,
  machine_id INT NOT NULL,
  note VARCHAR(255) NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'OPEN',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_work_orders_anomaly
    FOREIGN KEY (anomaly_id) REFERENCES anomalies (anomaly_id)
    ON DELETE CASCADE,
  CONSTRAINT fk_work_orders_machine
    FOREIGN KEY (machine_id) REFERENCES machines (machine_id)
    ON DELETE CASCADE
) ENGINE=InnoDB;

-- ECOPULSE_FORMULAS — Engellenen CO2, müdahale ile kapanan (RESOLVED) alarmların toplamıdır.
CREATE OR REPLACE VIEW kpi_engellenen_co2 AS
SELECT COALESCE(SUM(co2_impact_kg), 0) AS engellenen_co2_kg
FROM anomalies
WHERE status = 'RESOLVED';
