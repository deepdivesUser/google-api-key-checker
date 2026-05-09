#!/bin/bash
# ================================================
# Firebase Database Open Access Checker
# Author: deepdivesUser
# Description: Tests Firebase Realtime Database
#              URLs for unauthenticated read/write
#              access and common exposed endpoints
# Usage:
#   Interactive : ./check_firebase.sh
#   Argument    : ./check_firebase.sh <FIREBASE_URL>
#   Env var     : FIREBASE_URL=https://... ./check_firebase.sh
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
WRITE_FINDINGS=()
TESTED=0

# ── Banner ───────────────────────────────────────
banner() {
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║     Firebase Database Access Checker      ║"
    echo "  ║         For authorized testing only       ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${RESET}"
}

# ── Get Firebase URL ──────────────────────────────
get_url() {
    if [ -n "$1" ]; then
        FIREBASE_URL="$1"
        echo -e "${CYAN}[*] Using URL from argument${RESET}"
    elif [ -n "$FIREBASE_URL" ]; then
        echo -e "${CYAN}[*] Using URL from environment variable${RESET}"
    else
        echo -e "${YELLOW}[?] Enter Firebase Realtime Database URL${RESET}"
        echo -e "${YELLOW}    (e.g. https://project-default-rtdb.firebaseio.com):${RESET}"
        read -r FIREBASE_URL
        echo ""
    fi

    # Strip trailing slash
    FIREBASE_URL="${FIREBASE_URL%/}"

    # Validate format
    if [[ ! "$FIREBASE_URL" =~ ^https://[a-zA-Z0-9_-]+.*firebaseio\.com$ ]]; then
        echo -e "${RED}[!] Warning: URL doesn't look like a Firebase Realtime Database URL${RESET}"
        echo -e "${RED}    Expected format: https://project-name-default-rtdb.firebaseio.com${RESET}"
        echo -e "${YELLOW}    Continue anyway? (y/n):${RESET}"
        read -r CONFIRM
        [[ "$CONFIRM" != "y" ]] && echo "Exiting." && exit 1
    fi

    echo -e "${CYAN}[*] Target: ${BOLD}$FIREBASE_URL${RESET}"
    echo ""
}

# ── Read Check ────────────────────────────────────
check_read() {
    local ENDPOINT="$1"
    local LABEL="$2"
    local URL="$FIREBASE_URL/$ENDPOINT.json"

    TESTED=$((TESTED + 1))
    printf "  %-35s" "[$LABEL]"

    RESPONSE=$(curl -s --max-time 10 "$URL")
    HTTP_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" "$URL")

    if echo "$RESPONSE" | grep -qi "permission_denied\|Permission denied"; then
        echo -e "${GREEN}✅ PERMISSION DENIED${RESET}"
    elif echo "$RESPONSE" | grep -qi "error"; then
        echo -e "${GREEN}✅ ERROR / RESTRICTED${RESET}"
    elif [[ "$HTTP_CODE" == "401" || "$HTTP_CODE" == "403" ]]; then
        echo -e "${GREEN}✅ RESTRICTED (HTTP $HTTP_CODE)${RESET}"
    elif [[ "$RESPONSE" == "null" ]]; then
        echo -e "${YELLOW}⚠️  NULL (endpoint exists, no data)${RESET}"
        FINDINGS+=("$LABEL (null — endpoint exposed)")
    elif [[ -z "$RESPONSE" ]]; then
        echo -e "${YELLOW}❓ EMPTY RESPONSE${RESET}"
    else
        DATA_SIZE=${#RESPONSE}
        echo -e "${RED}🔓 OPEN — $DATA_SIZE bytes returned${RESET}"
        FINDINGS+=("$LABEL (READ OPEN — $DATA_SIZE bytes)")
    fi
}

# ── Write Check ───────────────────────────────────
check_write() {
    local ENDPOINT="firebase_pentest_check"
    local URL="$FIREBASE_URL/$ENDPOINT.json"
    local PAYLOAD='{"checker":"authorized_pentest","timestamp":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}'

    echo ""
    echo -e "${BOLD}── Write Access Test ───────────────────────────${RESET}"
    printf "  %-35s" "[Unauthenticated Write]"

    WRITE_RESPONSE=$(curl -s --max-time 10 -X POST "$URL" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD")
    WRITE_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
        -X POST "$URL" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD")

    if echo "$WRITE_RESPONSE" | grep -qi "permission_denied\|Permission denied"; then
        echo -e "${GREEN}✅ WRITE DENIED${RESET}"
    elif echo "$WRITE_RESPONSE" | grep -qi "name\|timestamp\|checker"; then
        echo -e "${RED}🔓 WRITE OPEN — data written successfully${RESET}"
        WRITE_FINDINGS+=("Unauthenticated write succeeded")

        # Clean up immediately
        printf "  %-35s" "[Cleanup]"
        DELETE_RESPONSE=$(curl -s --max-time 10 -X DELETE \
            "$FIREBASE_URL/$ENDPOINT.json")
        if echo "$DELETE_RESPONSE" | grep -qi "null\|{}"; then
            echo -e "${GREEN}✅ Test data deleted${RESET}"
        else
            echo -e "${YELLOW}⚠️  Manual cleanup needed: DELETE $URL${RESET}"
        fi
    elif [[ "$WRITE_CODE" == "401" || "$WRITE_CODE" == "403" ]]; then
        echo -e "${GREEN}✅ WRITE DENIED (HTTP $WRITE_CODE)${RESET}"
    else
        echo -e "${YELLOW}❓ UNKNOWN — HTTP $WRITE_CODE${RESET}"
        echo -e "       ${YELLOW}↳ Response: $WRITE_RESPONSE${RESET}"
    fi
}

# ── Firestore Check ───────────────────────────────
check_firestore() {
    # Extract project ID from URL
    PROJECT_ID=$(echo "$FIREBASE_URL" | sed 's|https://||' | cut -d'-' -f1-3 | sed 's|-default-rtdb.*||' | sed 's|\.firebaseio\.com||')

    echo ""
    echo -e "${BOLD}── Firestore (if applicable) ───────────────────${RESET}"
    printf "  %-35s" "[Firestore REST API]"

    FIRESTORE_URL="https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents"
    FS_RESPONSE=$(curl -s --max-time 10 "$FIRESTORE_URL")
    FS_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" "$FIRESTORE_URL")

    if echo "$FS_RESPONSE" | grep -qi "PERMISSION_DENIED\|UNAUTHENTICATED"; then
        echo -e "${GREEN}✅ RESTRICTED${RESET}"
    elif [[ "$FS_CODE" == "200" ]]; then
        echo -e "${RED}🔓 OPEN — Firestore accessible${RESET}"
        FINDINGS+=("Firestore REST API open")
    else
        echo -e "${YELLOW}❓ UNKNOWN — HTTP $FS_CODE${RESET}"
    fi
}

# ── Severity Summary ──────────────────────────────
severity() {
    echo ""
    echo -e "${BOLD}================================================${RESET}"
    echo -e "${BOLD} Results Summary${RESET}"
    echo -e "${BOLD}================================================${RESET}"
    echo -e "${CYAN}[*] Target   : $FIREBASE_URL${RESET}"
    echo -e "${CYAN}[*] Endpoints tested: $TESTED${RESET}"
    echo ""

    if [ ${#FINDINGS[@]} -eq 0 ] && [ ${#WRITE_FINDINGS[@]} -eq 0 ]; then
        echo -e "${GREEN}[✅] Database appears properly secured${RESET}"
        echo -e "${GREEN}    Severity: Informational${RESET}"
    else
        if [ ${#WRITE_FINDINGS[@]} -gt 0 ]; then
            echo -e "${RED}[🔓] WRITE ACCESS FINDINGS:${RESET}"
            for f in "${WRITE_FINDINGS[@]}"; do
                echo -e "${RED}    → $f${RESET}"
            done
            echo -e "${RED}${BOLD}    Severity: CRITICAL${RESET}"
            echo ""
        fi

        if [ ${#FINDINGS[@]} -gt 0 ]; then
            echo -e "${RED}[🔓] READ ACCESS FINDINGS:${RESET}"
            for f in "${FINDINGS[@]}"; do
                echo -e "${RED}    → $f${RESET}"
            done
            echo ""

            # Score severity
            HAS_DATA=$(printf '%s\n' "${FINDINGS[@]}" | grep -v "null" | wc -l)
            HAS_SENSITIVE=$(printf '%s\n' "${FINDINGS[@]}" | grep -iE "user|token|message|account|admin|password|key|secret" | wc -l)

            if [ "$HAS_SENSITIVE" -gt 0 ]; then
                echo -e "${RED}${BOLD}    Severity: CRITICAL — sensitive data exposed${RESET}"
            elif [ "$HAS_DATA" -gt 0 ]; then
                echo -e "${RED}${BOLD}    Severity: HIGH — data readable without auth${RESET}"
            else
                echo -e "${YELLOW}${BOLD}    Severity: MEDIUM — endpoints exposed (null data)${RESET}"
            fi
        fi
    fi

    echo ""
    echo -e "${CYAN}[*] Document findings with curl evidence for your report${RESET}"
    echo -e "${BOLD}================================================${RESET}"
}

# ── Main ──────────────────────────────────────────
banner
get_url "$1"

echo -e "${BOLD}── Root & Common Endpoints ─────────────────────${RESET}"
check_read ""              "Root (.json)"
check_read "users"         "Users"
check_read "accounts"      "Accounts"
check_read "messages"      "Messages"
check_read "chats"         "Chats"
check_read "tokens"        "Tokens"
check_read "config"        "Config"
check_read "settings"      "Settings"
check_read "admin"         "Admin"
check_read "data"          "Data"
check_read "api"           "API"

echo ""
echo -e "${BOLD}── Sensitive Endpoints ─────────────────────────${RESET}"
check_read "private"       "Private"
check_read "secrets"       "Secrets"
check_read "keys"          "Keys"
check_read "passwords"     "Passwords"
check_read "credentials"   "Credentials"
check_read "payments"      "Payments"
check_read "transactions"  "Transactions"
check_read "logs"          "Logs"

check_write
check_firestore
severity
