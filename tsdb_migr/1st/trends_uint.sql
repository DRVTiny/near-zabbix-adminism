DROP TABLE IF EXISTS trends_uint_new;
CREATE TABLE trends_uint_new (LIKE trends_uint INCLUDING DEFAULTS INCLUDING CONSTRAINTS EXCLUDING INDEXES);
SELECT create_hypertable('trends_uint_new', 'clock', chunk_time_interval => 2592000);
INSERT INTO trends_uint_new SELECT * FROM trends_uint WHERE clock>=$TS_NOT_BEFORE;
