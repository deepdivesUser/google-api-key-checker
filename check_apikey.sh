#!/bin/bash
# ================================================
# Google API Key Scope Checker
# Author: deepdivesUser

# Description: Tests the scope and restrictions
#              of a Google API key across multiple
#              Google APIs to identify misconfigurations
# Usage:
#   Interactive : ./check_apikey.sh
#   Argument    : ./check_apikey.sh <API_KEY>
#   Env var     : GOOGLE_API_KEY=AIza... ./check_apikey.sh
# ================================================

# ── Colors ──────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Banner ───────────────────────────────────────
banner() {
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║      Google API Key Scope Checker     ║"
    echo "  ║       For authorized testing only     ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${RESET}"
}

# ── Get API Key ───────────────────────────────────
get_key() {
    if [ -n "$1" ]; then
        API_KEY="$1"
        echo -e "${CYAN}[*] Using key from argument${RESET}"
    elif [ -n "$GOOGLE_API_KEY" ]; then
        API_KEY="$GOOGLE_API_KEY"
        echo -e "${CYAN}[*] Using key from environment variable${RESET}"
    else
        echo -e "${YELLOW}[?] Enter Google API key to test:${RESET}"
        read -r -s API_KEY
        echo ""
    fi

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

# ── Standard JSON Check ───────────────────────────
FINDINGS=()

check() {
    local NAME="$1"
    local URL="$2"

    RESPONSE=$(curl -s --max-time 10 "$URL")
    STATUS=$(echo "$RESPONSE" | grep -o '"status" *: *"[^"]*"' | head -1 | grep -o '"[A-Z_]*"$' | tr -d '"')
    ERROR=$(echo "$RESPONSE" | grep -o '"message" *: *"[^"]*"' | head -1 | cut -d'"' -f4)

    printf "  %-30s" "[$NAME]"

    if echo "$RESPONSE" | grep -qE '"error"|"keyInvalid"'; then
        echo -e "${GREEN}✅ DENIED / INVALID${RESET}"
    elif [[ "$STATUS" =~ ^(OK|ZERO_RESULTS)$ ]]; then
        echo -e "${RED}⚠️  ACCESSIBLE${RESET}"
        FINDINGS+=("$NAME")
    elif [[ "$STATUS" == "OVER_QUERY_LIMIT" ]]; then
        echo -e "${YELLOW}⚠️  ACCESSIBLE (quota hit)${RESET}"
        FINDINGS+=("$NAME (quota limited)")
    elif [[ "$STATUS" == "REQUEST_DENIED" ]]; then
        echo -e "${GREEN}✅ RESTRICTED${RESET}"
    elif echo "$RESPONSE" | grep -qE "PERMISSION_DENIED|UNAUTHENTICATED"; then
        echo -e "${GREEN}✅ PERMISSION DENIED${RESET}"
    else
        echo -e "${YELLOW}❓ UNKNOWN${RESET}"
        [ -n "$ERROR" ] && echo -e "       ${YELLOW}↳ $ERROR${RESET}"
    fi
}

# ── Static Maps Image Check ───────────────────────
check_static_maps() {
    local NAME="Static Maps"
    local URL="https://maps.googleapis.com/maps/api/staticmap?center=London&zoom=13&size=600x300&key=$API_KEY"

    printf "  %-30s" "[$NAME]"

    # First check content-type header
    CONTENT_TYPE=$(curl -s --max-time 10 -o /dev/null -w "%{content_type}" "$URL")
    HTTP_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" "$URL")

    if [[ "$CONTENT_TYPE" == *"image/png"* || "$CONTENT_TYPE" == *"image/jpeg"* ]]; then
        echo -e "${RED}⚠️  ACCESSIBLE (returns image — key works)${RESET}"
        FINDINGS+=("$NAME")
    elif [[ "$HTTP_CODE" == "403" ]]; then
        echo -e "${GREEN}✅ RESTRICTED (HTTP 403)${RESET}"
    elif [[ "$HTTP_CODE" == "200" && "$CONTENT_TYPE" == *"json"* ]]; then
        # Fallback: parse JSON response
        RESPONSE=$(curl -s --max-time 10 "$URL")
        STATUS=$(echo "$RESPONSE" | grep -o '"status" *: *"[^"]*"' | head -1 | grep -o '"[A-Z_]*"$' | tr -d '"')
        if [[ "$STATUS" == "REQUEST_DENIED" ]]; then
            echo -e "${GREEN}✅ RESTRICTED${RESET}"
        else
            echo -e "${YELLOW}❓ UNKNOWN — HTTP $HTTP_CODE / $CONTENT_TYPE${RESET}"
        fi
    else
        echo -e "${YELLOW}❓ UNKNOWN — HTTP $HTTP_CODE / $CONTENT_TYPE${RESET}"
    fi
}

# ── Severity Summary ──────────────────────────────
severity() {
    echo ""
    echo -e "${BOLD}================================================${RESET}"
    echo -e "${BOLD} Results Summary${RESET}"
    echo -e "${BOLD}================================================${RESET}"

    if [ ${#FINDINGS[@]} -eq 0 ]; then
        echo -e "${GREEN}[✅] No accessible APIs found — key appears restricted${RESET}"
        echo -e "${GREEN}    Severity: Informational${RESET}"
        echo -e "${GREEN}    Note: Key still exposed in plaintext in APK.${RESET}"
        echo -e "${GREEN}          Recommend moving to server-side or restricting${RESET}"
        echo -e "${GREEN}          by Android app signature in Google Cloud Console.${RESET}"
    else
        echo -e "${RED}[⚠️ ] Accessible APIs found:${RESET}"
        for f in "${FINDINGS[@]}"; do
            echo -e "${RED}    → $f${RESET}"
        done
        echo ""

        COUNT=${#FINDINGS[@]}
        if echo "${FINDINGS[*]}" | grep -qiE "Drive|Cloud|Firebase|Admin|Gmail"; then
            echo -e "${RED}${BOLD}    Severity: CRITICAL — sensitive API access${RESET}"
        elif [ "$COUNT" -ge 3 ]; then
            echo -e "${RED}${BOLD}    Severity: MEDIUM — multiple APIs accessible${RESET}"
        else
            echo -e "${YELLOW}${BOLD}    Severity: LOW — limited API access (cost abuse risk)${RESET}"
        fi
    fi

    echo ""
    echo -e "${CYAN}[*] Tested key: $REDACTED${RESET}"
    echo -e "${CYAN}[*] Document findings for your report${RESET}"
    echo -e "${BOLD}================================================${RESET}"
}

# ── Main ──────────────────────────────────────────
banner
get_key "$1"

echo -e "${BOLD}── Geo / Maps APIs ─────────────────────────────${RESET}"
check           "Geocoding"       "https://maps.googleapis.com/maps/api/geocode/json?address=London&key=$API_KEY"
check           "Places Nearby"   "https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=-33.8670522,151.1957362&radius=500&key=$API_KEY"
check           "Directions"      "https://maps.googleapis.com/maps/api/directions/json?origin=Toronto&destination=Montreal&key=$API_KEY"
check           "Elevation"       "https://maps.googleapis.com/maps/api/elevation/json?locations=39.7391536,-104.9847034&key=$API_KEY"
check           "Street View"     "https://maps.googleapis.com/maps/api/streetview/metadata?location=40.714728,-73.998672&key=$API_KEY"
check_static_maps

echo ""
echo -e "${BOLD}── Other Google APIs ───────────────────────────${RESET}"
check "YouTube"         "https://www.googleapis.com/youtube/v3/search?part=snippet&q=test&key=$API_KEY"
check "Firebase"        "https://firebase.googleapis.com/v1beta1/projects?key=$API_KEY"
check "Cloud Resources" "https://cloudresourcemanager.googleapis.com/v1/projects?key=$API_KEY"
check "Google Drive"    "https://www.googleapis.com/drive/v3/files?key=$API_KEY"
check "Gmail"           "https://gmail.googleapis.com/gmail/v1/users/me/profile?key=$API_KEY"
check "Cloud Storage"   "https://storage.googleapis.com/storage/v1/b?project=test&key=$API_KEY"

severity
