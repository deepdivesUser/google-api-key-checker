#!/bin/bash
# ================================================
# Google Crash Reporting / Firebase Crashlytics
# API Key Access Checker
# Author: deepdivesUser
# Description: Tests Google Crash Reporting and
#              Firebase Crashlytics API keys for
#              unauthorized access to crash data,
#              project info, and related services
# Usage:
#   Interactive : ./check_crashreporting.sh
#   Argument    : ./check_crashreporting.sh <API_KEY>
#   Env var     : CRASH_API_KEY=AIza... ./check_crashreporting.sh
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
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║   Google Crash Reporting API Key Checker      ║"
    echo "  ║          For authorized testing only          ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

# ── Get API Key ───────────────────────────────────
get_key() {
    if [ -n "$1" ]; then
        API_KEY="$1"
        echo -e "${CYAN}[*] Using key from argument${RESET}"
    elif [ -n "$CRASH_API_KEY" ]; then
        API_KEY="$CRASH_API_KEY"
        echo -e "${CYAN}[*] Using key from environment variable${RESET}"
    else
        echo -e "${YELLOW}[?] Enter Google Crash Reporting API key to test:${RESET}"
        read -r -s API_KEY
        echo ""
    fi

    # Validate format
    if [[ ! "$API_KEY" =~ ^AIza[0-9A-Za-z_-]{35}$ ]]; then
        echo -e "${RED}[!] Warning: Key doesn't match expected Google API key format${RESET}"
        echo -e "${RED}    Expected: AIza followed by 35 alphanumeric chars${RESET}"
        echo -e "${YELLOW}    Continue anyway? (y/n):${RESET}"
        read -r CONFIRM
        [[ "$CONFIRM" != "y" ]] && echo "Exiting." && exit 1
    fi

    REDACTED="${API_KEY:0:10}...[redacted]"
    echo -e "${CYAN}[*] Testing key: ${BOLD}$REDACTED${RESET}"
    echo ""
}

# ── Generic Check ─────────────────────────────────
check() {
    local NAME="$1"
    local URL="$2"
    local SENSITIVE="${3:-false}"

    TESTED=$((TESTED + 1))
    printf "  %-42s" "[$NAME]"

    RESPONSE=$(curl -s --max-time 10 "$URL")
    HTTP_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" "$URL")

    if echo "$RESPONSE" | grep -qiE "PERMISSION_DENIED|permission_denied|ACCESS_DENIED"; then
        echo -e "${GREEN}✅ PERMISSION DENIED${RESET}"
    elif echo "$RESPONSE" | grep -qiE "UNAUTHENTICATED|unauthenticated"; then
        echo -e "${GREEN}✅ UNAUTHENTICATED / RESTRICTED${RESET}"
    elif echo "$RESPONSE" | grep -qi "keyInvalid\|API_KEY_INVALID"; then
        echo -e "${GREEN}✅ KEY INVALID / REVOKED${RESET}"
    elif echo "$RESPONSE" | grep -qi "disabled\|not enabled\|not activated"; then
        echo -e "${GREEN}✅ API NOT ENABLED${RESET}"
    elif [[ "$HTTP_CODE" == "403" || "$HTTP_CODE" == "401" ]]; then
        echo -e "${GREEN}✅ RESTRICTED (HTTP $HTTP_CODE)${RESET}"
    elif [[ "$HTTP_CODE" == "200" ]]; then
        if [ "$SENSITIVE" == "true" ]; then
            echo -e "${RED}🔓 ACCESSIBLE — SENSITIVE DATA EXPOSED${RESET}"
            FINDINGS+=("SENSITIVE: $NAME")
        else
            echo -e "${RED}🔓 ACCESSIBLE${RESET}"
            FINDINGS+=("$NAME")
        fi
        # Show snippet of response for context
        SNIPPET=$(echo "$RESPONSE" | head -c 200 | tr '\n' ' ')
        echo -e "       ${YELLOW}↳ $SNIPPET${RESET}"
    elif [[ "$HTTP_CODE" == "404" ]]; then
        echo -e "${YELLOW}❓ NOT FOUND (404) — project ID needed${RESET}"
    else
        echo -e "${YELLOW}❓ UNKNOWN — HTTP $HTTP_CODE${RESET}"
    fi
}

# ── Project ID Extraction ─────────────────────────
get_project_hints() {
    echo ""
    echo -e "${BOLD}── Attempting Project Discovery ────────────────${RESET}"
    printf "  %-42s" "[Firebase Project Lookup]"

    # Try to get project info which may reveal project ID
    PROJ_RESPONSE=$(curl -s --max-time 10 \
        "https://firebase.googleapis.com/v1beta1/projects?key=$API_KEY")

    if echo "$PROJ_RESPONSE" | grep -qiE "CREDENTIALS_MISSING|API keys are not supported|UNAUTHENTICATED|PERMISSION_DENIED|keyInvalid|API_KEY_INVALID"; then
        echo -e "${GREEN}✅ DENIED${RESET}"
    elif echo "$PROJ_RESPONSE" | grep -qE '"projectId" *: *"[^"]+"'; then
        PROJECT_ID=$(echo "$PROJ_RESPONSE" | grep -o '"projectId": *"[^"]*"' | head -1 | cut -d'"' -f4)
        PROJECT_NUMBER=$(echo "$PROJ_RESPONSE" | grep -o '"projectNumber": *"[^"]*"' | head -1 | cut -d'"' -f4)
        echo -e "${RED}🔓 PROJECT INFO EXPOSED${RESET}"
        echo -e "       ${RED}↳ Project ID     : $PROJECT_ID${RESET}"
        echo -e "       ${RED}↳ Project Number : $PROJECT_NUMBER${RESET}"
        FINDINGS+=("Firebase project info exposed: $PROJECT_ID")
        DISCOVERED_PROJECT_ID="$PROJECT_ID"
    else
        echo -e "${YELLOW}❓ UNKNOWN${RESET}"
    fi
}

# ── Crashlytics Checks ────────────────────────────
check_crashlytics() {
    echo ""
    echo -e "${BOLD}── Firebase Crashlytics ────────────────────────${RESET}"

    # Use discovered project ID if available, otherwise placeholder
    local PID="${DISCOVERED_PROJECT_ID:-YOUR_PROJECT_ID}"

    check "Crashlytics API Access" \
        "https://firebase.googleapis.com/v1beta1/projects/$PID/androidApps?key=$API_KEY" \
        "true"

    check "Crashlytics App List" \
        "https://firebasecrashlytics.googleapis.com/v1beta1/projects/$PID?key=$API_KEY" \
        "true"

    check "Error Groups (Crash Reports)" \
        "https://clouderrorreporting.googleapis.com/v1beta1/projects/$PID/groupStats?key=$API_KEY" \
        "true"

    check "Error Events (Stack Traces)" \
        "https://clouderrorreporting.googleapis.com/v1beta1/projects/$PID/events?key=$API_KEY" \
        "true"

    check "Crash Report Issues" \
        "https://clouderrorreporting.googleapis.com/v1beta1/projects/$PID/groups?key=$API_KEY" \
        "true"
}

# ── Related Firebase APIs ─────────────────────────
check_related() {
    echo ""
    echo -e "${BOLD}── Related Firebase / Google APIs ──────────────${RESET}"

    check "Firebase Management API" \
        "https://firebase.googleapis.com/v1beta1/projects?key=$API_KEY"

    check "Cloud Logging (may have crash logs)" \
        "https://logging.googleapis.com/v2/entries:list?key=$API_KEY"

    check "Cloud Monitoring" \
        "https://monitoring.googleapis.com/v3/projects?key=$API_KEY"

    check "Firebase Remote Config" \
        "https://firebaseremoteconfig.googleapis.com/v1/projects/${DISCOVERED_PROJECT_ID:-test}/remoteConfig?key=$API_KEY" \
        "true"

    check "Firebase App Distribution" \
        "https://firebaseappdistribution.googleapis.com/v1/projects/${DISCOVERED_PROJECT_ID:-test}/apps?key=$API_KEY"

    check "Firebase Dynamic Links" \
        "https://firebasedynamiclinks.googleapis.com/v1/installAttribution?key=$API_KEY"

    check "Cloud Error Reporting Write" \
        "https://clouderrorreporting.googleapis.com/v1beta1/projects/${DISCOVERED_PROJECT_ID:-test}/events:report?key=$API_KEY"
}

# ── What Crash Reports Contain ────────────────────
explain_impact() {
    echo ""
    echo -e "${BOLD}── Why Crash Report Access is Sensitive ────────${RESET}"
    echo -e "  ${YELLOW}If crash reports are accessible, they may expose:${RESET}"
    echo -e "  ${YELLOW}  → Device model, OS, carrier, screen resolution${RESET}"
    echo -e "  ${YELLOW}  → App version, build number, internal config${RESET}"
    echo -e "  ${YELLOW}  → Full stack traces (reveals internal code paths)${RESET}"
    echo -e "  ${YELLOW}  → Memory state at time of crash${RESET}"
    echo -e "  ${YELLOW}  → User account IDs if logged at crash time${RESET}"
    echo -e "  ${YELLOW}  → Session tokens if present in app state${RESET}"
    echo -e "  ${YELLOW}  → PII if developers log it carelessly${RESET}"
    echo -e "  ${YELLOW}  → Internal API endpoints from stack traces${RESET}"
}

# ── Severity Summary ──────────────────────────────
severity() {
    echo ""
    echo -e "${BOLD}================================================${RESET}"
    echo -e "${BOLD} Results Summary${RESET}"
    echo -e "${BOLD}================================================${RESET}"
    echo -e "${CYAN}[*] Key tested   : $REDACTED${RESET}"
    echo -e "${CYAN}[*] APIs tested  : $TESTED${RESET}"
    echo ""

    if [ ${#FINDINGS[@]} -eq 0 ]; then
        echo -e "${GREEN}[✅] No accessible APIs found — key appears restricted${RESET}"
        echo -e "${GREEN}    Severity: Informational${RESET}"
        echo -e "${GREEN}    Note: Key still exposed in plaintext in APK.${RESET}"
        echo -e "${GREEN}          Recommend restricting by app signature${RESET}"
        echo -e "${GREEN}          in Google Cloud Console.${RESET}"
    else
        echo -e "${RED}[🔓] Accessible APIs found:${RESET}"
        for f in "${FINDINGS[@]}"; do
            echo -e "${RED}    → $f${RESET}"
        done
        echo ""

        HAS_SENSITIVE=$(printf '%s\n' "${FINDINGS[@]}" | grep -i "SENSITIVE\|crash\|error\|stack\|project" | wc -l)
        COUNT=${#FINDINGS[@]}

        if [ "$HAS_SENSITIVE" -gt 0 ]; then
            echo -e "${RED}${BOLD}    Severity: HIGH — crash/error data potentially exposed${RESET}"
            echo -e "${RED}${BOLD}    May contain PII, stack traces, internal endpoints${RESET}"
        elif [ "$COUNT" -ge 2 ]; then
            echo -e "${RED}${BOLD}    Severity: MEDIUM — multiple APIs accessible${RESET}"
        else
            echo -e "${YELLOW}${BOLD}    Severity: LOW — limited access${RESET}"
        fi
    fi

    echo ""
    echo -e "${CYAN}[*] Document all findings with curl evidence${RESET}"
    echo -e "${BOLD}================================================${RESET}"
}

# ── Main ──────────────────────────────────────────
banner
get_key "$1"
get_project_hints
check_crashlytics
check_related
explain_impact
severity
