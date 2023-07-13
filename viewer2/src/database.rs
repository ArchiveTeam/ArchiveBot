use std::{
    collections::HashMap,
    path::Path,
    sync::Arc,
    time::{SystemTime, UNIX_EPOCH},
};

use chrono::{DateTime, NaiveDate, NaiveDateTime, Utc};
use sqlx::{migrate::Migrator, Connection, SqliteConnection};
use tokio::sync::Mutex;

use crate::ia::{FileDetails, ItemInfo};

static MIGRATOR: Migrator = sqlx::migrate!("./migrations/");

#[derive(Debug, Clone)]
pub struct UpdateJobArgs<'a> {
    pub short_id: &'a str,
    pub job_id: &'a str,
    pub domain: &'a str,
    pub abort_inc: i64,
    pub warc_inc: i64,
    pub json_inc: i64,
    pub size_inc: i64,
}

#[derive(Debug, Clone)]
pub struct UpdateFilesJobArgs<'a> {
    pub ia_item_id: &'a str,
    pub filename: &'a str,
    pub job_id: &'a str,
}

#[derive(Debug, Clone)]
pub struct Database {
    connection: Arc<Mutex<SqliteConnection>>,
    id_generator: IdGenerator,
}

impl Database {
    pub async fn open(path: &Path) -> anyhow::Result<Self> {
        let url = format!("sqlite:{}?mode=rwc", path.to_str().unwrap());
        tracing::info!(url, "open database");

        let mut connection = SqliteConnection::connect(&url).await?;

        tracing::info!("running migrations");
        MIGRATOR.run(&mut connection).await?;

        Ok(Self {
            connection: Arc::new(Mutex::new(connection)),
            id_generator: IdGenerator::new(),
        })
    }

    pub async fn close(&self) -> anyhow::Result<()> {
        tracing::debug!("close");

        let dummy_connection = SqliteConnection::connect("sqlite::memory:").await?;

        let mut guard = self.connection.lock().await;
        let old_connection = std::mem::replace(&mut *guard, dummy_connection);

        old_connection.close();

        Ok(())
    }

    pub async fn get_last_update(&self) -> anyhow::Result<DateTime<Utc>> {
        tracing::debug!("get_last_update");
        let mut connection = self.connection.lock().await;

        let row = sqlx::query_scalar("SELECT value FROM app_metadata WHERE key = 'last_update'")
            .fetch_optional(&mut *connection)
            .await?;
        let oldest_date = DateTime::from_utc(NaiveDateTime::from_timestamp_opt(0, 0).unwrap(), Utc);

        match row {
            Some(row) => Ok(row),
            None => Ok(oldest_date),
        }
    }

    pub async fn set_last_update(&self) -> anyhow::Result<()> {
        tracing::debug!("set_last_update");
        let mut connection = self.connection.lock().await;

        sqlx::query(
            "INSERT OR REPLACE INTO app_metadata (key, value)
            VALUES ('last_update', ?)",
        )
        .bind(Utc::now())
        .execute(&mut *connection)
        .await?;

        Ok(())
    }

    pub async fn add_ia_items(&self, items: &[ItemInfo]) -> anyhow::Result<()> {
        tracing::debug!("add_ia_items");
        let mut connection = self.connection.lock().await;
        let mut transaction = connection.begin().await?;

        for item in items {
            sqlx::query(
                "INSERT INTO ia_items
                (id, added_date, public_date, image_count)
                VALUES (?, ?, ?, ?)
                ON CONFLICT (id) DO NOTHING",
            )
            .bind(&item.identifier)
            .bind(item.addeddate)
            .bind(item.publicdate)
            .bind(item.imagecount)
            .execute(&mut *transaction)
            .await?;
        }

        transaction.commit().await?;

        Ok(())
    }

    pub async fn get_ia_items_needing_refresh(
        &self,
        after_id: &str,
    ) -> anyhow::Result<Vec<String>> {
        tracing::debug!("get_ia_items_needing_refresh");
        let mut connection = self.connection.lock().await;
        let date_ago = Utc::now() - chrono::Duration::days(3);

        let rows = sqlx::query_scalar(
            "SELECT id FROM ia_items
            WHERE (refresh_date IS NULL OR public_date > ?)
            AND id > ?
            ORDER BY id
            LIMIT 10000",
        )
        .bind(date_ago)
        .bind(after_id)
        .fetch_all(&mut *connection)
        .await?;

        Ok(rows)
    }

    pub async fn set_ia_item_refresh_date(&self, identifier: &str) -> anyhow::Result<()> {
        tracing::debug!("set_ia_item_refresh_date");
        let mut connection = self.connection.lock().await;
        let mut transaction = connection.begin().await?;
        let date = Utc::now();

        sqlx::query("UPDATE ia_items SET refresh_date = ? WHERE id = ?")
            .bind(date)
            .bind(identifier)
            .execute(&mut *transaction)
            .await?;

        transaction.commit().await?;

        Ok(())
    }

    pub async fn add_item_files(
        &self,
        identifier: &str,
        files: &HashMap<String, FileDetails>,
    ) -> anyhow::Result<()> {
        tracing::debug!("add_item_files");
        let mut connection = self.connection.lock().await;
        let mut transaction = connection.begin().await?;

        for (name, details) in files {
            let filename = name.strip_prefix('/').unwrap_or(name);

            sqlx::query(
                "INSERT INTO files
                (ia_item_id, filename, size)
                VALUES (?, ?, ?)
                ON CONFLICT (ia_item_id, filename) DO NOTHING",
            )
            .bind(identifier)
            .bind(filename)
            .bind(details.size)
            .execute(&mut *transaction)
            .await?;
        }

        transaction.commit().await?;

        Ok(())
    }
    pub async fn get_files_without_job_id(
        &self,
        after_id: &str,
        after_filename: &str,
    ) -> anyhow::Result<Vec<(String, String, i64)>> {
        tracing::debug!("get_files_without_job_id");
        let mut connection = self.connection.lock().await;

        let rows = sqlx::query_as(
            "SELECT ia_item_id, filename, size FROM files
            WHERE job_id IS NULL
            AND (ia_item_id, filename) > (?, ?)
            ORDER BY ia_item_id, filename
            LIMIT 10000",
        )
        .bind(after_id)
        .bind(after_filename)
        .fetch_all(&mut *connection)
        .await?;

        Ok(rows)
    }

    pub async fn update_jobs(
        &self,
        jobs_args_list: &[UpdateJobArgs<'_>],
        files_args_list: &[UpdateFilesJobArgs<'_>],
    ) -> anyhow::Result<()> {
        tracing::trace!("update_job");
        let mut connection = self.connection.lock().await;
        let mut transaction = connection.begin().await?;

        for args in jobs_args_list {
            sqlx::query(
                "INSERT INTO jobs (id, short_id, domain)
                VALUES (?, ?, ?)
                ON CONFLICT (id) DO NOTHING",
            )
            .bind(args.job_id)
            .bind(args.short_id)
            .bind(args.domain)
            .execute(&mut *transaction)
            .await?;

            sqlx::query(
                "UPDATE jobs
                SET aborts = aborts + ?, warcs = warcs + ?, jsons = jsons + ?, size = size + ?
                WHERE id = ?",
            )
            .bind(args.abort_inc)
            .bind(args.warc_inc)
            .bind(args.json_inc)
            .bind(args.size_inc)
            .bind(args.job_id)
            .execute(&mut *transaction)
            .await?;
        }

        for args in files_args_list {
            sqlx::query(
                "UPDATE files SET job_id = ?
                WHERE ia_item_id = ? AND filename = ?",
            )
            .bind(args.job_id)
            .bind(args.ia_item_id)
            .bind(args.filename)
            .execute(&mut *transaction)
            .await?;
        }

        transaction.commit().await?;

        Ok(())
    }

    pub async fn populate_daily_stats(&self) -> anyhow::Result<()> {
        tracing::debug!("populate_daily_stats");
        let mut connection = self.connection.lock().await;

        let dates: Vec<NaiveDate> =
            sqlx::query_scalar("SELECT substr(public_date, 0, 11) FROM ia_items")
                .fetch_all(&mut *connection)
                .await?;

        for dates in dates.chunks(100) {
            let mut transaction = connection.begin().await?;

            for date in dates {
                let size: i64 = sqlx::query_scalar(
                    "SELECT sum(files.size) FROM files
                    JOIN ia_items ON files.ia_item_id = ia_items.id
                    WHERE substr(ia_items.public_date, 0, 11) = ?",
                )
                .bind(date)
                .fetch_one(&mut *transaction)
                .await?;

                sqlx::query("INSERT OR REPLACE INTO daily_stats (date, size) VALUES (?, ?)")
                    .bind(date)
                    .bind(size)
                    .execute(&mut *transaction)
                    .await?;
            }

            transaction.commit().await?;
        }

        Ok(())
    }

    pub async fn get_jobs_without_url(
        &self,
        after_id: &str,
        after_filename: &str,
    ) -> anyhow::Result<Vec<(String, String, String)>> {
        tracing::debug!("get_jobs_without_url");
        let mut connection = self.connection.lock().await;

        let rows = sqlx::query_as(
            "SELECT ia_item_id, filename, job_id FROM files
            WHERE filename LIKE '%.json' AND job_id NOT NULL
            AND (ia_item_id, filename) > (?, ?)
            ORDER BY ia_item_id, filename
            LIMIT 10000",
        )
        .bind(after_id)
        .bind(after_filename)
        .fetch_all(&mut *connection)
        .await?;

        Ok(rows)
    }

    pub async fn add_job_url(
        &self,
        job_id: &str,
        url: &str,
        started_by: &str,
    ) -> anyhow::Result<()> {
        tracing::debug!("add_job_url");
        let mut connection = self.connection.lock().await;
        let mut transaction = connection.begin().await?;

        sqlx::query("UPDATE jobs SET url = ?, started_by = ? WHERE id = ?")
            .bind(url)
            .bind(started_by)
            .bind(job_id)
            .execute(&mut *transaction)
            .await?;

        sqlx::query(
            "UPDATE jobs_search_index SET url = ?
            WHERE rowid IN (SELECT search_id FROM jobs WHERE id = ?)",
        )
        .bind(url)
        .bind(job_id)
        .execute(&mut *transaction)
        .await?;

        transaction.commit().await?;

        Ok(())
    }

    pub async fn get_jobs_without_search(&self, after_id: &str) -> anyhow::Result<Vec<String>> {
        tracing::debug!("get_jobs_without_search");
        let mut connection = self.connection.lock().await;

        let rows = sqlx::query_scalar(
            "SELECT id FROM jobs
            WHERE search_id IS NULL
            AND id > ?
            ORDER BY id
            LIMIT 10000",
        )
        .bind(after_id)
        .fetch_all(&mut *connection)
        .await?;

        Ok(rows)
    }

    pub async fn add_job_search_rows(&mut self, job_ids: &[String]) -> anyhow::Result<()> {
        tracing::debug!("add_job_search_rows");
        let mut connection = self.connection.lock().await;
        let mut transaction = connection.begin().await?;

        for job_id in job_ids {
            sqlx::query("UPDATE jobs SET search_id = ? WHERE id = ?")
                .bind(self.id_generator.generate())
                .bind(job_id)
                .execute(&mut *transaction)
                .await?;
            sqlx::query(
                "INSERT INTO jobs_search_index (rowid, domain, url)
                SELECT search_id, domain, url FROM jobs WHERE jobs.id = ?",
            )
            .bind(job_id)
            .execute(&mut *transaction)
            .await?;
        }

        transaction.commit().await?;

        Ok(())
    }

    pub async fn search_domain(
        &self,
        query: &str,
        offset: i64,
        limit: i64,
    ) -> anyhow::Result<Vec<(String, String, String)>> {
        let connection = &mut *self.connection.lock().await;
        let query = format_fts_query(query);
        let rows = sqlx::query_as(
            "SELECT id, domain, url FROM jobs_search_index
            WHERE domain MATCH ?
            ORDER BY rank
            LIMIT ? OFFSET ?",
        )
        .bind(&query)
        .bind(limit)
        .bind(offset)
        .fetch_all(connection)
        .await?;

        Ok(rows)
    }

    pub async fn search_full(
        &self,
        query_domain: &str,
        query_url: &str,
        offset: i64,
        limit: i64,
    ) -> anyhow::Result<Vec<(String, String, String)>> {
        let connection = &mut *self.connection.lock().await;
        let query_domain = format_fts_query(query_domain);
        let query_url = format_fts_query(query_url);
        let rows = sqlx::query_as(
            "SELECT id, domain, url FROM jobs_search_index
            WHERE domain MATCH ?
            OR url MATCH ?
            ORDER BY rank
            LIMIT ? OFFSET ?",
        )
        .bind(&query_domain)
        .bind(&query_url)
        .bind(limit)
        .bind(offset)
        .fetch_all(connection)
        .await?;

        Ok(rows)
    }

    pub async fn search_job_id(
        &self,
        query: &str,
        offset: i64,
        limit: i64,
    ) -> anyhow::Result<Vec<(String, String, String)>> {
        if !query.is_ascii() {
            return Ok(Vec::new());
        }

        let connection = &mut *self.connection.lock().await;

        let rows = sqlx::query_as(
            "SELECT id, domain, url FROM jobs
            WHERE id = ? OR short_id = ?
            ORDER BY id
            LIMIT ? OFFSET ?",
        )
        .bind(query)
        .bind(&query[0..5.min(query.len())])
        .bind(limit)
        .bind(offset)
        .fetch_all(connection)
        .await?;

        Ok(rows)
    }

    pub async fn get_no_json_jobs(&self) -> anyhow::Result<Vec<(String, String)>> {
        let connection = &mut *self.connection.lock().await;

        let rows = sqlx::query_as("SELECT id, domain from JOBS WHERE jsons = 0 ")
            .fetch_all(connection)
            .await?;

        Ok(rows)
    }

    pub async fn get_no_warc_jobs(&self) -> anyhow::Result<Vec<(String, String)>> {
        let connection = &mut *self.connection.lock().await;

        let rows = sqlx::query_as("SELECT id, domain from JOBS WHERE warcs = 0")
            .fetch_all(connection)
            .await?;

        Ok(rows)
    }

    pub async fn get_daily_stats(&self) -> anyhow::Result<Vec<(NaiveDate, i64)>> {
        let connection = &mut *self.connection.lock().await;

        let rows = sqlx::query_as("SELECT date, size FROM daily_stats")
            .fetch_all(connection)
            .await?;

        Ok(rows)
    }

    pub async fn get_domains(&self, limit: i64, offset: i64) -> anyhow::Result<Vec<String>> {
        let connection = &mut *self.connection.lock().await;

        let rows = sqlx::query_scalar(
            "SELECT domain FROM jobs
            GROUP BY domain
            ORDER BY domain
            LIMIT ? OFFSET ?",
        )
        .bind(limit)
        .bind(offset)
        .fetch_all(connection)
        .await?;

        Ok(rows)
    }

    pub async fn get_items(&self, limit: i64, offset: i64) -> anyhow::Result<Vec<String>> {
        let connection = &mut *self.connection.lock().await;

        let rows = sqlx::query_scalar("SELECT id FROM ia_items LIMIT ? OFFSET ?")
            .bind(limit)
            .bind(offset)
            .fetch_all(connection)
            .await?;

        Ok(rows)
    }

    pub async fn get_jobs(
        &self,
        limit: i64,
        offset: i64,
    ) -> anyhow::Result<Vec<(String, String, String)>> {
        let connection = &mut *self.connection.lock().await;

        let rows = sqlx::query_as("SELECT id, domain, url FROM jobs LIMIT ? OFFSET ?")
            .bind(limit)
            .bind(offset)
            .fetch_all(connection)
            .await?;

        Ok(rows)
    }

    pub async fn get_jobs_by_domain(&self, domain: &str) -> anyhow::Result<Vec<(String, String)>> {
        let connection = &mut *self.connection.lock().await;

        let rows = sqlx::query_as("SELECT id, url FROM jobs WHERE domain = ?")
            .bind(domain)
            .fetch_all(connection)
            .await?;

        Ok(rows)
    }

    pub async fn get_files_by_job(
        &self,
        job_id: &str,
    ) -> anyhow::Result<Vec<(String, String, i64)>> {
        let connection = &mut *self.connection.lock().await;

        let rows = sqlx::query_as(
            "SELECT ia_item_id, filename, size
            FROM files
            WHERE job_id = ?",
        )
        .bind(job_id)
        .fetch_all(connection)
        .await?;

        Ok(rows)
    }

    pub async fn get_files_by_item(
        &self,
        identifier: &str,
    ) -> anyhow::Result<Vec<(String, String, i64)>> {
        let connection = &mut *self.connection.lock().await;

        let rows = sqlx::query_as(
            "SELECT filename, job_id, size
            FROM files
            WHERE ia_item_id = ?",
        )
        .bind(identifier)
        .fetch_all(connection)
        .await?;

        Ok(rows)
    }

    pub async fn get_cost_leaderboard(&self) -> anyhow::Result<Vec<(String, i64)>> {
        let connection = &mut *self.connection.lock().await;

        let rows = sqlx::query_as(
            "SELECT lower(substr(started_by, 1, 4)) AS nick, sum(size) AS sum_size
            FROM jobs
            GROUP BY nick
            ORDER BY sum_size DESC",
        )
        .fetch_all(connection)
        .await?;

        Ok(rows)
    }
}

fn format_fts_query(query: &str) -> String {
    format!("\"{}\"*", query.replace('"', "\"\""))
}

#[derive(Debug, Clone)]
struct IdGenerator {
    counter: u16,
}

impl IdGenerator {
    fn new() -> Self {
        let unix_duration = SystemTime::now().duration_since(UNIX_EPOCH).unwrap();

        Self {
            counter: unix_duration.as_millis() as u16,
        }
    }

    fn generate(&mut self) -> i64 {
        let unix_duration = SystemTime::now().duration_since(UNIX_EPOCH).unwrap();

        let id = ((unix_duration.as_millis() as i64) << 16) | self.counter as i64;
        self.counter = self.counter.wrapping_add(1);

        id
    }
}
