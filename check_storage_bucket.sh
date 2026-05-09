#!/bin/bash
# ================================================
# Google Cloud / Firebase Storage Bucket Checker
# Author: deepdivesUser
# Description: Tests Google Cloud Storage and
#              Firebase Storage buckets for
#              unauthenticated read/write/list
#              access and common misconfigurations
# Usage:
#   Interactive : ./check_storage_bucket.sh
#   Argument    : ./check_storage_bucket.sh <BUCKET_NAME>
#   Env var     : GCS_BUCKET=name ./check_storage_bucket.sh
# ================================================

# ── Colors ──────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Globals ──────────────────────────────────────
FINDINGS=()
TESTED=0

# ── Banner ───────────────────────────────────────
banner() {
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║    Google Storage Bucket Access Checker   ║"
    echo "  ║         For authorized testing only       ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${RESET}"
}

# ── Get Bucket Name ───────────────────────────────
get_bucket() {
    if [ -n "$1" ]; then
        BUCKET="$1"
        echo -e "${CYAN}[*] Using bucket from argument${RESET}"
    elif [ -n "$GCS_BUCKET" ]; then
        BUCKET="$GCS_BUCKET"
        echo -e "${CYAN}[*] Using bucket from environment variable${RESET}"
    else
        echo -e "${YELLOW}[?] Enter Google Storage bucket name to test${RESET}"
        echo -e "${YELLOW}    (e.g. my-app-default-rtdb or my-app.appspot.com):${RESET}"
        read -r BUCKET
        echo ""
    fi

    # Strip gs:// prefix if pasted with it
    BUCKET="${BUCKET#gs://}"
    BUCKET="${BUCKET%/}"

    if [ -z "$BUCKET" ]; then
        echo -e "${RED}[!] No bucket name provided. Exiting.${RESET}"
        exit 1
    fi

    echo -e "${CYAN}[*] Target bucket: ${BOLD}$BUCKET${RESET}"
    echo ""
}

# ── Generic Check Helper ──────────────────────────
run_check() {
    local NAME="$1"
    local URL="$2"
    local METHOD="${3:-GET}"
    local DATA="$4"

    TESTED=$((TESTED + 1))
    printf "  %-38s" "[$NAME]"

    if [ -n "$DATA" ]; then
        RESPONSE=$(curl -s --max-time 10 -X "$METHOD" \
            -H "Content-Type: application/octet-stream" \
            --data-binary "$DATA" "$URL")
        HTTP_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
            -X "$METHOD" \
            -H "Content-Type: application/octet-stream" \
            --data-binary "$DATA" "$URL")
    else
        RESPONSE=$(curl -s --max-time 10 -X "$METHOD" "$URL")
        HTTP_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
            -X "$METHOD" "$URL")
    fi

    echo "$RESPONSE $HTTP_CODE"
}

# ── List Access Check ─────────────────────────────
check_list() {
    echo -e "${BOLD}── List / Read Access ──────────────────────────${RESET}"

    # GCS JSON API list
    printf "  %-38s" "[GCS API List Objects]"
    RESPONSE=$(curl -s --max-time 10 \
        "https://storage.googleapis.com/storage/v1/b/$BUCKET/o")
    HTTP_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
        "https://storage.googleapis.com/storage/v1/b/$BUCKET/o")

    if echo "$RESPONSE" | grep -qi "anonymous caller\|PERMISSION_DENIED\|forbidden\|AccessDenied"; then
        echo -e "${GREEN}✅ LIST DENIED${RESET}"
    elif echo "$RESPONSE" | grep -qi "items\|prefixes\|kind.*storage"; then
        ITEM_COUNT=$(echo "$RESPONSE" | grep -o '"name"' | wc -l)
        echo -e "${RED}🔓 LIST OPEN — $ITEM_COUNT objects found${RESET}"
        FINDINGS+=("GCS API list open — $ITEM_COUNT objects")
        # Show first few filenames
        echo "$RESPONSE" | grep -o '"name": *"[^"]*"' | head -5 | \
            while read -r line; do
                echo -e "       ${RED}↳ $line${RESET}"
            done
    elif [[ "$HTTP_CODE" == "404" ]]; then
        echo -e "${YELLOW}❓ BUCKET NOT FOUND (404)${RESET}"
    elif [[ "$HTTP_CODE" == "400" ]]; then
        echo -e "${YELLOW}❓ BAD REQUEST (400) — check bucket name${RESET}"
    else
        echo -e "${YELLOW}❓ UNKNOWN — HTTP $HTTP_CODE${RESET}"
    fi

    # GCS direct URL list
    printf "  %-38s" "[GCS Direct URL]"
    RESPONSE2=$(curl -s --max-time 10 \
        "https://storage.googleapis.com/$BUCKET/")
    HTTP_CODE2=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
        "https://storage.googleapis.com/$BUCKET/")

    if echo "$RESPONSE2" | grep -qi "AccessDenied\|forbidden\|anonymous"; then
        echo -e "${GREEN}✅ DENIED${RESET}"
    elif echo "$RESPONSE2" | grep -qi "ListBucketResult\|Contents\|Key>"; then
        echo -e "${RED}🔓 OPEN — XML listing returned${RESET}"
        FINDINGS+=("GCS direct URL list open")
    elif [[ "$HTTP_CODE2" == "403" ]]; then
        echo -e "${GREEN}✅ RESTRICTED (HTTP 403)${RESET}"
    elif [[ "$HTTP_CODE2" == "404" ]]; then
        echo -e "${YELLOW}❓ NOT FOUND (404)${RESET}"
    else
        echo -e "${YELLOW}❓ UNKNOWN — HTTP $HTTP_CODE2${RESET}"
    fi

    # Firebase Storage URL
    printf "  %-38s" "[Firebase Storage API]"
    FB_RESPONSE=$(curl -s --max-time 10 \
        "https://firebasestorage.googleapis.com/v0/b/$BUCKET/o")
    FB_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
        "https://firebasestorage.googleapis.com/v0/b/$BUCKET/o")

    if echo "$FB_RESPONSE" | grep -qi "permission_denied\|PERMISSION_DENIED\|unauthorized"; then
        echo -e "${GREEN}✅ DENIED${RESET}"
    elif echo "$FB_RESPONSE" | grep -qi "items\|downloadTokens\|name"; then
        echo -e "${RED}🔓 OPEN — Firebase Storage accessible${RESET}"
        FINDINGS+=("Firebase Storage API open")
    elif [[ "$FB_CODE" == "403" || "$FB_CODE" == "401" ]]; then
        echo -e "${GREEN}✅ RESTRICTED (HTTP $FB_CODE)${RESET}"
    elif [[ "$FB_CODE" == "404" ]]; then
        echo -e "${YELLOW}❓ NOT FOUND (404)${RESET}"
    else
        echo -e "${YELLOW}❓ UNKNOWN — HTTP $FB_CODE${RESET}"
    fi
}

# ── Bucket Metadata Check ─────────────────────────
check_metadata() {
    echo ""
    echo -e "${BOLD}── Bucket Metadata / IAM ───────────────────────${RESET}"

    # Bucket metadata
    printf "  %-38s" "[Bucket Metadata]"
    META_RESPONSE=$(curl -s --max-time 10 \
        "https://storage.googleapis.com/storage/v1/b/$BUCKET")
    META_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
        "https://storage.googleapis.com/storage/v1/b/$BUCKET")

    if echo "$META_RESPONSE" | grep -qi "anonymous\|PERMISSION_DENIED\|forbidden"; then
        echo -e "${GREEN}✅ DENIED${RESET}"
    elif echo "$META_RESPONSE" | grep -qi '"kind".*"storage#bucket"'; then
        LOCATION=$(echo "$META_RESPONSE" | grep -o '"location": *"[^"]*"' | cut -d'"' -f4)
        echo -e "${YELLOW}⚠️  METADATA READABLE — Location: $LOCATION${RESET}"
        FINDINGS+=("Bucket metadata readable")
    elif [[ "$META_CODE" == "403" ]]; then
        echo -e "${GREEN}✅ RESTRICTED (HTTP 403)${RESET}"
    else
        echo -e "${YELLOW}❓ UNKNOWN — HTTP $META_CODE${RESET}"
    fi

    # IAM policy
    printf "  %-38s" "[IAM Policy]"
    IAM_RESPONSE=$(curl -s --max-time 10 \
        "https://storage.googleapis.com/storage/v1/b/$BUCKET/iam")
    IAM_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
        "https://storage.googleapis.com/storage/v1/b/$BUCKET/iam")

    if echo "$IAM_RESPONSE" | grep -qi "anonymous\|PERMISSION_DENIED\|forbidden"; then
        echo -e "${GREEN}✅ DENIED${RESET}"
    elif echo "$IAM_RESPONSE" | grep -qi "allUsers\|allAuthenticatedUsers"; then
        echo -e "${RED}🔓 IAM EXPOSED — public access policy found${RESET}"
        FINDINGS+=("IAM policy exposes allUsers or allAuthenticatedUsers")
    elif [[ "$IAM_CODE" == "403" ]]; then
        echo -e "${GREEN}✅ RESTRICTED (HTTP 403)${RESET}"
    else
        echo -e "${YELLOW}❓ UNKNOWN — HTTP $IAM_CODE${RESET}"
    fi
}

# ── Common File Check ─────────────────────────────
check_common_files() {
    echo ""
    echo -e "${BOLD}── Common Sensitive Files ──────────────────────${RESET}"

    FILES=(
        "config.json"
        "credentials.json"
        "secrets.json"
        "firebase.json"
        "google-services.json"
        ".env"
        "database.json"
        "users.json"
        "backup.zip"
        "backup.sql"
        "dump.sql"
        "private.pem"
        "private_key.json"
        "serviceAccount.json"
        "service-account.json"
    )

    for FILE in "${FILES[@]}"; do
        printf "  %-38s" "[$FILE]"
        FILE_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
            "https://storage.googleapis.com/$BUCKET/$FILE")

        if [[ "$FILE_CODE" == "200" ]]; then
            echo -e "${RED}🔓 ACCESSIBLE (HTTP 200)${RESET}"
            FINDINGS+=("Sensitive file accessible: $FILE")
        elif [[ "$FILE_CODE" == "403" ]]; then
            echo -e "${GREEN}✅ RESTRICTED (HTTP 403)${RESET}"
        elif [[ "$FILE_CODE" == "404" ]]; then
            echo -e "${GREEN}✅ NOT FOUND (404)${RESET}"
        else
            echo -e "${YELLOW}❓ HTTP $FILE_CODE${RESET}"
        fi
    done
}

# ── Write Access Check ────────────────────────────
check_write() {
    echo ""
    echo -e "${BOLD}── Write Access ────────────────────────────────${RESET}"

    TEST_FILE="pentest_check_$(date +%s).txt"
    UPLOAD_URL="https://storage.googleapis.com/upload/storage/v1/b/$BUCKET/o?uploadType=media&name=$TEST_FILE"

    printf "  %-38s" "[Unauthenticated Write]"
    WRITE_RESPONSE=$(curl -s --max-time 10 -X POST \
        -H "Content-Type: text/plain" \
        --data-binary "authorized_pentest_check" \
        "$UPLOAD_URL")
    WRITE_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Content-Type: text/plain" \
        --data-binary "authorized_pentest_check" \
        "$UPLOAD_URL")

    if echo "$WRITE_RESPONSE" | grep -qi "anonymous\|PERMISSION_DENIED\|forbidden\|unauthorized"; then
        echo -e "${GREEN}✅ WRITE DENIED${RESET}"
    elif [[ "$WRITE_CODE" == "200" ]] && echo "$WRITE_RESPONSE" | grep -qi '"name"'; then
        echo -e "${RED}🔓 WRITE OPEN — file uploaded successfully${RESET}"
        FINDINGS+=("Unauthenticated write succeeded")

        # Clean up
        printf "  %-38s" "[Cleanup]"
        DELETE_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
            -X DELETE \
            "https://storage.googleapis.com/storage/v1/b/$BUCKET/o/$TEST_FILE")
        if [[ "$DELETE_CODE" == "204" || "$DELETE_CODE" == "200" ]]; then
            echo -e "${GREEN}✅ Test file deleted${RESET}"
        else
            echo -e "${YELLOW}⚠️  Manual cleanup needed:${RESET}"
            echo -e "       ${YELLOW}DELETE https://storage.googleapis.com/$BUCKET/$TEST_FILE${RESET}"
        fi
    elif [[ "$WRITE_CODE" == "403" || "$WRITE_CODE" == "401" ]]; then
        echo -e "${GREEN}✅ WRITE DENIED (HTTP $WRITE_CODE)${RESET}"
    else
        echo -e "${YELLOW}❓ UNKNOWN — HTTP $WRITE_CODE${RESET}"
    fi
}

# ── gsutil Check ──────────────────────────────────
check_gsutil() {
    echo ""
    echo -e "${BOLD}── gsutil (if installed) ───────────────────────${RESET}"
    printf "  %-38s" "[gsutil ls]"

    if command -v gsutil &>/dev/null; then
        GSUTIL_OUT=$(gsutil ls "gs://$BUCKET" 2>&1)
        if echo "$GSUTIL_OUT" | grep -qi "AccessDeniedException\|forbidden"; then
            echo -e "${GREEN}✅ ACCESS DENIED${RESET}"
        elif echo "$GSUTIL_OUT" | grep -qi "gs://"; then
            COUNT=$(echo "$GSUTIL_OUT" | wc -l)
            echo -e "${RED}🔓 OPEN — $COUNT objects listed${RESET}"
            FINDINGS+=("gsutil list open — $COUNT objects")
        else
            echo -e "${YELLOW}❓ $GSUTIL_OUT${RESET}"
        fi
    else
        echo -e "${YELLOW}⚠️  gsutil not installed — skipping${RESET}"
        echo -e "       ${YELLOW}Install: pip install gsutil --break-system-packages${RESET}"
    fi
}

# ── Severity Summary ──────────────────────────────
severity() {
    echo ""
    echo -e "${BOLD}================================================${RESET}"
    echo -e "${BOLD} Results Summary${RESET}"
    echo -e "${BOLD}================================================${RESET}"
    echo -e "${CYAN}[*] Target   : gs://$BUCKET${RESET}"
    echo -e "${CYAN}[*] Endpoints tested: $TESTED${RESET}"
    echo ""

    if [ ${#FINDINGS[@]} -eq 0 ]; then
        echo -e "${GREEN}[✅] Bucket appears properly secured${RESET}"
        echo -e "${GREEN}    Severity: Informational${RESET}"
    else
        echo -e "${RED}[🔓] Findings:${RESET}"
        for f in "${FINDINGS[@]}"; do
            echo -e "${RED}    → $f${RESET}"
        done
        echo ""

        HAS_WRITE=$(printf '%s\n' "${FINDINGS[@]}" | grep -i "write" | wc -l)
        HAS_SENSITIVE=$(printf '%s\n' "${FINDINGS[@]}" | grep -iE "credential|secret|key|service.account|private|IAM" | wc -l)
        HAS_DATA=$(printf '%s\n' "${FINDINGS[@]}" | grep -iE "objects found|accessible|listing" | wc -l)

        if [ "$HAS_WRITE" -gt 0 ] || [ "$HAS_SENSITIVE" -gt 0 ]; then
            echo -e "${RED}${BOLD}    Severity: CRITICAL${RESET}"
        elif [ "$HAS_DATA" -gt 0 ]; then
            echo -e "${RED}${BOLD}    Severity: HIGH — data readable without auth${RESET}"
        else
            echo -e "${YELLOW}${BOLD}    Severity: MEDIUM — misconfiguration found${RESET}"
        fi
    fi

    echo ""
    echo -e "${CYAN}[*] Capture curl evidence for your report${RESET}"
    echo -e "${BOLD}================================================${RESET}"
}

# ── Main ──────────────────────────────────────────
banner
get_bucket "$1"
check_list
check_metadata
check_common_files
check_write
check_gsutil
severity
