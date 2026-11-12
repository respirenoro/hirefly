-- HireFly lesson sample (fictional). The small dataset used by every worked example in the SQL lessons.
-- SQLite-compatible; the table and column names match practice.sql. Load it into an empty database.
CREATE TABLE pharmacies (id INT PRIMARY KEY, name VARCHAR(80), city VARCHAR(40), state CHAR(2));
INSERT INTO pharmacies (id, name, city, state) VALUES
(1, 'Riverside Pharmacy', 'Austin', 'TX'),
(2, 'Maple Drug', 'Dallas', 'TX'),
(3, 'Harbor Health Rx', 'Houston', 'TX'),
(4, 'Oak Street Pharmacy', 'Austin', 'TX');

CREATE TABLE pharmacists (id INT PRIMARY KEY, name VARCHAR(80), license_state CHAR(2), active INT);
INSERT INTO pharmacists (id, name, license_state, active) VALUES
(10, 'Dana Ortiz', 'TX', 1),
(11, 'Sam Lee', 'TX', 1),
(12, 'Priya Nair', 'OK', 1),
(13, 'Chris Boyd', 'TX', 1);

-- is_emergency: shifts 102, 105 and 108 are emergency requests (used only in unit 8 and later lessons).
CREATE TABLE shifts (id INT PRIMARY KEY, pharmacy_id INT, pharmacist_id INT, requested_at TEXT, filled_at TEXT,
                     starts_at TEXT, status VARCHAR(20), cancel_reason VARCHAR(30), is_emergency INT);
INSERT INTO shifts (id, pharmacy_id, pharmacist_id, requested_at, filled_at, starts_at, status, cancel_reason, is_emergency) VALUES
(101, 1, 10,   '2026-03-02 08:00:00', '2026-03-02 09:30:00', '2026-03-03 09:00:00', 'completed', NULL, 0),
(102, 1, 11,   '2026-03-05 10:00:00', '2026-03-05 10:45:00', '2026-03-06 09:00:00', 'completed', NULL, 1),
(103, 2, NULL, '2026-03-08 07:00:00', NULL,                  '2026-03-09 09:00:00', 'cancelled', 'no coverage', 0),
(104, 2, 12,   '2026-03-12 14:00:00', '2026-03-12 18:00:00', '2026-03-15 09:00:00', 'completed', NULL, 0),
(105, 3, 10,   '2026-04-01 09:00:00', '2026-04-01 09:20:00', '2026-04-02 09:00:00', 'completed', NULL, 1),
(106, 3, NULL, '2026-04-04 11:00:00', NULL,                  '2026-04-05 09:00:00', 'cancelled', 'pharmacy cancelled', 0),
(107, 1, NULL, '2026-04-10 08:00:00', NULL,                  '2026-04-12 09:00:00', 'open', NULL, 0),
(108, 2, 11,   '2026-04-15 13:00:00', '2026-04-15 15:00:00', '2026-04-16 09:00:00', 'cancelled', 'pharmacist cancelled', 1);

CREATE TABLE assignments (id INT PRIMARY KEY, shift_id INT, pharmacist_id INT, status VARCHAR(20), completed_at TEXT);
INSERT INTO assignments (id, shift_id, pharmacist_id, status, completed_at) VALUES
(1, 101, 10, 'completed', '2026-03-03 17:00:00'),
(2, 102, 11, 'completed', '2026-03-06 17:00:00'),
(3, 104, 12, 'completed', '2026-03-15 17:00:00'),
(4, 105, 10, 'completed', '2026-04-02 17:00:00'),
(5, 108, 11, 'cancelled', NULL);
