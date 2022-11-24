DROP TABLE IF EXISTS history_uint_old;
ALTER TABLE history_uint RENAME TO history_uint_old;
ALTER TABLE IF EXISTS history_uint_new RENAME TO history_uint;
CREATE INDEX history_uint_1 on history_uint (itemid,clock);
INSERT INTO history_uint SELECT * FROM history_uint_old WHERE clock>=$TS_NEW_DATA;
