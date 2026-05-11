// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";

/// @notice Minimal interface for ERC-8004 IdentityRegistry on source chains.
interface IERC8004Identity {
    function register(
        string memory agentURI
    ) external returns (uint256 agentId);

    function ownerOf(
        uint256 agentId
    ) external view returns (address);

    function tokenURI(
        uint256 agentId
    ) external view returns (string memory);
}

/// @title 1_RegisterOnExtChain
/// @notice Registers an agent on an external chain's ERC-8004 IdentityRegistry.
///         Run once per source chain (Sepolia, Base Sepolia, BSC Testnet).
///
/// Usage:
///   forge script script/demo/external-chain/1_RegisterOnExtChain.s.sol \
///     --private-key $AGENT_BUILDER_KEY \
///     --rpc-url $SEPOLIA_RPC --broadcast -vvvv
///
/// Env vars required:
///   AGENT_URI        - IPFS URI for agent card (e.g. "ipfs://Qm...")
///   ERC8004_IDENTITY - ERC-8004 IdentityRegistry address
contract RegisterOnExtChain is Script {
    function run() external {
        string memory agentURI = vm.envString("AGENT_URI");
        address registry = vm.envAddress("ERC8004_IDENTITY");

        _header("STEP 1: Register Agent on External Chain");
        _log("Chain ID", vm.toString(block.chainid));
        _log("Registry", vm.toString(registry));
        _log("Caller", vm.toString(msg.sender));
        _log("Agent URI", agentURI);
        _separator();

        vm.startBroadcast();
        uint256 agentId = IERC8004Identity(registry).register(agentURI);
        vm.stopBroadcast();

        _header("REGISTRATION RESULT");
        _log("Agent ID", vm.toString(agentId));
        _log("Agent ID (hex)", vm.toString(bytes32(agentId)));
        _log("Owner", vm.toString(IERC8004Identity(registry).ownerOf(agentId)));
        _log("Token URI", IERC8004Identity(registry).tokenURI(agentId));
        _separator();

        console.log("");
        console.log("  >>> Save this for binding later:");
        console.log("      BOUND_AGENT_ID_%s=%s", _chainLabel(block.chainid), vm.toString(agentId));
        console.log("");
    }

    function _chainLabel(
        uint256 chainId
    ) internal pure returns (string memory) {
        if (chainId == 11_155_111) return "ETH";
        if (chainId == 84_532) return "BASE";
        if (chainId == 97) return "BSC";
        return "UNKNOWN";
    }

    function _header(
        string memory title
    ) internal pure {
        console.log("");
        console.log("==========================================");
        console.log("  %s", title);
        console.log("==========================================");
    }

    function _log(
        string memory key,
        string memory value
    ) internal pure {
        console.log("  %-16s %s", key, value);
    }

    function _separator() internal pure {
        console.log("------------------------------------------");
    }
}
