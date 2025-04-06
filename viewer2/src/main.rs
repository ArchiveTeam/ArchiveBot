mod backend;
mod database;
mod ia;
mod web;

use std::{fmt::Display, net::IpAddr, path::PathBuf, process::ExitCode, sync::LazyLock, time::{Duration, Instant}};

use clap::Parser;
use tokio_util::sync::CancellationToken;
use tracing::Level;
use tracing_subscriber::prelude::*;

static START_TIME: LazyLock<Instant> = LazyLock::new(Instant::now);

#[derive(Parser, Debug)]
#[command(author, version)]
struct Args {
    /// IP address of the listening socket
    #[arg(long, short = 'H', default_value = "127.0.0.1")]
    host: IpAddr,

    /// Port number of the listening socket
    #[arg(long, short = 'P', default_value_t = 8056)]
    port: u16,

    /// Path to a directory for storing state
    #[arg(long, short, default_value = "data")]
    data_dir: PathBuf,

    /// URL path prefix
    #[arg(long, default_value = "/")]
    prefix: String,

    /// Action that the backend will do
    #[arg(long, default_value_t = BackendAction::Live)]
    backend_action: BackendAction,
}

#[derive(Debug, Clone, Copy)]
enum BackendAction {
    /// Fetch data from IA
    Live,
    /// Use dummy test data
    Dev,
    /// Don't do any data processing
    None,
}

impl From<&str> for BackendAction {
    fn from(value: &str) -> Self {
        match value {
            "live" => Self::Live,
            "dev" => Self::Dev,
            "none" => Self::None,
            _ => panic!("invalid backend action"),
        }
    }
}

impl Display for BackendAction {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BackendAction::Live => write!(f, "live"),
            BackendAction::Dev => write!(f, "dev"),
            BackendAction::None => write!(f, "none"),
        }
    }
}

#[tokio::main]
async fn main() -> ExitCode {
    match main_inner().await {
        Ok(_) => ExitCode::SUCCESS,
        Err(error) => {
            tracing::error!(?error);
            eprintln!("{:#}", error);
            ExitCode::FAILURE
        }
    }
}

async fn main_inner() -> anyhow::Result<()> {
    let _ = *START_TIME;

    let args = Args::parse();

    init_logging();

    let mut backend = backend::Backend::open(&args.data_dir).await?;
    let address = (args.host, args.port).into();
    let web_future = web::run(address, &args.prefix, backend.clone());
    let backend_future = async {
        match args.backend_action {
            BackendAction::Live => backend.run().await,
            BackendAction::Dev => backend.run_test_data().await,
            BackendAction::None => loop {
                tokio::time::sleep(Duration::from_secs(60)).await;
            },
        }
    };

    let token = CancellationToken::new();

    set_up_cancel(token.clone());

    let token2 = token.clone();
    tokio::select! {
        _result = token2.cancelled() => { },
        result = async { tokio::try_join!(backend_future, web_future) } => {
            result?;
        },
    }

    backend.close().await?;
    tracing::info!("done");

    Ok(())
}

fn init_logging() {
    let level = if cfg!(debug_assertions) {
        Level::DEBUG
    } else {
        Level::INFO
    };

    let filter = tracing_subscriber::filter::Targets::new().with_target("archivebot_viewer", level);

    tracing_subscriber::registry()
        .with(tracing_subscriber::fmt::layer())
        .with(filter)
        .init();

    tracing::debug!("logging initialized");
}

fn set_up_cancel(token: CancellationToken) {
    let c_token = token.clone();

    tokio::spawn(async move {
        tokio::signal::ctrl_c().await.unwrap();
        c_token.cancel();
    });

    #[cfg(unix)]
    {
        let u_token = token;
        tokio::spawn(async move {
            set_up_sig_handler(u_token).await;
        });
    }
}

#[cfg(unix)]
async fn set_up_sig_handler(token: CancellationToken) {
    let mut stream =
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()).unwrap();

    loop {
        stream.recv().await;
        token.cancel();
    }
}
