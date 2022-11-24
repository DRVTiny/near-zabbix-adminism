DROP TABLE IF EXISTS history_str_old;
ALTER TABLE history_str RENAME TO history_str_old;
ALTER TABLE IF EXISTS history_str_new RENAME TO history_str;
CREATE INDEX history_str_1 on history_str (itemid,clock);
INSERT INTO history_str SELECT * FROM history_str_old WHERE clock>=$TS_NEW_DATA;
