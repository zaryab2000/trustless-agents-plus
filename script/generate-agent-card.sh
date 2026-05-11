#!/usr/bin/env bash
set -euo pipefail

# ==========================================
#  TAP Demo — Agent Card Generator
# ==========================================
#
# Generates dummy agent card(s), uploads to IPFS via Pinata,
# saves records to agents-dummy/, and outputs env vars.
#
# Usage:
#   ./script/demo-track-1/generate-agent-card.sh [start] [count]
#
# Examples:
#   ./script/demo-track-1/generate-agent-card.sh            # TAP_AGENT_1 only
#   ./script/demo-track-1/generate-agent-card.sh 3           # TAP_AGENT_3 only
#   ./script/demo-track-1/generate-agent-card.sh 1 5         # TAP_AGENT_1 through TAP_AGENT_5
#
# Env vars required:
#   PINATA_JWT - Pinata API JWT token
#
# Env vars optional:
#   AGENT_IMAGE_DIR - Directory with profile images (agent_1.png, agent_2.png, ...)
#                     If not set or file missing, uses a deterministic DiceBear URL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DUMMY_DIR="${REPO_ROOT}/agents-dummy"

START_NUM="${1:-1}"
COUNT="${2:-1}"

if [[ -z "${PINATA_JWT:-}" ]]; then
    echo ""
    echo "=========================================="
    echo "  ERROR: PINATA_JWT not set"
    echo "=========================================="
    echo "  Export your Pinata JWT token first:"
    echo "    export PINATA_JWT=<your-jwt>"
    echo ""
    exit 1
fi

mkdir -p "${DUMMY_DIR}"

MODELS=("gpt-4o" "claude-sonnet-4-20250514" "gemini-2.0-flash" "llama-3.1-70b" "mistral-large")
CAPS_POOL=(
    "defi-analysis"
    "portfolio-tracking"
    "yield-optimization"
    "risk-assessment"
    "nft-valuation"
    "market-prediction"
    "liquidity-management"
    "cross-chain-bridging"
    "governance-voting"
    "token-swap"
)

pick_capabilities() {
    local num=$1
    local seed=$((num * 7))
    local c1=${CAPS_POOL[$((seed % ${#CAPS_POOL[@]}))]}
    local c2=${CAPS_POOL[$(((seed + 3) % ${#CAPS_POOL[@]}))]}
    local c3=${CAPS_POOL[$(((seed + 7) % ${#CAPS_POOL[@]}))]}
    echo "\"${c1}\", \"${c2}\", \"${c3}\""
}

get_image_url() {
    local num=$1
    local image_dir="${AGENT_IMAGE_DIR:-}"

    if [[ -n "${image_dir}" ]]; then
        local candidates=("agent_${num}.png" "agent_${num}.jpg" "agent_${num}.svg")
        for fname in "${candidates[@]}"; do
            if [[ -f "${image_dir}/${fname}" ]]; then
                echo "local:${image_dir}/${fname}"
                return
            fi
        done
    fi

    echo "https://api.dicebear.com/9.x/bottts-neutral/svg?seed=TAP_AGENT_${num}"
}

echo ""
echo "==============================================
==============================================
    TAP AGENT CARD GENERATOR
==============================================
=============================================="
echo ""

if [[ "${COUNT}" -gt 1 ]]; then
    echo "  Generating ${COUNT} agents: TAP_AGENT_${START_NUM} to TAP_AGENT_$(( START_NUM + COUNT - 1 ))"
else
    echo "  Generating: TAP_AGENT_${START_NUM}"
fi
echo ""

SUMMARY_FILE="${DUMMY_DIR}/_batch_$(date -u +%Y%m%d_%H%M%S).txt"
: > "${SUMMARY_FILE}"

for (( i = 0; i < COUNT; i++ )); do
    NUM=$(( START_NUM + i ))
    AGENT_NAME="TAP_AGENT_${NUM}"
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    MODEL=${MODELS[$(( NUM % ${#MODELS[@]} ))]}
    CAPABILITIES=$(pick_capabilities "${NUM}")
    IMAGE_URL=$(get_image_url "${NUM}")
    CARD_FILE="${DUMMY_DIR}/${AGENT_NAME}.json"

    echo "=========================================="
    echo "  [${NUM}] ${AGENT_NAME}"
    echo "=========================================="

    if [[ "${IMAGE_URL}" == local:* ]]; then
        LOCAL_PATH="${IMAGE_URL#local:}"
        echo "  Uploading profile image: ${LOCAL_PATH}"
        IMG_RESPONSE=$(curl -s -X POST "https://uploads.pinata.cloud/v3/files" \
            -H "Authorization: Bearer ${PINATA_JWT}" \
            -F "file=@${LOCAL_PATH}")
        IMG_CID=$(echo "${IMG_RESPONSE}" | grep -o '"cid":"[^"]*"' | head -1 | cut -d'"' -f4)
        if [[ -n "${IMG_CID}" ]]; then
            IMAGE_URL="ipfs://${IMG_CID}"
            echo "  Image pinned: ${IMAGE_URL}"
        else
            echo "  WARN: Image upload failed, falling back to DiceBear"
            IMAGE_URL="https://api.dicebear.com/9.x/bottts-neutral/svg?seed=${AGENT_NAME}"
        fi
    fi

    cat > "${CARD_FILE}" << EOF
{
  "name": "${AGENT_NAME}",
  "description": "TAP demo agent #${NUM}. Cross-chain AI agent for testnet simulation.",
  "version": "1.0.0",
  "model": "${MODEL}",
  "capabilities": [${CAPABILITIES}],
  "chains": ["eip155:11155111", "eip155:84532", "eip155:97"],
  "operator": "TAP Demo Team",
  "image": "${IMAGE_URL}",
  "website": "https://tap.push.org",
  "created": "${TIMESTAMP}"
}
EOF

    RESPONSE=$(curl -s -X POST "https://uploads.pinata.cloud/v3/files" \
        -H "Authorization: Bearer ${PINATA_JWT}" \
        -F "file=@${CARD_FILE};filename=${AGENT_NAME}.json")

    IPFS_CID=$(echo "${RESPONSE}" | grep -o '"cid":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [[ -z "${IPFS_CID}" ]]; then
        echo "  ERROR: Pinata upload failed for ${AGENT_NAME}"
        echo "  Response: ${RESPONSE}"
        echo ""
        continue
    fi

    AGENT_URI="ipfs://${IPFS_CID}"
    AGENT_CARD_HASH=$(cast keccak "$(cat "${CARD_FILE}")")

    cat > "${DUMMY_DIR}/${AGENT_NAME}.env" << EOF
# ${AGENT_NAME} — generated $(date -u +"%Y-%m-%d %H:%M:%S UTC")
AGENT_NAME=${AGENT_NAME}
AGENT_URI=${AGENT_URI}
AGENT_CARD_HASH=${AGENT_CARD_HASH}
AGENT_IMAGE=${IMAGE_URL}
AGENT_MODEL=${MODEL}
AGENT_CARD_FILE=${CARD_FILE}
EOF

    echo "  IPFS URI:     ${AGENT_URI}"
    echo "  Card Hash:    ${AGENT_CARD_HASH}"
    echo "  Image:        ${IMAGE_URL}"
    echo "  Saved to:     agents-dummy/${AGENT_NAME}.json"
    echo "                agents-dummy/${AGENT_NAME}.env"
    echo "------------------------------------------"
    echo ""

    {
        echo "# ${AGENT_NAME}"
        echo "export AGENT_URI=\"${AGENT_URI}\""
        echo "export AGENT_CARD_HASH=${AGENT_CARD_HASH}"
        echo ""
    } >> "${SUMMARY_FILE}"
done

echo "=========================================="
echo "  SUMMARY"
echo "=========================================="
echo ""
echo "  Agents generated: ${COUNT}"
echo "  Records saved to: agents-dummy/"
echo ""

if [[ "${COUNT}" -eq 1 ]]; then
    echo "  export AGENT_URI=\"${AGENT_URI}\""
    echo "  export AGENT_CARD_HASH=${AGENT_CARD_HASH}"
else
    echo "  All export lines saved to:"
    echo "    ${SUMMARY_FILE}"
    echo ""
    echo "  To load a specific agent:"
    echo "    source agents-dummy/TAP_AGENT_<N>.env"
fi
echo ""
echo "=========================================="
echo ""
