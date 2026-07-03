use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use uuid::Uuid;

use crate::domain::error::AppError;
use crate::infra::jwt::{self, Claims};
use crate::state::AppState;

/// Authenticated caller, extracted from the Bearer token.
/// Add it as a handler argument to require authentication.
#[derive(Debug, Clone)]
pub struct CurrentUser {
    pub id: Uuid,
    pub session_id: Uuid,
    #[allow(dead_code)] // notifications/SMS features will read this
    pub phone: String,
    pub roles: Vec<String>,
    pub perms: Vec<String>,
}

impl CurrentUser {
    pub fn has_role(&self, role: &str) -> bool {
        self.roles.iter().any(|r| r == role)
    }

    pub fn require_role(&self, role: &str) -> Result<(), AppError> {
        if self.has_role(role) {
            Ok(())
        } else {
            Err(AppError::Forbidden)
        }
    }

    pub fn require_perm(&self, perm: &str) -> Result<(), AppError> {
        if self.perms.iter().any(|p| p == perm) {
            Ok(())
        } else {
            Err(AppError::Forbidden)
        }
    }
}

impl From<Claims> for CurrentUser {
    fn from(c: Claims) -> Self {
        Self {
            id: c.sub,
            session_id: c.sid,
            phone: c.phone,
            roles: c.roles,
            perms: c.perms,
        }
    }
}

impl FromRequestParts<AppState> for CurrentUser {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let token = parts
            .headers
            .get(axum::http::header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .ok_or(AppError::Unauthorized)?;
        let claims = jwt::verify(token, &state.config.jwt_secret)?;
        Ok(claims.into())
    }
}
