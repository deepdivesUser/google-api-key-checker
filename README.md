# Google API Key & Firebase Checker

Bash scripts for authorized security testing — validate the scope of a Google API key, check Firebase Realtime Database instances for unauthenticated access, and probe Google Cloud / Firebase Storage buckets for misconfigurations. Useful during mobile or web application pentests.

---

## Setup

Make all scripts executable before running:
```bash
chmod +x check_apikey.sh check_firebase.sh check_storage_bucket.sh
```

---

## check_apikey.sh

Tests a Google API key against multiple Google APIs to identify misconfigurations and unrestricted access.

### Usage

**Interactive** — prompts for the key securely (hidden input):
```bash
./check_apikey.sh
```

**Argument** — pass the key directly:
```bash
./check_apikey.sh <keyValue>
```

**Environment variable** — useful in scripts or CI:
```bash
GOOGLE_API_KEY=<keyValue> ./check_apikey.sh
```

### What It Tests

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

### Output

| Result | Meaning |
|---|---|
| `ACCESSIBLE` | Key works — API is reachable and returned data |
| `ACCESSIBLE (quota hit)` | Key works but quota is exhausted |
| `RESTRICTED` | Key is restricted from this API |
| `DENIED / INVALID` | Key rejected by Google |
| `UNKNOWN` | Unexpected response; raw error shown |

### Severity

- **CRITICAL** — sensitive APIs accessible (Drive, Cloud, Firebase, Gmail, Admin)
- **MEDIUM** — 3 or more APIs accessible
- **LOW** — limited access (cost abuse risk)
- **Informational** — no APIs accessible, but key is still exposed in plaintext

> Even when no APIs are accessible, an exposed key (e.g. hardcoded in an APK) is still a finding. Recommend restricting by Android app signature in Google Cloud Console or moving calls server-side.

---

## check_firebase.sh

Tests a Firebase Realtime Database URL for unauthenticated read and write access across common and sensitive endpoints, plus Firestore REST API exposure.

### Usage

**Interactive** — prompts for the database URL:
```bash
./check_firebase.sh
```

**Argument** — pass the URL directly:
```bash
./check_firebase.sh https://project-default-rtdb.firebaseio.com
```

**Environment variable:**
```bash
FIREBASE_URL=https://project-default-rtdb.firebaseio.com ./check_firebase.sh
```

### What It Tests

**Root & Common Endpoints** (unauthenticated read)
- Root, Users, Accounts, Messages, Chats, Tokens, Config, Settings, Admin, Data, API

**Sensitive Endpoints** (unauthenticated read)
- Private, Secrets, Keys, Passwords, Credentials, Payments, Transactions, Logs

**Write Access Test**
- Attempts an unauthenticated POST to `firebase_pentest_check.json` and cleans up any written data immediately after

**Firestore REST API**
- Derives the project ID from the database URL and probes the Firestore REST endpoint for open access

### Output

| Result | Meaning |
|---|---|
| `OPEN` | Endpoint readable without authentication; byte count shown |
| `NULL` | Endpoint exists but contains no data |
| `WRITE OPEN` | Unauthenticated write succeeded |
| `PERMISSION DENIED` / `RESTRICTED` | Endpoint is secured |
| `UNKNOWN` | Unexpected response; raw output shown |

### Severity

- **CRITICAL** — unauthenticated write access, or sensitive data (users, tokens, passwords, etc.) readable
- **HIGH** — data readable without authentication
- **MEDIUM** — endpoints exposed but return null data
- **Informational** — database appears properly secured

---

## check_storage_bucket.sh

Tests a Google Cloud Storage or Firebase Storage bucket for unauthenticated read, write, list access, and common misconfigurations.

### Usage

**Interactive** — prompts for the bucket name:
```bash
./check_storage_bucket.sh
```

**Argument** — pass the bucket name directly:
```bash
./check_storage_bucket.sh <BUCKET_NAME>
```

**Environment variable:**
```bash
GCS_BUCKET=<BUCKET_NAME> ./check_storage_bucket.sh
```

The `gs://` prefix is stripped automatically if included.

### What It Tests

**List / Read Access**
- GCS JSON API object listing
- GCS direct URL listing
- Firebase Storage API listing

**Bucket Metadata / IAM**
- Bucket metadata readability (location, configuration)
- IAM policy exposure (`allUsers` or `allAuthenticatedUsers`)

**Common Sensitive Files** (unauthenticated fetch)
- `config.json`, `credentials.json`, `secrets.json`, `firebase.json`, `google-services.json`, `.env`, `database.json`, `users.json`, `backup.zip`, `backup.sql`, `dump.sql`, `private.pem`, `private_key.json`, `serviceAccount.json`, `service-account.json`

**Write Access**
- Attempts an unauthenticated upload via the GCS upload API and deletes the test file immediately if the write succeeds

**gsutil** (if installed)
- Runs `gsutil ls` as an additional unauthenticated list check

### Output

| Result | Meaning |
|---|---|
| `LIST OPEN` | Bucket contents listable without authentication |
| `WRITE OPEN` | Unauthenticated upload succeeded |
| `ACCESSIBLE (HTTP 200)` | Sensitive file is publicly downloadable |
| `METADATA READABLE` | Bucket metadata returned without authentication |
| `IAM EXPOSED` | IAM policy grants access to `allUsers` or `allAuthenticatedUsers` |
| `DENIED` / `RESTRICTED` | Endpoint is secured |
| `NOT FOUND (404)` | Bucket or object does not exist |
| `UNKNOWN` | Unexpected HTTP response; code shown |

### Severity

- **CRITICAL** — unauthenticated write succeeded, or sensitive credentials / keys accessible
- **HIGH** — data readable without authentication (open listing or sensitive files)
- **MEDIUM** — misconfiguration found (e.g. metadata readable, IAM exposed)
- **Informational** — bucket appears properly secured

---

## Requirements

- `bash`
- `curl`
- `gsutil` *(optional — for the gsutil check in `check_storage_bucket.sh`)*

## Authorization

For authorized testing only. Run these tools only against targets you own or have explicit written permission to test.