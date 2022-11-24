DROP TABLE IF EXISTS history_old;
ALTER TABLE history RENAME TO history_old;
ALTER TABLE IF EXISTS history_new RENAME TO history;
CREATE INDEX history_1 on history (itemid,clock);
INSERT INTO history SELECT * FROM history_old WHERE clock>=$TS_NEW_DATA;
