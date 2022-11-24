DROP TABLE IF EXISTS history_uint_new;
CREATE TABLE history_uint_new (LIKE history_uint INCLUDING DEFAULTS INCLUDING CONSTRAINTS EXCLUDING INDEXES);
SELECT create_hypertable('history_uint_new', 'clock', chunk_time_interval => 86400);
INSERT INTO history_uint_new SELECT * FROM history_uint WHERE clock>=$TS_NOT_BEFORE;
