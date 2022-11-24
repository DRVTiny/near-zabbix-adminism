DROP TABLE IF EXISTS trends_uint_old;
ALTER TABLE trends_uint RENAME TO trends_uint_old;
ALTER TABLE IF EXISTS trends_uint_new RENAME TO trends_uint;
INSERT INTO trends_uint SELECT * FROM trends_uint_old WHERE clock>=$TS_NEW_DATA;
