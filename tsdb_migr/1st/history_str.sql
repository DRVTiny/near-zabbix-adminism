DROP TABLE IF EXISTS history_str_new;
CREATE TABLE history_str_new (LIKE history_str INCLUDING DEFAULTS INCLUDING CONSTRAINTS EXCLUDING INDEXES);
SELECT create_hypertable('history_str_new', 'clock', chunk_time_interval => 86400);
INSERT INTO history_str_new SELECT * FROM history_str WHERE clock>=$TS_NOT_BEFORE;
