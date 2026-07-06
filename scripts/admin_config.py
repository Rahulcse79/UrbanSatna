#!/usr/bin/env python3
"""Break-glass admin tool: read or change app-config flags directly via
the API — no app needed. Works while DEV_RETURN_OTP=true (the server
echoes the login OTP); once a real SMS gateway lands, it prompts for the
OTP you receive by SMS.

Examples:
  # Show current config (no login needed)
  ./scripts/admin_config.py https://urbansatna.onrender.com +919752079591 get

  # Turn maintenance mode OFF
  ./scripts/admin_config.py https://urbansatna.onrender.com +919752079591 \
      set maintenance_mode false

  # Other flags work the same way:
  #   set allow_server_url_change true|false
  #   set promo_enabled true|false
  #   set promo_title "Diwali offer"
  #   set min_build 42
"""
import json
import sys
import urllib.request

BOOL_KEYS = {"maintenance_mode", "allow_server_url_change", "promo_enabled",
             "require_latest"}
INT_KEYS = {"min_build", "latest_build"}
STR_KEYS = {"promo_title", "promo_subtitle"}


def call(base, method, path, token=None, body=None):
    req = urllib.request.Request(base + path, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(req, data, timeout=60) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        err = json.load(e)
        sys.exit(f"API error {e.code}: {err.get('error')}")


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    base, phone, action = sys.argv[1].rstrip("/"), sys.argv[2], sys.argv[3]

    if action == "get":
        config = call(base, "GET", "/api/v1/app-config")["data"]
        print(json.dumps(config, indent=2))
        return

    if action != "set" or len(sys.argv) < 6:
        sys.exit(__doc__)
    key, raw = sys.argv[4], sys.argv[5]
    if key in BOOL_KEYS:
        value = raw.lower() in ("true", "1", "on", "yes")
    elif key in INT_KEYS:
        value = int(raw)
    elif key in STR_KEYS:
        value = raw
    else:
        sys.exit(f"unknown key '{key}'. Known: "
                 f"{sorted(BOOL_KEYS | INT_KEYS | STR_KEYS)}")

    print(f"Requesting OTP for {phone} …")
    r = call(base, "POST", "/api/v1/auth/otp/request", body={"phone": phone})
    otp = r["data"].get("dev_otp")
    if not otp:
        otp = input("Enter the OTP you received by SMS: ").strip()
    r = call(base, "POST", "/api/v1/auth/otp/verify",
             body={"phone": phone, "otp": otp, "device": "admin-cli"})
    token = r["data"]["access_token"]
    if "admin" not in r["data"].get("roles", []) \
            and "super_admin" not in r["data"].get("roles", []):
        sys.exit("this phone is not an admin account")

    r = call(base, "PATCH", "/api/v1/app-config", token, {key: value})
    print("Updated. Current config:")
    print(json.dumps(r["data"], indent=2))


if __name__ == "__main__":
    main()
