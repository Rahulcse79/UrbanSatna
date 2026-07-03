use jsonwebtoken::{DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::domain::error::AppError;

/// Access-token claims. Roles/permissions are embedded at login, so
/// permission changes take effect on the next login/refresh.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    pub sub: Uuid,
    /// Session id — lets logout revoke exactly this device.
    pub sid: Uuid,
    pub phone: String,
    pub roles: Vec<String>,
    pub perms: Vec<String>,
    pub iat: i64,
    pub exp: i64,
}

pub fn sign(claims: &Claims, secret: &str) -> Result<String, AppError> {
    jsonwebtoken::encode(
        &Header::default(),
        claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .map_err(|e| AppError::Internal(anyhow::Error::new(e).context("signing JWT")))
}

pub fn verify(token: &str, secret: &str) -> Result<Claims, AppError> {
    jsonwebtoken::decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &Validation::default(),
    )
    .map(|data| data.claims)
    .map_err(|_| AppError::Unauthorized)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn claims() -> Claims {
        Claims {
            sub: Uuid::now_v7(),
            sid: Uuid::now_v7(),
            phone: "+919999999999".into(),
            roles: vec!["customer".into()],
            perms: vec!["bookings:create".into()],
            iat: chrono::Utc::now().timestamp(),
            exp: chrono::Utc::now().timestamp() + 900,
        }
    }

    #[test]
    fn roundtrip() {
        let c = claims();
        let token = sign(&c, "secret").unwrap();
        let back = verify(&token, "secret").unwrap();
        assert_eq!(back.sub, c.sub);
        assert_eq!(back.roles, c.roles);
    }

    #[test]
    fn wrong_secret_rejected() {
        let token = sign(&claims(), "secret").unwrap();
        assert!(verify(&token, "other").is_err());
    }

    #[test]
    fn expired_rejected() {
        let mut c = claims();
        // Past the library's default 60s clock-skew leeway.
        c.exp = chrono::Utc::now().timestamp() - 120;
        let token = sign(&c, "secret").unwrap();
        assert!(verify(&token, "secret").is_err());
    }
}
