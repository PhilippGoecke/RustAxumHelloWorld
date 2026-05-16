FROM debian:trixie-slim as builder

ARG DEBIAN_FRONTEND=noninteractive

# install rustup dependencies
RUN apt update && apt upgrade -y \
  # install dependencies
  && apt install -y --no-install-recommends --no-install-suggests gcc libc6-dev curl ca-certificates \
  # install rustup
  && apt install -y --no-install-recommends --no-install-suggests rustup \
  && rm -rf "/var/lib/apt/lists/*" \
  && rm -rf /var/cache/apt/archives

# add user and set home directory
ARG USER=rust
RUN useradd --create-home --shell /bin/bash $USER
ARG HOME="/home/$USER"
WORKDIR $HOME
USER $USER

ENV PATH="$HOME/.cargo/bin:$PATH"

RUN rustup default stable

WORKDIR /app

# Scaffold a minimal axum "hello world" app
RUN cargo new --bin hello_world

WORKDIR /app/hello_world

# Add axum, tokio and serde dependencies
RUN cargo add axum \
  && cargo add tokio --features macros,rt-multi-thread \
  && cargo add serde --features derive

# Capture the Rust and cargo versions used to build this image
RUN rustc --version | awk '{print $2}' > /app/hello_world/.rust_version \
  && cargo --version | awk '{print $2}' > /app/hello_world/.cargo_version \
  && cargo tree -i axum --depth 0 | awk 'NR==1{print $2}' | sed 's/^v//' > /app/hello_world/.axum_version

# Replace main.rs with a "Hello World" / "Hello $name!" axum handler mounted at "/"
RUN cat > src/main.rs <<'EOF'
use axum::{extract::Query, response::IntoResponse, routing::get, Router};
use serde::Deserialize;

const RUST_VERSION: &str = include_str!("../.rust_version");
const CARGO_VERSION: &str = include_str!("../.cargo_version");
const AXUM_VERSION: &str = include_str!("../.axum_version");

#[derive(Debug, Deserialize)]
pub struct HelloParams {
    pub name: Option<String>,
}

async fn index(Query(params): Query<HelloParams>) -> impl IntoResponse {
    let greeting = match params.name {
        Some(name) if !name.is_empty() => format!("Hello {name}!"),
        _ => "Hello World".to_string(),
    };
    format!(
        "{greeting}\nrust: {}\ncargo: {}\naxum: {}\n",
        RUST_VERSION.trim(),
        CARGO_VERSION.trim(),
        AXUM_VERSION.trim()
    )
}

#[tokio::main]
async fn main() {
    let app = Router::new().route("/", get(index));
    let bind = std::env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:5150".to_string());
    let listener = tokio::net::TcpListener::bind(&bind).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
EOF

# Build the release binary
RUN cargo build --release

# new stage for Rust app
FROM debian:trixie-slim as runtime

# install dependencies
RUN apt update && apt upgrade -y \
  && apt install -y --no-install-recommends --no-install-suggests ca-certificates libssl3 \
  && rm -rf "/var/lib/apt/lists/*" \
  && rm -rf /var/cache/apt/archives

# add user and set home directory
ARG USER=rust
RUN useradd --create-home --shell /bin/bash $USER
ARG HOME="/home/$USER"
WORKDIR $HOME
USER $USER

WORKDIR /srv/app

# Copy compiled binary from the builder
COPY --from=builder --chown=$USER:$USER /app/hello_world/target/release/hello_world /usr/local/bin/hello_world

EXPOSE 5150

ENV BIND_ADDR=0.0.0.0:5000

CMD ["hello_world"]
