DROP TABLE IF EXISTS trends_new;
CREATE TABLE trends_new (LIKE trends INCLUDING DEFAULTS INCLUDING CONSTRAINTS EXCLUDING INDEXES);
SELECT create_hypertable('trends_new', 'clock', chunk_time_interval => 2592000);
INSERT INTO trends_new SELECT * FROM trends WHERE clock>=$TS_NOT_BEFORE;
