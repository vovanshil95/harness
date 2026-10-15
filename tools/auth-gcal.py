#!/usr/bin/env python3
"""Headless Google OAuth for mcp-google-calendar (two-phase, PKCE-persisting).

Phase 1 (url): печатает ссылку авторизации и сохраняет state (verifier + client config).
Phase 2 (finish CODE): обменивает code на токен и сохраняет его в
dirname(credentials.json)/mcp-google-calendar-token.json.

Запуск (нужен google-auth-oauthlib):
  uv run --with google-auth-oauthlib python auth-gcal.py <gcal-dir> url
  uv run --with google-auth-oauthlib python auth-gcal.py <gcal-dir> finish "<code>"
"""
import json
import sys

from google_auth_oauthlib.flow import InstalledAppFlow

SCOPES = [
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/calendar.events",
]
REDIRECT = "http://localhost:3420"


def main() -> None:
    if len(sys.argv) < 3:
        print("usage: auth-gcal.py <gcal-dir> <url|finish> [code]", file=sys.stderr)
        sys.exit(1)
    gcal_dir = sys.argv[1]
    cmd = sys.argv[2]
    cred = f"{gcal_dir}/credentials.json"
    state_path = f"{gcal_dir}/auth-state.json"
    token_path = f"{gcal_dir}/mcp-google-calendar-token.json"

    if cmd == "url":
        flow = InstalledAppFlow.from_client_secrets_file(cred, SCOPES, redirect_uri=REDIRECT)
        url, _ = flow.authorization_url(access_type="offline", prompt="consent")
        with open(state_path, "w") as f:
            json.dump(
                {
                    "client_config": flow.client_config,
                    "code_verifier": flow.code_verifier,
                    "redirect_uri": REDIRECT,
                },
                f,
            )
        print(url)
    elif cmd == "finish":
        code = sys.argv[3]
        with open(state_path) as f:
            state = json.load(f)
        # client_config — это INNER dict, оборачиваем обратно в {"installed": ...}
        flow = InstalledAppFlow.from_client_config(
            {"installed": state["client_config"]},
            SCOPES,
            redirect_uri=state["redirect_uri"],
        )
        flow.code_verifier = state["code_verifier"]  # КРИТИЧНО: тот же verifier, что в фазе 1
        if "code=" in code:
            code = code.split("code=", 1)[1].split("&", 1)[0]
        flow.fetch_token(code=code)
        creds = flow.credentials
        scope = getattr(creds, "scope", None) or " ".join(getattr(creds, "scopes", []) or [])
        token = {
            "access_token": creds.token,
            "refresh_token": creds.refresh_token,
            "scope": scope,
            "token_type": "Bearer",
            "expiry_date": int(creds.expiry.timestamp() * 1000) if creds.expiry else 0,
        }
        with open(token_path, "w") as f:
            json.dump(token, f)
        print(f"token saved to {token_path}")


if __name__ == "__main__":
    main()
