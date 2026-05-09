# Google API Key Scope Checker

A bash script for authorized security testing that validates the scope and restrictions of a Google API key across multiple Google APIs — useful for identifying misconfigurations during mobile or web application pentests.

## Usage

Make the script executable before running it:
```bash
chmod +x check_apikey.sh
```

**Interactive** — prompts for the key securely (hidden input):
```bash
./check_apikey.sh
```

**Argument** — pass the key directly:
```bash
./check_apikey.sh AIzaSy...
```

**Environment variable** — useful in scripts or CI:
```bash
GOOGLE_API_KEY=<keyValue> ./check_apikey.sh
```

## What It Tests

The script probes the provided key against two categories of Google APIs:

**Geo / Maps APIs**
- Geocoding
- Places Nearby Search
- Directions
- Elevation
- Street View Metadata
- Static Maps (detects image response vs. error)

**Other Google APIs**
- YouTube Data API
- Firebase Management
- Cloud Resource Manager
- Google Drive
- Gmail
- Cloud Storage

## Output

Each API is reported as one of:

| Result | Meaning |
|---|---|
| `ACCESSIBLE` | Key works — API is reachable and returned data |
| `ACCESSIBLE (quota hit)` | Key works but quota is exhausted |
| `RESTRICTED` | Key is restricted from this API |
| `DENIED / INVALID` | Key rejected by Google |
| `UNKNOWN` | Unexpected response; raw error shown |

## Severity Summary

After all checks, the script prints a findings summary with a severity rating:

- **CRITICAL** — sensitive APIs accessible (Drive, Cloud, Firebase, Gmail, Admin)
- **MEDIUM** — 3 or more APIs accessible
- **LOW** — limited access (cost abuse risk)
- **Informational** — no APIs accessible, but key is still exposed in plaintext

> Even when no APIs are accessible, an exposed key (e.g. hardcoded in an APK) is still a finding. Recommend restricting by Android app signature in Google Cloud Console or moving calls server-side.

## Requirements

- `bash`
- `curl`

## Authorization

For authorized testing only. Run this tool only against API keys you own or have explicit written permission to test.
