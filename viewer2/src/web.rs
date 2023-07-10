use std::net::SocketAddr;

use askama::Template;
use axum::{
    extract::{Path, Query, State},
    response::IntoResponse,
    routing::get,
    Json, Router, Server,
};
use chrono::{DateTime, Datelike, NaiveDate, Utc};
use serde::Deserialize;

use crate::backend::{
    AuditItem, Backend, CostRow, DomainRow, ItemRow, JobRow, JobsRow, SearchResult,
};

const PAGE_LIMIT: i64 = 1000;

#[derive(Debug, Clone)]
struct WebState {
    link_prefix: String,
    backend: Backend,
}

pub async fn run(address: SocketAddr, link_prefix: &str, backend: Backend) -> anyhow::Result<()> {
    let router = Router::new()
        .route("/", get(index_handler))
        .route("/faq", get(faq_handler))
        .route("/audit", get(audit_handler))
        .route("/stats", get(stats_handler))
        .route("/domains", get(domains_handler))
        .route("/domain/:domain", get(domain_handler))
        .route("/items", get(items_handler))
        .route("/item/:item_id", get(item_handler))
        .route("/jobs", get(jobs_handler))
        .route("/job/:job_id", get(job_handler))
        .route("/costs", get(cost_leaderboard_handler))
        .route("/api/v1/search.json", get(api_v1_search_handler))
        .route("/api/v2/search.json", get(api_v2_search_handler))
        .with_state(WebState {
            link_prefix: link_prefix.to_string(),
            backend,
        });

    // TODO: if static files are needed, ServeDir from the tower-http package can be used.

    let app = Router::new().nest(link_prefix, router);

    Server::bind(&address)
        .serve(app.into_make_service())
        .await?;

    Ok(())
}

struct HandlerError {
    source: Option<anyhow::Error>,
    status_code: Option<axum::http::StatusCode>,
}

impl HandlerError {
    fn new_status_code(status_code: axum::http::StatusCode) -> Self {
        Self {
            source: None,
            status_code: Some(status_code),
        }
    }
}

impl From<anyhow::Error> for HandlerError {
    fn from(value: anyhow::Error) -> Self {
        HandlerError {
            source: Some(value),
            status_code: None,
        }
    }
}

impl IntoResponse for HandlerError {
    fn into_response(self) -> askama_axum::Response {
        if let Some(source) = self.source {
            tracing::error!(error = ?source);
            return axum::http::StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }

        if let Some(status_code) = self.status_code {
            return status_code.into_response();
        }

        axum::http::StatusCode::INTERNAL_SERVER_ERROR.into_response()
    }
}

#[derive(Default, Deserialize)]
#[serde(default)]
struct SearchQuery {
    q: String,
    #[serde(default = "SearchQuery::match_default")]
    r#match: String,
}

impl SearchQuery {
    fn match_default() -> String {
        "domain".to_string()
    }
}

#[derive(Deserialize)]
#[serde(default)]
struct Pagination {
    page: i32,
}

impl Default for Pagination {
    fn default() -> Self {
        Self { page: 1 }
    }
}

impl Pagination {
    fn offset(&self) -> i64 {
        (self.page as i64 - 1) * PAGE_LIMIT
    }
}

#[derive(Template)]
#[template(path = "index.html")]
struct IndexTemplate {
    link_prefix: String,
    query: String,
    search_results: Vec<SearchResult>,
    last_update: DateTime<Utc>,
}

async fn index_handler(
    State(state): State<WebState>,
    Query(search_params): Query<SearchQuery>,
) -> Result<IndexTemplate, HandlerError> {
    let search_results = if !search_params.q.is_empty() {
        state
            .backend
            .search(&search_params.q, true, PAGE_LIMIT, 0)
            .await?
    } else {
        Vec::new()
    };
    let last_update = state.backend.get_last_update().await?;

    Ok(IndexTemplate {
        link_prefix: state.link_prefix,
        query: search_params.q,
        search_results,
        last_update,
    })
}

#[derive(Template)]
#[template(path = "faq.html")]
struct FaqTemplate {
    link_prefix: String,
}

async fn faq_handler(State(state): State<WebState>) -> FaqTemplate {
    FaqTemplate {
        link_prefix: state.link_prefix,
    }
}

#[derive(Template)]
#[template(path = "audit.html")]
struct AuditTemplate {
    link_prefix: String,
    no_json_items: Vec<AuditItem>,
    no_warc_items: Vec<AuditItem>,
}

async fn audit_handler(State(state): State<WebState>) -> Result<AuditTemplate, HandlerError> {
    let no_json_items = state.backend.get_audit_no_json_items().await?;
    let no_warc_items = state.backend.get_audit_no_warc_items().await?;

    Ok(AuditTemplate {
        link_prefix: state.link_prefix,
        no_json_items,
        no_warc_items,
    })
}

#[derive(Template)]
#[template(path = "stats.html")]
struct StatsTemplate {
    link_prefix: String,
    daily_stats: Vec<(NaiveDate, i64, i64)>,
}

async fn stats_handler(State(state): State<WebState>) -> Result<StatsTemplate, HandlerError> {
    let rows = state.backend.get_daily_stats().await?;
    let mut daily_stats = Vec::new();

    let mut total = 0;
    for row in rows {
        total += row.1;
        daily_stats.push((row.0, row.1, total));
    }

    Ok(StatsTemplate {
        link_prefix: state.link_prefix,
        daily_stats,
    })
}

#[derive(Template)]
#[template(path = "domains.html")]
struct DomainsTemplate {
    link_prefix: String,
    page: i32,
    has_next_page: bool,
    domains: Vec<String>,
}

async fn domains_handler(
    State(state): State<WebState>,
    Query(pagination): Query<Pagination>,
) -> Result<DomainsTemplate, HandlerError> {
    let domains = state
        .backend
        .get_domains(PAGE_LIMIT, pagination.offset())
        .await?;

    if domains.is_empty() {
        return Err(HandlerError::new_status_code(
            axum::http::StatusCode::NOT_FOUND,
        ));
    }

    Ok(DomainsTemplate {
        link_prefix: state.link_prefix,
        page: pagination.page,
        has_next_page: !domains.is_empty(),
        domains,
    })
}

#[derive(Template)]
#[template(path = "domain.html")]
struct DomainTemplate {
    link_prefix: String,
    domain: String,
    rows: Vec<DomainRow>,
}

async fn domain_handler(
    State(state): State<WebState>,
    Path(domain): Path<String>,
) -> Result<DomainTemplate, HandlerError> {
    let rows = state.backend.get_domain(&domain).await?;

    if rows.is_empty() {
        return Err(HandlerError::new_status_code(
            axum::http::StatusCode::NOT_FOUND,
        ));
    }

    Ok(DomainTemplate {
        link_prefix: state.link_prefix,
        domain,
        rows,
    })
}

#[derive(Template)]
#[template(path = "items.html")]
struct ItemsTemplate {
    link_prefix: String,
    identifiers: Vec<String>,
    page: i32,
    has_next_page: bool,
}

async fn items_handler(
    State(state): State<WebState>,
    Query(pagination): Query<Pagination>,
) -> Result<ItemsTemplate, HandlerError> {
    let identifiers = state
        .backend
        .get_items(PAGE_LIMIT, pagination.offset())
        .await?;

    if identifiers.is_empty() {
        return Err(HandlerError::new_status_code(
            axum::http::StatusCode::NOT_FOUND,
        ));
    }

    Ok(ItemsTemplate {
        link_prefix: state.link_prefix,
        page: pagination.page,
        has_next_page: !identifiers.is_empty(),
        identifiers,
    })
}

#[derive(Template)]
#[template(path = "item.html")]
struct ItemTemplate {
    link_prefix: String,
    identifier: String,
    rows: Vec<ItemRow>,
}

async fn item_handler(
    State(state): State<WebState>,
    Path(item_id): Path<String>,
) -> Result<ItemTemplate, HandlerError> {
    let rows = state.backend.get_item(&item_id).await?;

    if rows.is_empty() {
        return Err(HandlerError::new_status_code(
            axum::http::StatusCode::NOT_FOUND,
        ));
    }

    Ok(ItemTemplate {
        link_prefix: state.link_prefix,
        identifier: item_id,
        rows,
    })
}

#[derive(Template)]
#[template(path = "jobs.html")]
struct JobsTemplate {
    link_prefix: String,
    page: i32,
    has_next_page: bool,
    rows: Vec<JobsRow>,
}

async fn jobs_handler(
    State(state): State<WebState>,
    Query(pagination): Query<Pagination>,
) -> Result<JobsTemplate, HandlerError> {
    let rows = state
        .backend
        .get_jobs(PAGE_LIMIT, pagination.offset())
        .await?;

    if rows.is_empty() {
        return Err(HandlerError::new_status_code(
            axum::http::StatusCode::NOT_FOUND,
        ));
    }

    Ok(JobsTemplate {
        link_prefix: state.link_prefix,
        page: pagination.page,
        has_next_page: !rows.is_empty(),
        rows,
    })
}
#[derive(Template)]
#[template(path = "job.html")]
struct JobTemplate {
    link_prefix: String,
    job_id: String,
    rows: Vec<JobRow>,
}

async fn job_handler(
    State(state): State<WebState>,
    Path(job_id): Path<String>,
) -> Result<JobTemplate, HandlerError> {
    let rows = state.backend.get_job(&job_id).await?;

    if rows.is_empty() {
        return Err(HandlerError::new_status_code(
            axum::http::StatusCode::NOT_FOUND,
        ));
    }

    Ok(JobTemplate {
        link_prefix: state.link_prefix,
        job_id,
        rows,
    })
}

#[derive(Template)]
#[template(path = "cost_leaderboard.html")]
struct CostLeaderboardTemplate {
    link_prefix: String,
    rows: Vec<CostRow>,
}

async fn cost_leaderboard_handler(
    State(state): State<WebState>,
) -> Result<CostLeaderboardTemplate, HandlerError> {
    let results = state.backend.get_cost_leaderboard().await?;

    Ok(CostLeaderboardTemplate {
        link_prefix: state.link_prefix,
        rows: results,
    })
}

async fn api_v1_search_handler(
    State(state): State<WebState>,
    Query(params): Query<SearchQuery>,
) -> Result<Json<Vec<SearchResult>>, HandlerError> {
    let query = &params.q;
    let search_results = state.backend.search(query, false, i64::MAX, 0).await?;

    Ok(Json(search_results))
}

async fn api_v2_search_handler(
    State(state): State<WebState>,
    Query(params): Query<SearchQuery>,
) -> Result<Json<Vec<SearchResult>>, HandlerError> {
    let query = &params.q;
    let form_match = &params.r#match;
    let search_results = state
        .backend
        .search(query, form_match == "full", i64::MAX, 0)
        .await?;

    Ok(Json(search_results))
}
