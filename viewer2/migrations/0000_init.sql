-- sqlite3

-- Workaround transactions
-- https://github.com/launchbadge/sqlx/issues/2085
COMMIT;
PRAGMA journal_mode = WAL;
BEGIN TRANSACTION;


CREATE TABLE app_metadata (
    key TEXT PRIMARY KEY,
    value TEXT
) WITHOUT ROWID;

CREATE TABLE ia_items (
    id TEXT PRIMARY KEY,
    added_date TEXT NOT NULL,
    public_date TEXT NOT NULL,
    image_count INTEGER,
    refresh_date TEXT
) WITHOUT ROWID;

CREATE TABLE files (
    ia_item_id TEXT NOT NULL,
    filename TEXT NOT NULL,
    size INTEGER NOT NULL,
    job_id TEXT,
    PRIMARY KEY(ia_item_id, filename),
    FOREIGN KEY(ia_item_id) REFERENCES ia_items(id),
    FOREIGN KEY(job_id) REFERENCES jobs(id)
) WITHOUT ROWID;

CREATE INDEX files_job_id_fk_index ON files(job_id) WHERE job_id NOT NULL;

CREATE TABLE jobs (
    id TEXT NOT NULL PRIMARY KEY,
    short_id TEXT NOT NULL,
    domain TEXT NOT NULL,
    url TEXT,
    started_by TEXT,
    aborts INTEGER DEFAULT 0,
    warcs INTEGER DEFAULT 0,
    jsons INTEGER DEFAULT 0,
    size INTEGER DEFAULT 0
) WITHOUT ROWID;

CREATE TABLE daily_stats (
    date TEXT NOT NULL PRIMARY KEY,
    size INTEGER
) WITHOUT ROWID;
