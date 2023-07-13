use std::{collections::HashMap, path::Path, time::Duration};

use chrono::{DateTime, NaiveDate, Utc};
use serde::Serialize;

use crate::{
    database::{Database, UpdateFilesJobArgs, UpdateJobArgs},
    ia::{FileDetails, IAClient, ItemDetails, ItemInfo, JsonMetadata},
};

#[derive(Debug, Clone)]
pub struct Backend {
    database: Database,
}

impl Backend {
    pub async fn open(data_dir: &Path) -> anyhow::Result<Self> {
        let db_path = data_dir.join("archivebot_2.db");
        let database = Database::open(&db_path).await?;
        Ok(Self { database })
    }

    pub async fn close(&self) -> anyhow::Result<()> {
        self.database.close().await
    }

    pub async fn run(&mut self) -> anyhow::Result<()> {
        loop {
            self.populate().await?;
            tokio::time::sleep(Duration::from_secs(3600 * 6)).await;
        }
    }

    pub async fn run_test_data(&mut self) -> anyhow::Result<()> {
        loop {
            self.populate_test_data().await?;
            tokio::time::sleep(Duration::from_secs(3600 * 6)).await;
        }
    }

    async fn populate(&mut self) -> anyhow::Result<()> {
        let last_update = self.database.get_last_update().await?;
        let now = Utc::now();

        if now - last_update < chrono::Duration::hours(4) {
            tracing::debug!("not populating database");
            return Ok(());
        }

        match self.populate_steps().await {
            Ok(_) => {}
            Err(error) => tracing::error!(error = ?error, "populate error"),
        }

        self.database.set_last_update().await?;

        Ok(())
    }

    async fn populate_steps(&mut self) -> anyhow::Result<()> {
        tracing::info!("populate steps begin");

        self.populate_ia_items().await?;
        self.populate_files().await?;
        self.populate_jobs().await?;
        self.populate_daily_stats().await?;

        // FIXME: Takes too long. As of 2023, about 400,000 files will need to be fetched.
        // This should probably be a background step.
        // self.populate_json_urls().await?;

        self.populate_search().await?;

        tracing::info!("populate steps end");

        Ok(())
    }

    async fn populate_ia_items(&mut self) -> anyhow::Result<()> {
        tracing::info!("populate ia items");

        let after_date = self.database.get_last_update().await?;
        let after_date = after_date - chrono::Duration::days(7);
        let mut client = IAClient::new()?;

        loop {
            let items = client.fetch_items(Some(after_date)).await?;

            self.database.add_ia_items(&items).await?;

            if !client.has_more_items() {
                break;
            }
        }

        Ok(())
    }

    async fn populate_files(&mut self) -> anyhow::Result<()> {
        tracing::info!("populate files");

        let mut client = IAClient::new()?;
        let mut after_id = String::new();

        loop {
            let identifiers = self
                .database
                .get_ia_items_needing_refresh(&after_id)
                .await?;

            if identifiers.is_empty() {
                break;
            }

            for identifier in &identifiers {
                let item_details = client.fetch_item_files(identifier).await?;

                self.database
                    .add_item_files(identifier, &item_details.files)
                    .await?;
                self.database.set_ia_item_refresh_date(identifier).await?;
                tokio::time::sleep(Duration::from_secs_f64(0.5)).await;

                after_id = identifier.to_owned();
            }
        }

        Ok(())
    }

    async fn populate_jobs(&mut self) -> anyhow::Result<()> {
        tracing::info!("populate jobs");

        struct JobData {
            short_id: String,
            domain: String,
            abort_count: i64,
            warc_count: i64,
            json_count: i64,
            size: i64,
        }

        let mut after_id = (String::new(), String::new());

        loop {
            let files = self
                .database
                .get_files_without_job_id(&after_id.0, &after_id.1)
                .await?;

            if files.is_empty() {
                break;
            }

            let mut jobs_cache = HashMap::<String, JobData>::new();
            let mut files_cache = HashMap::<(String, String), String>::new();

            for (ia_item_id, filename, size) in &files {
                if let Some(filename_info) = crate::ia::parse_filename(filename) {
                    let job_id = {
                        if filename_info.ident.is_empty() {
                            format!("{}{}", filename_info.date, filename_info.time)
                        } else {
                            format!(
                                "{}{}{}",
                                filename_info.date, filename_info.time, filename_info.ident
                            )
                        }
                    };

                    let aborted = !filename_info.aborted.is_empty();
                    let is_warc = filename_info.extension == "warc.gz";
                    let is_json = filename_info.extension == "json";
                    let size = if is_warc { *size } else { 0 };

                    if !jobs_cache.contains_key(&job_id) {
                        jobs_cache.insert(
                            job_id.clone(),
                            JobData {
                                short_id: filename_info.ident,
                                domain: filename_info.domain,
                                abort_count: 0,
                                warc_count: 0,
                                json_count: 0,
                                size: 0,
                            },
                        );
                    }

                    let mut data = jobs_cache.get_mut(&job_id).unwrap();

                    if aborted {
                        data.abort_count += 1;
                    }
                    if is_warc {
                        data.warc_count += 1;
                    }
                    if is_json {
                        data.json_count += 1;
                    }

                    data.size += size;

                    files_cache.insert((ia_item_id.to_string(), filename.to_string()), job_id);
                }

                after_id = (ia_item_id.to_owned(), filename.to_owned());
            }

            let mut args = Vec::new();
            let mut files_args = Vec::new();

            for (job_id, data) in &jobs_cache {
                args.push(UpdateJobArgs {
                    short_id: &data.short_id,
                    job_id,
                    domain: &data.domain,
                    abort_inc: data.abort_count,
                    warc_inc: data.warc_count,
                    json_inc: data.json_count,
                    size_inc: data.size,
                });
            }

            for ((ia_item_id, filename), job_id) in &files_cache {
                files_args.push(UpdateFilesJobArgs {
                    ia_item_id,
                    filename,
                    job_id,
                });
            }

            self.database.update_jobs(&args, &files_args).await?;
        }

        Ok(())
    }

    async fn populate_daily_stats(&mut self) -> anyhow::Result<()> {
        tracing::info!("populate daily stats");

        self.database.populate_daily_stats().await?;

        Ok(())
    }

    async fn populate_json_urls(&mut self) -> anyhow::Result<()> {
        tracing::info!("populate json urls");

        let mut client = IAClient::new()?;

        let mut after_id = (String::new(), String::new());

        loop {
            let rows = self
                .database
                .get_jobs_without_url(&after_id.0, &after_id.1)
                .await?;

            if rows.is_empty() {
                break;
            }

            for (ia_item_id, filename, job_id) in rows {
                let json_data = client.fetch_item_file(&ia_item_id, &filename).await?;
                let json_doc = serde_json::from_slice::<JsonMetadata>(&json_data)?;

                self.database
                    .add_job_url(
                        &job_id,
                        json_doc.url.as_deref().unwrap_or_default(),
                        json_doc.started_by.as_deref().unwrap_or_default(),
                    )
                    .await?;
                tokio::time::sleep(Duration::from_secs_f64(0.5)).await;

                after_id = (ia_item_id, filename);
            }
        }

        Ok(())
    }

    async fn populate_search(&mut self) -> anyhow::Result<()> {
        tracing::info!("populate_search");

        let mut after_id = String::new();

        loop {
            let job_ids = self.database.get_jobs_without_search(&after_id).await?;

            if job_ids.is_empty() {
                break;
            }

            self.database
                .add_job_search_rows(job_ids.as_slice())
                .await?;

            after_id = job_ids.last().unwrap().to_owned();
        }

        Ok(())
    }

    async fn populate_test_data(&mut self) -> anyhow::Result<()> {
        tracing::info!("populate_test_data");

        let items = vec![ItemInfo {
            identifier: "test_item_1".to_string(),
            addeddate: "3000-01-01T00:00:00Z".parse().unwrap(),
            publicdate: "3000-01-01T00:00:00Z".parse().unwrap(),
            imagecount: Some(123),
        }];

        self.database.add_ia_items(&items).await?;

        let mut files = HashMap::<String, FileDetails>::new();
        files.insert(
            "example.com-inf-30000101-000000-abcde.warc.gz".to_string(),
            FileDetails { size: 123 },
        );
        files.insert(
            "example.com-inf-30000101-000000-abcde.json".to_string(),
            FileDetails { size: 123 },
        );
        let item_details = ItemDetails { files };
        self.database
            .add_item_files("test_item_1", &item_details.files)
            .await?;
        self.database
            .set_ia_item_refresh_date("test_item_1")
            .await?;

        self.populate_jobs().await?;
        self.populate_daily_stats().await?;

        self.database
            .add_job_url(
                "30000101000000abcde",
                "http://example.com/hello-world/",
                "username",
            )
            .await?;

        self.populate_search().await?;

        tracing::info!("populate_test_data end");

        Ok(())
    }

    pub async fn search(
        &self,
        query: &str,
        full: bool,
        limit: i64,
        offset: i64,
    ) -> anyhow::Result<Vec<SearchResult>> {
        let mut rows = Vec::new();

        rows.extend(self.search_job(query, limit, offset).await?);
        rows.extend(self.search_link(query, full, limit, offset).await?);

        Ok(rows)
    }

    async fn search_job(
        &self,
        query: &str,
        limit: i64,
        offset: i64,
    ) -> anyhow::Result<Vec<SearchResult>> {
        let rows = self.database.search_job_id(query, offset, limit).await?;
        let rows = rows
            .into_iter()
            .map(|row| SearchResult {
                result_type: "job".to_string(),
                job_id: row.0,
                domain: row.1,
                url: row.2,
            })
            .collect();

        Ok(rows)
    }

    async fn search_link(
        &self,
        query: &str,
        full: bool,
        limit: i64,
        offset: i64,
    ) -> anyhow::Result<Vec<SearchResult>> {
        let query = query.strip_prefix("https://").unwrap_or(query);
        let query = query.strip_prefix("http://").unwrap_or(query);
        let query = query.strip_prefix("ftp://").unwrap_or(query);
        let query = query.strip_prefix("www.").unwrap_or(query);
        let query_domain = idna::domain_to_ascii(query).unwrap_or_default();

        let rows = {
            if full {
                self.database
                    .search_full(&query_domain, query, offset, limit)
                    .await?
            } else {
                self.database.search_domain(&query_domain, offset, limit).await?
            }
        };

        let rows = rows.into_iter().map(|row| SearchResult {
            result_type: "domain".to_string(),
            job_id: row.0,
            domain: row.1,
            url: row.2,
        });

        Ok(rows.collect())
    }

    pub async fn get_last_update(&self) -> anyhow::Result<DateTime<Utc>> {
        self.database.get_last_update().await
    }

    pub async fn get_audit_no_json_items(&self) -> anyhow::Result<Vec<AuditItem>> {
        let rows = self.database.get_no_json_jobs().await?;
        let rows = rows
            .into_iter()
            .map(|row| AuditItem {
                job_id: row.0,
                domain: row.1,
            })
            .collect();

        Ok(rows)
    }

    pub async fn get_audit_no_warc_items(&self) -> anyhow::Result<Vec<AuditItem>> {
        let rows = self.database.get_no_warc_jobs().await?;
        let rows = rows
            .into_iter()
            .map(|row| AuditItem {
                job_id: row.0,
                domain: row.1,
            })
            .collect();

        Ok(rows)
    }

    pub async fn get_daily_stats(&self) -> anyhow::Result<Vec<(NaiveDate, i64)>> {
        self.database.get_daily_stats().await
    }

    pub async fn get_domains(&self, limit: i64, offset: i64) -> anyhow::Result<Vec<String>> {
        self.database.get_domains(limit, offset).await
    }

    pub async fn get_domain(&self, domain: &str) -> anyhow::Result<Vec<DomainRow>> {
        let rows = self.database.get_jobs_by_domain(domain).await?;

        let rows = rows
            .into_iter()
            .map(|row| DomainRow {
                job_id: row.0,
                url: row.1,
            })
            .collect();

        Ok(rows)
    }

    pub async fn get_items(&self, limit: i64, offset: i64) -> anyhow::Result<Vec<String>> {
        self.database.get_items(limit, offset).await
    }

    pub async fn get_item(&self, identifier: &str) -> anyhow::Result<Vec<ItemRow>> {
        let rows = self.database.get_files_by_item(identifier).await?;

        let rows = rows
            .into_iter()
            .map(|row| ItemRow {
                filename: row.0,
                job_id: row.1,
                size: row.2,
            })
            .collect();

        Ok(rows)
    }

    pub async fn get_jobs(&self, limit: i64, offset: i64) -> anyhow::Result<Vec<JobsRow>> {
        let rows = self.database.get_jobs(limit, offset).await?;

        let rows = rows
            .into_iter()
            .map(|row| JobsRow {
                job_id: row.0,
                domain: row.1,
                url: row.2,
            })
            .collect();

        Ok(rows)
    }

    pub async fn get_job(&self, job_id: &str) -> anyhow::Result<Vec<JobRow>> {
        let rows = self.database.get_files_by_job(job_id).await?;

        let mut rows = rows
            .into_iter()
            .map(|row| JobRow {
                ia_item_id: row.0,
                filename: row.1,
                size: row.2,
            })
            .collect::<Vec<JobRow>>();

        if rows.is_empty() {
            let job_ids = self
                .database
                .search_job_id(job_id, 0, 100)
                .await?
                .into_iter()
                .map(|row| row.0)
                .collect::<Vec<String>>();

            for job_id in &job_ids {
                let search_rows = self.database.get_files_by_job(job_id).await?;
                rows.extend(search_rows.into_iter().map(|row| JobRow {
                    ia_item_id: row.0,
                    filename: row.1,
                    size: row.2,
                }));
            }
        }

        Ok(rows)
    }

    pub async fn get_cost_leaderboard(&self) -> anyhow::Result<Vec<CostRow>> {
        let rows = self.database.get_cost_leaderboard().await?;

        let rows = rows
            .into_iter()
            .map(|row| CostRow {
                who: row.0,
                size: row.1,
            })
            .collect();

        Ok(rows)
    }
}

#[derive(Serialize)]
pub struct SearchResult {
    pub result_type: String,
    pub job_id: String,
    pub domain: String,
    pub url: String,
}

pub struct AuditItem {
    pub job_id: String,
    pub domain: String,
}

pub struct DomainRow {
    pub job_id: String,
    pub url: String,
}

pub struct ItemRow {
    pub filename: String,
    pub size: i64,
    pub job_id: String,
}

pub struct JobsRow {
    pub job_id: String,
    pub domain: String,
    pub url: String,
}

pub struct JobRow {
    pub ia_item_id: String,
    pub filename: String,
    pub size: i64,
}

pub struct CostRow {
    pub who: String,
    pub size: i64,
}
