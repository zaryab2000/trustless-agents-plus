#!/usr/bin/env bash
set -euo pipefail

# ==========================================
#  TAP Demo — Register Agent on External Chain
# ==========================================
#
# Wraps the Forge registration script, parses the returned agent ID,
# and saves it to the agent's .env file in agents-dummy/.
#
# Usage:
#   ./script/demo-track-1/register-on-ext-chain.sh <agent_number> <chain>
#
# Examples:
#   ./script/demo-track-1/register-on-ext-chain.sh 1 sepolia
#   ./script/demo-track-1/register-on-ext-chain.sh 1 base
#   ./script/demo-track-1/register-on-ext-chain.sh 1 bsc
#   ./script/demo-track-1/register-on-ext-chain.sh 2 sepolia
#
#   # Register on all 3 chains at once:
#   ./script/demo-track-1/register-on-ext-chain.sh 1 all
#
# Env vars required:
#   AGENT_BUILDER_KEY    - Private key for the Agent Builder wallet
#   ERC8004_IDENTITY     - ERC-8004 IdentityRegistry address
#
# Env vars optional (loaded from .env if not set):
#   SEPOLIA_RPC, BASE_SEPOLIA_RPC, BSC_TESTNET_RPC

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DUMMY_DIR="${REPO_ROOT}/agents-dummy"
FORGE_SCRIPT="${SCRIPT_DIR}/external-chain/1_RegisterOnExtChain.s.sol"

if [[ -z "${1:-}" || -z "${2:-}" ]]; then
    echo ""
    echo "  Usage: $0 <agent_number> <chain>"
    echo "  chain: sepolia | base | bsc | all"
    echo ""
    exit 1
fi

AGENT_NUM="$1"
CHAIN="$2"
AGENT_NAME="TAP_AGENT_${AGENT_NUM}"
ENV_FILE="${DUMMY_DIR}/${AGENT_NAME}.env"

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "  ERROR: ${ENV_FILE} not found."
    echo "  Run generate-agent-card.sh ${AGENT_NUM} first."
    exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

if [[ -f "${REPO_ROOT}/.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${REPO_ROOT}/.env"
    set +a
fi

ERC8004_IDENTITY="${ERC8004_IDENTITY:-0x8004A818BFB912233c491871b3d84c89A494BD9e}"
SEPOLIA_RPC="${SEPOLIA_RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
BASE_SEPOLIA_RPC="${BASE_SEPOLIA_RPC:-https://sepolia.base.org}"
BSC_TESTNET_RPC="${BSC_TESTNET_RPC:-https://data-seed-prebsc-1-s1.bnbchain.org:8545}"

register_on_chain() {
    local chain_name="$1"
    local rpc_url="$2"
    local env_key="$3"

    echo ""
    echo "=========================================="
    echo "  Registering ${AGENT_NAME} on ${chain_name}"
    echo "=========================================="

    OUTPUT=$(AGENT_URI="${AGENT_URI}" \
        ERC8004_IDENTITY="${ERC8004_IDENTITY}" \
        forge script "${FORGE_SCRIPT}" \
        --private-key "${AGENT_BUILDER_KEY}" \
        --rpc-url "${rpc_url}" --broadcast -vvvv 2>&1)

    AGENT_ID=$(echo "${OUTPUT}" | grep "BOUND_AGENT_ID_" | grep -o '[0-9]*$')

    if [[ -z "${AGENT_ID}" ]]; then
        echo "  ERROR: Could not parse agent ID from output"
        echo "${OUTPUT}" | tail -20
        return 1
    fi

    if grep -q "^${env_key}=" "${ENV_FILE}" 2>/dev/null; then
        sed -i '' "s/^${env_key}=.*/${env_key}=${AGENT_ID}/" "${ENV_FILE}"
    else
        if ! grep -q "# Source chain registrations" "${ENV_FILE}" 2>/dev/null; then
            echo "" >> "${ENV_FILE}"
            echo "# Source chain registrations (Step 1)" >> "${ENV_FILE}"
        fi
        echo "${env_key}=${AGENT_ID}" >> "${ENV_FILE}"
    fi

    echo "  Agent ID:  ${AGENT_ID}"
    echo "  Saved:     ${env_key}=${AGENT_ID} -> ${ENV_FILE}"
    echo "------------------------------------------"
}

case "${CHAIN}" in
    sepolia|eth)
        register_on_chain "Ethereum Sepolia" "${SEPOLIA_RPC}" "BOUND_AGENT_ID_ETH"
        ;;
    base)
        register_on_chain "Base Sepolia" "${BASE_SEPOLIA_RPC}" "BOUND_AGENT_ID_BASE"
        ;;
    bsc)
        register_on_chain "BSC Testnet" "${BSC_TESTNET_RPC}" "BOUND_AGENT_ID_BSC"
        ;;
    all)
        register_on_chain "Ethereum Sepolia" "${SEPOLIA_RPC}" "BOUND_AGENT_ID_ETH"
        register_on_chain "Base Sepolia" "${BASE_SEPOLIA_RPC}" "BOUND_AGENT_ID_BASE"
        register_on_chain "BSC Testnet" "${BSC_TESTNET_RPC}" "BOUND_AGENT_ID_BSC"
        ;;
    *)
        echo "  ERROR: Unknown chain '${CHAIN}'"
        echo "  Use: sepolia | base | bsc | all"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "  REGISTRATION COMPLETE"
echo "=========================================="
echo "  Agent:     ${AGENT_NAME}"
echo "  Env file:  ${ENV_FILE}"
echo ""
echo "  To load:   source ${ENV_FILE}"
echo "=========================================="
echo ""
