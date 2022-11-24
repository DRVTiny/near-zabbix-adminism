DROP TABLE IF EXISTS history_log_new;
CREATE TABLE history_log_new (LIKE history_log INCLUDING DEFAULTS INCLUDING CONSTRAINTS EXCLUDING INDEXES);
SELECT create_hypertable('history_log_new', 'clock', chunk_time_interval => 86400);
INSERT INTO history_log_new SELECT * FROM history_log WHERE clock>=$TS_NOT_BEFORE;
