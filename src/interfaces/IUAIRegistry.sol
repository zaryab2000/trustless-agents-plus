// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    AgentNotRegistered,
    AgentCardHashRequired,
    UnsupportedProofType,
    ShadowAlreadyClaimed,
    ShadowNotFound,
    ShadowLinkExpired,
    ShadowLinkNonceUsed,
    InvalidShadowSignature,
    InvalidChainIdentifier,
    InvalidRegistryAddress,
    IdentityNotTransferable,
    MaxShadowsExceeded
} from "../libraries/Errors.sol";

/// @title IUAIRegistry
/// @notice ERC-8004-compatible Universal Agent Identity Registry on Push Chain.
///         Uses UEA addresses as canonical agent identifiers.
///         agentId = uint256(uint160(ueaAddress)) — deterministic, collision-free.
///         Non-transferable (soulbound).
interface IUAIRegistry {
    // ──────────────────────────────────────────────
    //  Types
    // ──────────────────────────────────────────────

    /// @notice Proof mechanism used to verify shadow ownership.
    enum ShadowProofType {
        OWNER_KEY_SIGNED
    }

    /// @notice On-chain record for a registered agent identity.
    struct AgentRecord {
        bool registered;
        string agentURI;
        bytes32 agentCardHash;
        uint64 registeredAt;
        string originChainNamespace;
        string originChainId;
        bytes ownerKey;
        bool nativeToPush;
    }

    /// @notice Stored link between a canonical agent and a per-chain shadow identity.
    struct ShadowEntry {
        string chainNamespace;
        string chainId;
        address registryAddress;
        uint256 shadowAgentId;
        ShadowProofType proofType;
        bool verified;
        uint64 linkedAt;
    }

    /// @notice Input payload for creating a shadow link.
    /// @dev `proofData` encoding depends on the proof type:
    ///      - OWNER_KEY_SIGNED (ECDSA): raw 65-byte signature (r ‖ s ‖ v).
    ///      - OWNER_KEY_SIGNED (ERC-1271): `abi.encodePacked(signerAddress, signatureBytes)`
    ///        where `signerAddress` is the 20-byte contract address that implements ERC-1271,
    ///        and `signatureBytes` is the contract-specific signature passed to `isValidSignature`.
    struct ShadowLinkRequest {
        string chainNamespace;
        string chainId;
        address registryAddress;
        uint256 shadowAgentId;
        ShadowProofType proofType;
        bytes proofData;
        uint256 nonce;
        uint256 deadline;
    }

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    /// @notice Emitted when a new agent identity is registered.
    event Registered(
        uint256 indexed agentId,
        address indexed uea,
        string originChainNamespace,
        string originChainId,
        bytes ownerKey,
        string agentURI,
        bytes32 agentCardHash
    );

    /// @notice Emitted when an agent's URI is updated (via setAgentURI or re-registration).
    event AgentURIUpdated(uint256 indexed agentId, string newAgentURI);

    /// @notice Emitted when an agent's card hash is updated (via setAgentCardHash or re-registration).
    event AgentCardHashUpdated(uint256 indexed agentId, bytes32 newHash);

    /// @notice Emitted when a shadow identity is linked to a canonical agent.
    event ShadowLinked(
        uint256 indexed agentId,
        string chainNamespace,
        string chainId,
        address registryAddress,
        uint256 shadowAgentId,
        ShadowProofType proofType,
        bool verified
    );

    /// @notice Emitted when a shadow identity is unlinked from a canonical agent.
    event ShadowUnlinked(
        uint256 indexed agentId,
        string chainNamespace,
        string chainId,
        address registryAddress
    );

    // ──────────────────────────────────────────────
    //  Registration
    // ──────────────────────────────────────────────

    /// @notice Register a new agent identity or update an existing one.
    /// @dev On first call, creates a record with origin metadata from the UEA factory.
    ///      Subsequent calls update `agentURI` and `agentCardHash` only.
    /// @param agentURI Metadata URI (e.g. IPFS CID) for the agent card.
    /// @param agentCardHash Keccak-256 hash of the agent card content.
    /// @return agentId Deterministic ID derived as `uint256(uint160(msg.sender))`.
    function register(
        string calldata agentURI,
        bytes32 agentCardHash
    ) external returns (uint256 agentId);

    /// @notice Update the metadata URI for the caller's agent.
    /// @param newAgentURI New metadata URI.
    function setAgentURI(string calldata newAgentURI) external;

    /// @notice Update the agent card hash for the caller's agent.
    /// @param newHash New keccak-256 hash of the agent card content.
    function setAgentCardHash(bytes32 newHash) external;

    // ──────────────────────────────────────────────
    //  Shadow Linking
    // ──────────────────────────────────────────────

    /// @notice Link a per-chain ERC-8004 agent identity to the caller's canonical agent.
    /// @dev Only one shadow per (chainNamespace, chainId, registryAddress) tuple is
    ///      allowed per agent. Linking a second shadow from the same registry requires
    ///      unlinking the first. This constraint exists because the reverse-lookup index
    ///      keys on the chain+registry tuple without the shadowAgentId.
    /// @param req Shadow link request containing chain identifiers, proof, nonce, and deadline.
    function linkShadow(ShadowLinkRequest calldata req) external;

    /// @notice Remove a shadow link from the caller's canonical agent.
    /// @param chainNamespace CAIP-2 namespace of the shadow chain (e.g. "eip155").
    /// @param chainId CAIP-2 chain ID of the shadow chain (e.g. "1").
    /// @param registryAddress ERC-8004 registry address on the shadow chain.
    function unlinkShadow(
        string calldata chainNamespace,
        string calldata chainId,
        address registryAddress
    ) external;

    // ──────────────────────────────────────────────
    //  Reads — ERC-8004-shaped
    // ──────────────────────────────────────────────

    /// @notice Return the owner (UEA address) of a registered agent.
    /// @param agentId The agent identifier.
    /// @return The UEA address that owns this agent identity.
    function ownerOf(uint256 agentId) external view returns (address);

    /// @notice Return the metadata URI for a registered agent (ERC-721 compatible).
    /// @param agentId The agent identifier.
    /// @return The agent's metadata URI string.
    function tokenURI(uint256 agentId) external view returns (string memory);

    /// @notice Return the agent card URI (ERC-8004 alias for tokenURI).
    /// @param agentId The agent identifier.
    /// @return The agent's metadata URI string.
    function agentURI(uint256 agentId) external view returns (string memory);

    // ──────────────────────────────────────────────
    //  Reads — UAIRegistry-specific
    // ──────────────────────────────────────────────

    /// @notice Return the canonical UEA address for an agent ID.
    /// @param agentId The agent identifier.
    /// @return The UEA address (identical to `address(uint160(agentId))`).
    function canonicalUEA(uint256 agentId) external view returns (address);

    /// @notice Return the agent ID for a UEA address, or 0 if unregistered.
    /// @param uea The UEA address to look up.
    /// @return The agent ID, or 0 if no agent is registered at this address.
    function agentIdOfUEA(address uea) external view returns (uint256);

    /// @notice Return all shadow entries linked to an agent.
    /// @param agentId The agent identifier.
    /// @return Array of shadow entries (empty if none linked).
    function getShadows(
        uint256 agentId
    ) external view returns (ShadowEntry[] memory);

    /// @notice Resolve a shadow identity to its canonical UEA.
    /// @param chainNamespace CAIP-2 namespace of the shadow chain.
    /// @param chainId CAIP-2 chain ID of the shadow chain.
    /// @param registryAddress ERC-8004 registry on the shadow chain.
    /// @param shadowAgentId Agent ID on the shadow chain registry.
    /// @return canonical The canonical UEA address (address(0) if not linked).
    /// @return verified Whether the shadow link has been cryptographically verified.
    function canonicalUEAFromShadow(
        string calldata chainNamespace,
        string calldata chainId,
        address registryAddress,
        uint256 shadowAgentId
    ) external view returns (address canonical, bool verified);

    /// @notice Check whether an agent ID is registered.
    /// @param agentId The agent identifier.
    /// @return True if the agent is registered.
    function isRegistered(uint256 agentId) external view returns (bool);

    /// @notice Return the full on-chain record for an agent.
    /// @param agentId The agent identifier.
    /// @return The agent's record (zeroed if unregistered).
    function getAgentRecord(
        uint256 agentId
    ) external view returns (AgentRecord memory);

    // ──────────────────────────────────────────────
    //  ERC-721 transfer surface — all revert
    // ──────────────────────────────────────────────

    /// @notice Always reverts — agent identities are soulbound.
    function transferFrom(address from, address to, uint256 tokenId) external;

    /// @notice Always reverts — agent identities are soulbound.
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /// @notice Always reverts — agent identities are soulbound.
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;

    /// @notice Always reverts — agent identities are soulbound.
    function approve(address spender, uint256 tokenId) external;

    /// @notice Always reverts — agent identities are soulbound.
    function setApprovalForAll(address operator, bool approved) external;
}
