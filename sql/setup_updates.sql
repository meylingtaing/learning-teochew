PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
CREATE TABLE updates (
    id integer primary key,
    time_stamp timestamp default current_timestamp,
    content text
);
COMMIT;
