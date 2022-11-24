DROP TABLE IF EXISTS trends_old;
ALTER TABLE trends RENAME TO trends_old;
ALTER TABLE IF EXISTS trends_new RENAME TO trends;
INSERT INTO trends SELECT * FROM trends_old WHERE clock>=$TS_NEW_DATA;
