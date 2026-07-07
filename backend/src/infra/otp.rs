use rand::Rng;
use redis::aio::ConnectionManager;
use sha2::{Digest, Sha256};

use crate::domain::error::AppError;

const OTP_TTL_SECS: i64 = 300;
const MAX_REQUESTS_PER_WINDOW: i64 = 3;
const REQUEST_WINDOW_SECS: i64 = 600;
const MAX_VERIFY_ATTEMPTS: i64 = 5;

/// Escalating login protection: cumulative failed verifies (24 h window)
/// lock the account — 3 fails → 3 min, 5 → 10 min, 10 → 24 h. The admin
/// unlock endpoint clears these keys.
fn lock_secs_for(fails: i64) -> Option<i64> {
    match fails {
        f if f >= 10 => Some(24 * 3600),
        f if f >= 5 => Some(600),
        f if f >= 3 => Some(180),
        _ => None,
    }
}

async fn check_locked(redis: &mut ConnectionManager, phone: &str) -> Result<(), AppError> {
    let locked: Option<String> = redis::cmd("GET")
        .arg(format!("otp:lock:{phone}"))
        .query_async(redis)
        .await?;
    if locked.is_some() {
        return Err(AppError::RateLimited);
    }
    Ok(())
}

async fn record_failure(redis: &mut ConnectionManager, phone: &str) -> Result<(), AppError> {
    let fails: i64 = redis::cmd("INCR")
        .arg(format!("otp:fail:{phone}"))
        .query_async(redis)
        .await?;
    if fails == 1 {
        let _: () = redis::cmd("EXPIRE")
            .arg(format!("otp:fail:{phone}"))
            .arg(24 * 3600)
            .query_async(redis)
            .await?;
    }
    if let Some(secs) = lock_secs_for(fails) {
        let _: () = redis::cmd("SET")
            .arg(format!("otp:lock:{phone}"))
            .arg("1")
            .arg("EX")
            .arg(secs)
            .query_async(redis)
            .await?;
    }
    Ok(())
}

/// Admin unlock: clears the escalating lock and all counters.
pub async fn unlock(redis: &mut ConnectionManager, phone: &str) -> Result<(), AppError> {
    let _: () = redis::cmd("DEL")
        .arg(format!("otp:lock:{phone}"))
        .arg(format!("otp:fail:{phone}"))
        .arg(format!("otp:rl:{phone}"))
        .arg(format!("otp:a:{phone}"))
        .query_async(redis)
        .await?;
    Ok(())
}

fn hash_otp(phone: &str, otp: &str, secret: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(phone.as_bytes());
    hasher.update(b":");
    hasher.update(otp.as_bytes());
    hasher.update(b":");
    hasher.update(secret.as_bytes());
    hex::encode(hasher.finalize())
}

/// Generates and stores a 6-digit OTP for the phone (hashed, 5-min TTL),
/// rate-limited per phone. Returns the plain OTP for the SMS provider
/// (or the dev-flag response).
pub async fn request(
    redis: &mut ConnectionManager,
    phone: &str,
    secret: &str,
) -> Result<String, AppError> {
    check_locked(redis, phone).await?;
    let count: i64 = redis::cmd("INCR")
        .arg(format!("otp:rl:{phone}"))
        .query_async(redis)
        .await?;
    if count == 1 {
        let _: () = redis::cmd("EXPIRE")
            .arg(format!("otp:rl:{phone}"))
            .arg(REQUEST_WINDOW_SECS)
            .query_async(redis)
            .await?;
    }
    if count > MAX_REQUESTS_PER_WINDOW {
        return Err(AppError::RateLimited);
    }

    let otp = format!("{:06}", rand::thread_rng().gen_range(0..1_000_000));
    let _: () = redis::cmd("SET")
        .arg(format!("otp:h:{phone}"))
        .arg(hash_otp(phone, &otp, secret))
        .arg("EX")
        .arg(OTP_TTL_SECS)
        .query_async(redis)
        .await?;
    let _: () = redis::cmd("DEL")
        .arg(format!("otp:a:{phone}"))
        .query_async(redis)
        .await?;
    Ok(otp)
}

/// Verifies and consumes the OTP (single use, max 5 attempts).
pub async fn verify(
    redis: &mut ConnectionManager,
    phone: &str,
    otp: &str,
    secret: &str,
) -> Result<(), AppError> {
    check_locked(redis, phone).await?;
    let stored: Option<String> = redis::cmd("GET")
        .arg(format!("otp:h:{phone}"))
        .query_async(redis)
        .await?;
    let Some(stored) = stored else {
        return Err(AppError::OtpExpired);
    };

    let attempts: i64 = redis::cmd("INCR")
        .arg(format!("otp:a:{phone}"))
        .query_async(redis)
        .await?;
    if attempts == 1 {
        let _: () = redis::cmd("EXPIRE")
            .arg(format!("otp:a:{phone}"))
            .arg(OTP_TTL_SECS)
            .query_async(redis)
            .await?;
    }
    if attempts > MAX_VERIFY_ATTEMPTS {
        let _: () = redis::cmd("DEL")
            .arg(format!("otp:h:{phone}"))
            .query_async(redis)
            .await?;
        return Err(AppError::RateLimited);
    }

    if stored != hash_otp(phone, otp, secret) {
        record_failure(redis, phone).await?;
        return Err(AppError::OtpInvalid);
    }
    // Success clears the failure counter so honest typos don't accumulate.
    let _: () = redis::cmd("DEL")
        .arg(format!("otp:fail:{phone}"))
        .query_async(redis)
        .await?;
    let _: () = redis::cmd("DEL")
        .arg(format!("otp:h:{phone}"))
        .arg(format!("otp:a:{phone}"))
        .query_async(redis)
        .await?;
    Ok(())
}
