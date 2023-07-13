use std::collections::HashMap;

use chrono::{DateTime, Utc};
use regex::Regex;
use reqwest::Client;
use serde::{Deserialize, Deserializer};
use serde_json::Value;

const USER_AGENT: &str = "ArchiveBotViewer/2.0 (ArchiveTeam)";
const SEARCH_URL: &str = "https://archive.org/services/search/v1/scrape";
const ITEM_URL: &str = "https://archive.org/details/";
const DOWNLOAD_URL: &str = "https://archive.org/download/";

#[derive(Debug, Deserialize)]
struct IASearchResult {
    items: Vec<ItemInfo>,
    cursor: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ItemInfo {
    pub identifier: String,
    pub addeddate: DateTime<Utc>,
    pub publicdate: DateTime<Utc>,
    pub imagecount: Option<i64>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ItemDetails {
    pub files: HashMap<String, FileDetails>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct FileDetails {
    #[serde(default)]
    #[serde(deserialize_with = "parse_int")]
    pub size: i64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct JsonMetadata {
    pub url: Option<String>,
    pub started_by: Option<String>,
}

pub struct IAClient {
    client: Client,
    cursor: Option<String>,
}

impl IAClient {
    pub fn new() -> anyhow::Result<Self> {
        let client = Client::builder().user_agent(USER_AGENT).build()?;

        Ok(Self {
            client,
            cursor: None,
        })
    }

    pub async fn fetch_items(
        &mut self,
        after_date: Option<DateTime<Utc>>,
    ) -> anyhow::Result<Vec<ItemInfo>> {
        let mut items = Vec::new();

        let search_query = match after_date {
            Some(date) => format!(
                "collection:archivebot addeddate:[{} TO 2999-01-01]",
                date.to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
            ),
            None => "collection:archivebot".to_string(),
        };

        let mut query = vec![
            ("q", search_query.as_str()),
            ("fields", "identifier,addeddate,publicdate,imagecount"),
            ("sorts", "addeddate asc"),
        ];

        if let Some(cursor) = &self.cursor {
            query.push(("cursor", cursor));
        }

        let request = self.client.get(SEARCH_URL).query(&query).build()?;
        tracing::info!(url = %request.url(), "request");

        let response = self.client.execute(request).await?;
        tracing::info!(status_code = %response.status());
        let response = response.error_for_status()?;

        let doc: IASearchResult = response.json().await?;
        items.extend_from_slice(&doc.items);

        self.cursor = doc.cursor;

        Ok(items)
    }

    pub fn has_more_items(&self) -> bool {
        self.cursor.is_some()
    }

    pub async fn fetch_item_files(&mut self, identifier: &str) -> anyhow::Result<ItemDetails> {
        let request = self
            .client
            .get(format!("{}{}", ITEM_URL, identifier))
            .query(&[("output", "json")])
            .build()?;

        tracing::info!(url = %request.url(), "request");
        let response = self.client.execute(request).await?;
        tracing::info!(status_code = %response.status());
        let response = response.error_for_status()?;

        let doc: ItemDetails = response.json().await?;

        Ok(doc)
    }

    pub async fn fetch_item_file(
        &mut self,
        identifier: &str,
        filename: &str,
    ) -> anyhow::Result<Vec<u8>> {
        let request = self
            .client
            .get(format!("{}{}/{}", DOWNLOAD_URL, identifier, filename))
            .build()?;

        tracing::info!(url = %request.url(), "request");
        let response = self.client.execute(request).await?;
        tracing::info!(status_code = %response.status());
        let response = response.error_for_status()?;

        let bytes = response.bytes().await?;

        Ok(bytes.to_vec())
    }
}

pub struct FilenameParts {
    pub domain: String,
    pub depth: String,
    pub date: String,
    pub time: String,
    pub ident: String,
    pub aborted: String,
    pub extension: String,
}

pub fn parse_filename(filename: &str) -> Option<FilenameParts> {
    lazy_static::lazy_static! {
        static ref RE: Regex = Regex::new(r"^([\w._@ -]+)-(inf|shallow)-(\d{8})-(\d{6})-?(\w{5})?-?(aborted)?-?(\d+|meta)?.(json|warc\.gz)$").unwrap();
    }

    RE.captures(filename).map(|captures| FilenameParts {
        domain: captures.get(1).unwrap().as_str().to_string(),
        depth: captures.get(2).unwrap().as_str().to_string(),
        date: captures.get(3).unwrap().as_str().to_string(),
        time: captures.get(4).unwrap().as_str().to_string(),
        ident: match captures.get(5) {
            Some(capture) => capture.as_str().to_string(),
            None => String::new(),
        },
        aborted: match captures.get(6) {
            Some(capture) => capture.as_str().to_string(),
            None => String::new(),
        },
        extension: captures.get(8).unwrap().as_str().to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[ignore]
    #[tokio::test]
    #[tracing_test::traced_test]
    async fn test_fetch_items() {
        let date = "2023-01-01T00:00:00Z".parse().unwrap();
        let mut client = IAClient::new().unwrap();

        let items = client.fetch_items(Some(date)).await.unwrap();

        dbg!(&items);
    }

    #[test]
    fn test_parse_filename_legacy() {
        let parts = parse_filename("irclog.perlgeek.de-inf-20131101-162719-aborted.json").unwrap();

        assert_eq!(&parts.domain, "irclog.perlgeek.de");
        assert_eq!(&parts.depth, "inf");
        assert_eq!(&parts.date, "20131101");
        assert_eq!(&parts.time, "162719");
        assert_eq!(&parts.ident, "");
        assert_eq!(&parts.aborted, "aborted");
        assert_eq!(&parts.extension, "json");
    }

    #[test]
    fn test_parse_filename() {
        let parts =
            parse_filename("www15.atpages.jp-inf-20151231-051440-9v9p7-00000.warc.gz").unwrap();

        assert_eq!(&parts.domain, "www15.atpages.jp");
        assert_eq!(&parts.depth, "inf");
        assert_eq!(&parts.date, "20151231");
        assert_eq!(&parts.time, "051440");
        assert_eq!(&parts.ident, "9v9p7");
        assert_eq!(&parts.aborted, "");
        assert_eq!(&parts.extension, "warc.gz");
    }

    #[test]
    fn test_parse_filename_meta() {
        let parts =
            parse_filename("www.youtube.com-shallow-20200206-145902-8jjc9-meta.warc.gz").unwrap();

        assert_eq!(&parts.domain, "www.youtube.com");
        assert_eq!(&parts.depth, "shallow");
        assert_eq!(&parts.date, "20200206");
        assert_eq!(&parts.time, "145902");
        assert_eq!(&parts.ident, "8jjc9");
        assert_eq!(&parts.aborted, "");
        assert_eq!(&parts.extension, "warc.gz");
    }

    #[test]
    fn test_parse_filename_domain_symbols() {
        let parts =
            parse_filename("a-b.c@_d-inf-shallow-20200101-010203-metaa-aborted-meta.warc.gz")
                .unwrap();

        assert_eq!(&parts.domain, "a-b.c@_d-inf");
        assert_eq!(&parts.depth, "shallow");
        assert_eq!(&parts.date, "20200101");
        assert_eq!(&parts.time, "010203");
        assert_eq!(&parts.ident, "metaa");
        assert_eq!(&parts.aborted, "aborted");
        assert_eq!(&parts.extension, "warc.gz");
    }

    #[test]
    fn test_parse_filename_json() {
        let parts = parse_filename("www.testroniclabs.com-inf-20191014-171816-36aoc.json").unwrap();

        assert_eq!(&parts.domain, "www.testroniclabs.com");
        assert_eq!(&parts.depth, "inf");
        assert_eq!(&parts.date, "20191014");
        assert_eq!(&parts.time, "171816");
        assert_eq!(&parts.ident, "36aoc");
        assert_eq!(&parts.aborted, "");
        assert_eq!(&parts.extension, "json");
    }
}

fn parse_int<'de, D>(deserializer: D) -> Result<i64, D::Error>
where
    D: Deserializer<'de>,
{
    Ok(match Value::deserialize(deserializer)? {
        Value::String(s) => s.parse::<i64>().map_err(serde::de::Error::custom)?,
        Value::Number(num) => num
            .as_i64()
            .ok_or_else(|| serde::de::Error::custom("invalid number"))?,
        _ => return Err(serde::de::Error::custom("wrong type")),
    })
}
