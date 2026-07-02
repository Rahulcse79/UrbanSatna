pub mod envelope;
pub mod health;

use axum::http::{HeaderName, Request};
use axum::routing::get;
use axum::Router;
use axum_prometheus::PrometheusMetricLayer;
use tower::ServiceBuilder;
use tower_http::request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer};
use tower_http::trace::TraceLayer;

use crate::domain::error::AppError;
use crate::state::AppState;

const REQUEST_ID_HEADER: &str = "x-request-id";

pub fn router(state: AppState) -> Router {
    let (prometheus_layer, metric_handle) = PrometheusMetricLayer::pair();
    let request_id_header = HeaderName::from_static(REQUEST_ID_HEADER);

    let api_v1 = Router::new(); // feature routers get merged here as phases land

    Router::new()
        .route("/health", get(health::health))
        .route("/metrics", get(move || async move { metric_handle.render() }))
        .nest("/api/v1", api_v1)
        .fallback(|| async { AppError::NotFound("route") })
        .with_state(state)
        .layer(
            ServiceBuilder::new()
                .layer(SetRequestIdLayer::new(
                    request_id_header.clone(),
                    MakeRequestUuid,
                ))
                .layer(
                    TraceLayer::new_for_http().make_span_with(|request: &Request<_>| {
                        let request_id = request
                            .headers()
                            .get(REQUEST_ID_HEADER)
                            .and_then(|v| v.to_str().ok())
                            .unwrap_or("unknown");
                        tracing::info_span!(
                            "http_request",
                            method = %request.method(),
                            uri = %request.uri(),
                            request_id = %request_id,
                        )
                    }),
                )
                .layer(PropagateRequestIdLayer::new(request_id_header)),
        )
        .layer(prometheus_layer)
}
