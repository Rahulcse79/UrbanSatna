//! First-line support chatbot.
//!
//! With `ANTHROPIC_API_KEY` configured, replies come from the Anthropic
//! Messages API; otherwise — and whenever the API call fails or refuses —
//! the keyword bot answers. Chat never blocks on the AI dependency
//! (CLAUDE.md §1.6), and no vendor call leaves this module (§1.5).

use anyhow::{bail, Context};
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::config::Config;
use crate::infra::db::support::SupportMessage;

/// System account the chatbot speaks through (auto-provisioned).
pub const BOT_PHONE: &str = "+910000000001";
pub const BOT_NAME: &str = "Servexa Bot";

const API_URL: &str = "https://api.anthropic.com/v1/messages";
const API_VERSION: &str = "2023-06-01";
/// Thread messages sent to the model as conversation context.
const HISTORY_LIMIT: usize = 12;

const SYSTEM_PROMPT: &str = "\
You are the Servexa assistant, the in-app support chatbot of Servexa \
(UrbanSatna) — a home-services booking app for Satna, Madhya Pradesh, India. \
Customers book verified nearby professionals (electrician, plumber, AC \
mechanic, appliance repair, home cleaning, carpenter and more).

Facts you may rely on:
- Payment is collected after the service, in cash or UPI. There is no online prepayment.
- Every booking has a 4-digit arrival OTP shown on the booking card; the customer shares it with the technician at the door before work starts.
- Booking help: Bookings tab, open the booking — cancel it, chat with the technician, or call them from the booking card.
- Complaints and refund requests: Profile, then 'Report a problem' raises a ticket the operations team reviews.
- Coupons are applied at booking time; each code works once per customer.

Rules:
- Keep replies short (2-4 sentences), warm and practical.
- Mirror the user's language: reply in Hindi (Devanagari) when they write Hindi, otherwise English.
- You cannot see bookings, payments or accounts, and you cannot take actions. Never invent order details, amounts, timelines or promises. For anything account-specific, say the support team will follow up right here in this chat.
- If the user asks for a human, say the team will reply in this chat as soon as they are online.";

#[derive(Deserialize)]
struct ApiContentBlock {
    #[serde(rename = "type")]
    kind: String,
    #[serde(default)]
    text: String,
}

#[derive(Deserialize)]
struct ApiResponse {
    #[serde(default)]
    content: Vec<ApiContentBlock>,
    #[serde(default)]
    stop_reason: Option<String>,
}

#[derive(Clone)]
pub struct SupportBot {
    http: reqwest::Client,
    api_key: Option<String>,
    model: String,
}

impl SupportBot {
    pub fn new(config: &Config) -> Self {
        Self {
            http: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(20))
                .build()
                // Startup wiring: only fails if no TLS backend is available.
                .expect("building HTTP client for support bot"),
            api_key: config.anthropic_api_key.clone(),
            model: config.support_bot_model.clone(),
        }
    }

    /// Always produces a reply; the keyword bot covers every failure path.
    pub async fn reply(&self, history: &[SupportMessage], user_id: Uuid, text: &str) -> String {
        if let Some(key) = self.api_key.clone() {
            match self.ask_model(&key, history, user_id).await {
                Ok(reply) => return reply,
                Err(error) => {
                    tracing::warn!(%error, "support bot AI reply failed; using keyword fallback");
                }
            }
        }
        keyword_reply(text)
    }

    async fn ask_model(
        &self,
        key: &str,
        history: &[SupportMessage],
        user_id: Uuid,
    ) -> anyhow::Result<String> {
        let start = history.len().saturating_sub(HISTORY_LIMIT);
        let mut messages: Vec<Value> = Vec::new();
        for message in &history[start..] {
            let role = if message.sender_id == user_id {
                "user"
            } else {
                "assistant"
            };
            // The first message must be from the user.
            if messages.is_empty() && role == "assistant" {
                continue;
            }
            messages.push(json!({ "role": role, "content": message.body }));
        }
        if messages.is_empty() {
            bail!("no user messages to reply to");
        }

        let response = self
            .http
            .post(API_URL)
            .header("x-api-key", key)
            .header("anthropic-version", API_VERSION)
            .json(&json!({
                "model": self.model,
                "max_tokens": 400,
                "system": SYSTEM_PROMPT,
                "messages": messages,
            }))
            .send()
            .await
            .context("calling Anthropic API")?;

        let status = response.status();
        if !status.is_success() {
            bail!("Anthropic API returned {status}");
        }
        let parsed: ApiResponse = response.json().await.context("parsing API response")?;
        if parsed.stop_reason.as_deref() == Some("refusal") {
            bail!("model refused the request");
        }
        let reply: String = parsed
            .content
            .iter()
            .filter(|block| block.kind == "text")
            .map(|block| block.text.as_str())
            .collect::<Vec<_>>()
            .join("");
        let reply = reply.trim();
        if reply.is_empty() {
            bail!("model returned no text");
        }
        Ok(reply.to_string())
    }
}

/// Zero-dependency fallback: instant keyword answers for the common topics.
fn keyword_reply(text: &str) -> String {
    let t = text.to_lowercase();
    let greeting = matches!(
        t.trim(),
        "hi" | "hello" | "hey" | "namaste" | "नमस्ते" | "hii" | "hlo"
    );
    if t.contains("booking") || t.contains("बुकिंग") || t.contains("cancel") {
        "🤖 For booking help: open Bookings, tap the booking, and use \
         Cancel or Chat with your technician. Your arrival OTP is on the \
         booking card. A team member will follow up soon."
    } else if t.contains("payment")
        || t.contains("refund")
        || t.contains("भुगतान")
        || t.contains("paisa")
        || t.contains("money")
    {
        "🤖 Payments are collected after the service (cash/UPI). For a \
         wrong charge or refund, please also raise a ticket from Profile → \
         Report a problem — our team will review it quickly."
    } else if t.contains("worker")
        || t.contains("late")
        || t.contains("वर्कर")
        || t.contains("technician")
    {
        "🤖 You can see your technician's status on the booking card and \
         call them directly with the call button. If nobody accepted yet, \
         we're still searching nearby professionals."
    } else if greeting {
        "🤖 Namaste! I'm the Servexa assistant. Tell me about a booking, \
         payment, or worker issue — or type your question and our team \
         will reply as soon as they're online."
    } else {
        "🤖 Thanks for your message! Our support team is currently \
         offline and will reply as soon as possible. Meanwhile: booking \
         issues → Bookings tab · payments → pay after service (cash/UPI) \
         · urgent problems → Profile → Report a problem."
    }
    .to_string()
}
