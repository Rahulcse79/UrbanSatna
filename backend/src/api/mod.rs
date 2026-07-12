pub mod admin;
pub mod app_config;
pub mod auth;
pub mod bookings;
pub mod catalog;
pub mod chat;
pub mod coupons;
pub mod envelope;
pub mod health;
pub mod me;
pub mod support;
pub mod tickets;

use axum::extract::DefaultBodyLimit;
use axum::http::{HeaderName, Request};
use axum::routing::{get, patch, post};
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

    let api_v1 = Router::new()
        // app config (public read; admin write)
        .route(
            "/app-config",
            get(app_config::get).patch(app_config::update),
        )
        // auth
        .route("/auth/otp/request", post(auth::request_otp))
        .route("/auth/otp/verify", post(auth::verify_otp))
        .route("/auth/refresh", post(auth::refresh))
        .route("/auth/logout", post(auth::logout))
        // profile
        .route("/me", get(me::get_me).patch(me::update_me))
        .route(
            "/me/worker-application",
            get(me::my_worker_application).post(me::apply_worker),
        )
        .route("/me/avatar", get(me::get_avatar).post(me::upload_avatar))
        .route("/me/worker-application/kyc/{kind}", post(me::upload_kyc))
        // legacy alias: old APKs now create an application, not a role
        .route("/me/become-worker", post(me::apply_worker))
        // admin: worker verification queue
        .route(
            "/admin/worker-applications",
            get(admin::list_worker_applications),
        )
        .route(
            "/admin/worker-applications/{id}/decide",
            post(admin::decide_worker_application),
        )
        .route(
            "/admin/worker-applications/{id}/kyc/{kind}",
            get(admin::kyc_image),
        )
        // admin: catalog management (includes inactive rows)
        .route(
            "/admin/catalog/categories",
            get(catalog::list_categories_admin),
        )
        .route(
            "/admin/catalog/categories/{id}/services",
            get(catalog::list_services_admin),
        )
        // catalog (public reads, admin writes)
        .route(
            "/categories",
            get(catalog::list_categories).post(catalog::create_category),
        )
        .route("/categories/{id}", patch(catalog::update_category))
        .route("/categories/{id}/services", get(catalog::list_services))
        .route("/services/search", get(catalog::search))
        .route("/services", post(catalog::create_service))
        .route("/services/{id}", patch(catalog::update_service))
        // customer bookings
        .route("/bookings", post(bookings::create))
        .route("/bookings/mine", get(bookings::mine))
        .route("/bookings/{id}/cancel", post(bookings::cancel))
        .route("/bookings/{id}/rate", post(bookings::rate))
        // worker jobs
        .route("/jobs/available", get(bookings::available_jobs))
        .route("/jobs/mine", get(bookings::my_jobs))
        .route("/jobs/earnings", get(bookings::earnings))
        .route("/jobs/history", get(bookings::history))
        .route("/bookings/{id}/accept", post(bookings::accept))
        .route("/bookings/{id}/status", patch(bookings::advance))
        // coupons (check for the booking screen; admin CRUD)
        .route("/coupons/check", get(coupons::check))
        .route("/coupons/available", get(coupons::available))
        .route("/admin/coupons", get(coupons::list).post(coupons::create))
        .route("/admin/coupons/{id}", patch(coupons::update))
        // support tickets
        .route("/tickets", post(tickets::create))
        .route("/tickets/mine", get(tickets::mine))
        .route("/tickets/{id}/reopen", post(tickets::reopen))
        .route("/admin/tickets", get(tickets::list))
        .route("/admin/tickets/{id}/resolve", post(tickets::resolve))
        .route("/admin/tickets/{id}/close", post(tickets::close))
        // live support chat (user thread + admin inbox; image/video uploads)
        .route(
            "/support/messages",
            get(support::my_thread).post(support::send),
        )
        .route(
            "/support/messages/attachment",
            post(support::send_attachment)
                .layer(DefaultBodyLimit::max(support::MAX_ATTACHMENT_BYTES + 1024)),
        )
        .route(
            "/support/messages/{mid}/attachment",
            get(support::attachment),
        )
        .route("/admin/support/threads", get(support::threads))
        .route(
            "/admin/support/{user_id}/messages",
            get(support::admin_thread).post(support::admin_send),
        )
        .route(
            "/admin/support/{user_id}/messages/attachment",
            post(support::admin_send_attachment)
                .layer(DefaultBodyLimit::max(support::MAX_ATTACHMENT_BYTES + 1024)),
        )
        .route(
            "/admin/support/{user_id}/messages/{mid}/attachment",
            get(support::admin_attachment),
        )
        // admin: dashboard, user management, activity logs
        .route("/admin/stats", get(admin::stats))
        .route("/admin/users/unlock-login", post(admin::unlock_login))
        .route("/admin/users", get(admin::list_users))
        .route("/admin/users/{id}/avatar", get(admin::user_avatar))
        .route("/admin/users/{id}/block", post(admin::block_user))
        .route("/admin/users/{id}/unblock", post(admin::unblock_user))
        .route("/admin/audit", get(admin::audit_logs))
        // booking chat (media uploads get a bigger body budget)
        .route(
            "/bookings/{id}/messages",
            get(chat::list).post(chat::send_text),
        )
        .route(
            "/bookings/{id}/messages/attachment",
            post(chat::send_attachment)
                .layer(DefaultBodyLimit::max(chat::MAX_ATTACHMENT_BYTES + 1024)),
        )
        .route(
            "/bookings/{id}/messages/{mid}/attachment",
            get(chat::attachment),
        );

    Router::new()
        .route("/health", get(health::health))
        .route(
            "/metrics",
            get(move || async move { metric_handle.render() }),
        )
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
