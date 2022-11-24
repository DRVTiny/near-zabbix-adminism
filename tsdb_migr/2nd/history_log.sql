DROP TABLE IF EXISTS history_log_old;
ALTER TABLE history_log RENAME TO history_log_old;
ALTER TABLE IF EXISTS history_log_new RENAME TO history_log;
CREATE INDEX history_log_1 on history_log (itemid,clock);
INSERT INTO history_log SELECT * FROM history_log_old WHERE clock>=$TS_NEW_DATA;
