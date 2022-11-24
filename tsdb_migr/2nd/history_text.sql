DROP TABLE IF EXISTS history_text_old;
ALTER TABLE history_text RENAME TO history_text_old;
ALTER TABLE IF EXISTS history_text_new RENAME TO history_text;
CREATE INDEX history_text_1 on history_text (itemid,clock);
INSERT INTO history_text SELECT * FROM history_text_old WHERE clock>=$TS_NEW_DATA;
