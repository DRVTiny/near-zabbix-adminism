DROP TABLE IF EXISTS history_text_new;
CREATE TABLE history_text_new (LIKE history_text INCLUDING DEFAULTS INCLUDING CONSTRAINTS EXCLUDING INDEXES);
SELECT create_hypertable('history_text_new', 'clock', chunk_time_interval => 86400);
INSERT INTO history_text_new SELECT * FROM history_text WHERE clock>=$TS_NOT_BEFORE;
