CREATE INDEX short_id_index ON jobs (short_id) where short_id NOT NULL;
CREATE INDEX ia_items_date_index ON ia_items (substr(public_date, 0, 11));

ALTER TABLE jobs ADD search_id INTEGER;
CREATE UNIQUE INDEX jobs_search_id_index ON jobs (search_id);

CREATE VIRTUAL TABLE jobs_search_index
USING fts5(
    id UNINDEXED,
    domain,
    url,
    content='jobs',
    content_rowid='search_id'
);
