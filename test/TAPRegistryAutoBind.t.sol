// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TAPRegistry} from "src/TAPRegistry.sol";
import {ITAPRegistry} from "src/interfaces/ITAPRegistry.sol";
import {RegistryErrors} from "src/libraries/RegistryErrors.sol";
import {MockUEAFactory} from "./mocks/MockUEAFactory.sol";
import {UniversalAccountId} from "src/libraries/Types.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract TAPRegistryAutoBindTest is Test {
    TAPRegistry public registry;
    MockUEAFactory public factory;

    address public admin = makeAddr("admin");
    address public pauser = makeAddr("pauser");

    address public ueaUser;
    uint256 public ueaUserKey;

    address public ueaUserAlt;

    address public realOwner;
    uint256 public realOwnerKey;

    address constant ERC8004_ETH = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address constant ERC8004_BASE = 0x8004A818BFB912233c491871b3d84c89A494BD9e;

    bytes32 constant CARD_HASH = keccak256("agent-card");
    string constant AGENT_URI = "ipfs://QmTest";

    bytes32 public constant BIND_TYPEHASH = keccak256(
        "Bind(address canonicalOwner,string chainNamespace,string chainId,"
        "address registryAddress,uint256 boundAgentId,uint256 nonce,uint256 deadline)"
    );

    function setUp() public {
        (ueaUser, ueaUserKey) = makeAddrAndKey("ueaUser");
        (realOwner, realOwnerKey) = makeAddrAndKey("realOwner");
        ueaUserAlt = makeAddr("ueaUserAlt");

        factory = new MockUEAFactory();

        factory.addUEA(
            ueaUser,
            UniversalAccountId({
                chainNamespace: "eip155", chainId: "11155111", owner: abi.encodePacked(ueaUser)
            })
        );

        factory.addUEA(
            ueaUserAlt,
            UniversalAccountId({
                chainNamespace: "eip155", chainId: "84532", owner: abi.encodePacked(realOwner)
            })
        );

        factory.addUEA(
            realOwner,
            UniversalAccountId({
                chainNamespace: "eip155", chainId: "11155111", owner: abi.encodePacked(realOwner)
            })
        );

        TAPRegistry impl = new TAPRegistry(factory);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl), admin, abi.encodeCall(TAPRegistry.initialize, (admin, pauser))
        );
        registry = TAPRegistry(address(proxy));
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    function _getDomainSeparator() internal view returns (bytes32) {
        (
            ,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,,
        ) = registry.eip712Domain();

        return keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,"
                    "uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );
    }

    function _signBind(
        uint256 signerKey,
        address canonicalOwner,
        string memory chainNs,
        string memory chainId,
        address registryAddr,
        uint256 boundAgentId,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                BIND_TYPEHASH,
                canonicalOwner,
                keccak256(bytes(chainNs)),
                keccak256(bytes(chainId)),
                registryAddr,
                boundAgentId,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // ══════════════════════════════════════════════
    //  Part 1: agentIdFromBinding() view function
    // ══════════════════════════════════════════════

    function test_AgentIdFromBinding_ValidBinding_ReturnsCorrect() public {
        vm.prank(ueaUser);
        uint256 agentId = registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);

        (uint256 resolved, bool exists) =
            registry.agentIdFromBinding("eip155", "11155111", ERC8004_ETH, 5);
        assertEq(resolved, agentId);
        assertTrue(exists);
    }

    function test_AgentIdFromBinding_NoBinding_ReturnsFalse() public view {
        (uint256 resolved, bool exists) =
            registry.agentIdFromBinding("eip155", "1", ERC8004_ETH, 999);
        assertEq(resolved, 0);
        assertFalse(exists);
    }

    function test_AgentIdFromBinding_AfterUnbind_ReturnsFalse() public {
        vm.prank(ueaUser);
        registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);

        vm.prank(ueaUser);
        registry.unbind("eip155", "11155111", ERC8004_ETH);

        (uint256 resolved, bool exists) =
            registry.agentIdFromBinding("eip155", "11155111", ERC8004_ETH, 5);
        assertEq(resolved, 0);
        assertFalse(exists);
    }

    function test_AgentIdFromBinding_WrongRegistry_ReturnsFalse() public {
        vm.prank(ueaUser);
        registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);

        (uint256 resolved, bool exists) =
            registry.agentIdFromBinding("eip155", "11155111", ERC8004_BASE, 5);
        assertEq(resolved, 0);
        assertFalse(exists);
    }

    function test_AgentIdFromBinding_WrongBoundAgentId_ReturnsFalse() public {
        vm.prank(ueaUser);
        registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);

        (uint256 resolved, bool exists) =
            registry.agentIdFromBinding("eip155", "11155111", ERC8004_ETH, 999);
        assertEq(resolved, 0);
        assertFalse(exists);
    }

    function test_AgentIdFromBinding_WrongChain_ReturnsFalse() public {
        vm.prank(ueaUser);
        registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);

        (uint256 resolved, bool exists) = registry.agentIdFromBinding("eip155", "1", ERC8004_ETH, 5);
        assertEq(resolved, 0);
        assertFalse(exists);
    }

    function test_AgentIdFromBinding_ManualBind_ReturnsCorrect() public {
        vm.prank(ueaUser);
        uint256 agentId = registry.register(AGENT_URI, CARD_HASH);

        ITAPRegistry.BindRequest memory req = ITAPRegistry.BindRequest({
            chainNamespace: "eip155",
            chainId: "11155111",
            registryAddress: ERC8004_ETH,
            boundAgentId: 42,
            proofType: ITAPRegistry.BindProofType.OWNER_KEY_SIGNED,
            proofData: _signBind(
                ueaUserKey,
                ueaUser,
                "eip155",
                "11155111",
                ERC8004_ETH,
                42,
                1,
                block.timestamp + 1 hours
            ),
            nonce: 1,
            deadline: block.timestamp + 1 hours
        });

        vm.prank(ueaUser);
        registry.bind(req);

        (uint256 resolved, bool exists) =
            registry.agentIdFromBinding("eip155", "11155111", ERC8004_ETH, 42);
        assertEq(resolved, agentId);
        assertTrue(exists);
    }

    // ══════════════════════════════════════════════
    //  Part 2: Auto-bind on registration
    // ══════════════════════════════════════════════

    // ──────────────────────────────────────────────
    //  Happy path
    // ──────────────────────────────────────────────

    function test_RegisterAutoBind_HappyPath_CreatesBinding() public {
        vm.prank(ueaUser);
        uint256 agentId = registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);

        ITAPRegistry.BindEntry[] memory bindings = registry.getBindings(agentId);
        assertEq(bindings.length, 1);
        assertEq(bindings[0].chainNamespace, "eip155");
        assertEq(bindings[0].chainId, "11155111");
        assertEq(bindings[0].registryAddress, ERC8004_ETH);
        assertEq(bindings[0].boundAgentId, 5);
        assertTrue(bindings[0].verified);
        assertEq(bindings[0].linkedAt, block.timestamp);
    }

    function test_RegisterAutoBind_EmitsBothEvents() public {
        uint256 expectedId = uint256(uint160(ueaUser)) % 10_000_000;

        vm.expectEmit(true, true, false, true);
        emit ITAPRegistry.Registered(
            expectedId,
            ueaUser,
            "eip155",
            "11155111",
            abi.encodePacked(ueaUser),
            AGENT_URI,
            CARD_HASH
        );
        vm.expectEmit(true, false, false, true);
        emit ITAPRegistry.AgentBound(
            expectedId,
            "eip155",
            "11155111",
            ERC8004_ETH,
            5,
            ITAPRegistry.BindProofType.OWNER_KEY_SIGNED,
            true
        );

        vm.prank(ueaUser);
        registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);
    }

    function test_RegisterAutoBind_ReverseLookupsWork() public {
        vm.prank(ueaUser);
        uint256 agentId = registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);

        (address canonical, bool verified) =
            registry.canonicalOwnerFromBinding("eip155", "11155111", ERC8004_ETH, 5);
        assertEq(canonical, ueaUser);
        assertTrue(verified);

        (uint256 resolved, bool exists) =
            registry.agentIdFromBinding("eip155", "11155111", ERC8004_ETH, 5);
        assertEq(resolved, agentId);
        assertTrue(exists);
    }

    function test_RegisterAutoBind_RecordCreatedCorrectly() public {
        vm.prank(ueaUser);
        uint256 agentId = registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);

        ITAPRegistry.AgentRecord memory rec = registry.getAgentRecord(agentId);
        assertTrue(rec.registered);
        assertEq(rec.agentURI, AGENT_URI);
        assertEq(rec.agentCardHash, CARD_HASH);
        assertEq(rec.originChainNamespace, "eip155");
        assertEq(rec.originChainId, "11155111");
    }

    // ──────────────────────────────────────────────
    //  Zero registry → no bind
    // ──────────────────────────────────────────────

    function test_RegisterAutoBind_ZeroRegistry_NoBind() public {
        vm.prank(ueaUser);
        uint256 agentId = registry.register(AGENT_URI, CARD_HASH, address(0), 5);

        ITAPRegistry.BindEntry[] memory bindings = registry.getBindings(agentId);
        assertEq(bindings.length, 0);

        assertTrue(registry.isRegistered(agentId));
    }

    // ──────────────────────────────────────────────
    //  Alias path: existing binding → skip silently
    // ──────────────────────────────────────────────

    function test_RegisterAutoBind_Alias_SameChainBinding_Skips() public {
        address aliasFromSameChain = makeAddr("aliasFromSameChain");
        factory.addUEA(
            aliasFromSameChain,
            UniversalAccountId({
                chainNamespace: "eip155", chainId: "11155111", owner: abi.encodePacked(realOwner)
            })
        );

        vm.prank(realOwner);
        uint256 agentId = registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);

        ITAPRegistry.BindEntry[] memory before = registry.getBindings(agentId);
        assertEq(before.length, 1);

        vm.prank(aliasFromSameChain);
        uint256 aliasId = registry.register("ipfs://updated", keccak256("new"), ERC8004_ETH, 5);
        assertEq(aliasId, agentId);

        ITAPRegistry.BindEntry[] memory after_ = registry.getBindings(agentId);
        assertEq(after_.length, 1);
    }

    function test_RegisterAutoBind_Alias_NewChain_CreatesBind() public {
        vm.prank(realOwner);
        uint256 agentId = registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);

        vm.prank(ueaUserAlt);
        registry.register("ipfs://updated", keccak256("new"), ERC8004_BASE, 10);

        ITAPRegistry.BindEntry[] memory bindings = registry.getBindings(agentId);
        assertEq(bindings.length, 2);
        assertEq(bindings[0].chainId, "11155111");
        assertEq(bindings[0].boundAgentId, 5);
        assertEq(bindings[1].chainId, "84532");
        assertEq(bindings[1].boundAgentId, 10);
    }

    // ──────────────────────────────────────────────
    //  Update path (same UEA re-registers)
    // ──────────────────────────────────────────────

    function test_RegisterAutoBind_Update_SkipsDuplicate() public {
        vm.startPrank(ueaUser);
        uint256 agentId = registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);

        registry.register("ipfs://updated", keccak256("new"), ERC8004_ETH, 5);
        vm.stopPrank();

        ITAPRegistry.BindEntry[] memory bindings = registry.getBindings(agentId);
        assertEq(bindings.length, 1);

        assertEq(registry.getAgentRecord(agentId).agentURI, "ipfs://updated");
    }

    // ──────────────────────────────────────────────
    //  Coexistence with manual bind()
    // ──────────────────────────────────────────────

    function test_RegisterAutoBind_ManualBindCoexists() public {
        vm.prank(ueaUser);
        uint256 agentId = registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);

        ITAPRegistry.BindRequest memory req = ITAPRegistry.BindRequest({
            chainNamespace: "eip155",
            chainId: "84532",
            registryAddress: ERC8004_BASE,
            boundAgentId: 10,
            proofType: ITAPRegistry.BindProofType.OWNER_KEY_SIGNED,
            proofData: _signBind(
                ueaUserKey,
                ueaUser,
                "eip155",
                "84532",
                ERC8004_BASE,
                10,
                1,
                block.timestamp + 1 hours
            ),
            nonce: 1,
            deadline: block.timestamp + 1 hours
        });

        vm.prank(ueaUser);
        registry.bind(req);

        ITAPRegistry.BindEntry[] memory bindings = registry.getBindings(agentId);
        assertEq(bindings.length, 2);
        assertEq(bindings[0].chainId, "11155111");
        assertEq(bindings[1].chainId, "84532");
    }

    // ──────────────────────────────────────────────
    //  Dedup collision: different agent same binding
    // ──────────────────────────────────────────────

    function test_RegisterAutoBind_DedupCollision_SkipsSilently() public {
        vm.prank(ueaUser);
        registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);

        address otherUea = makeAddr("otherUea");
        factory.addUEA(
            otherUea,
            UniversalAccountId({
                chainNamespace: "eip155", chainId: "11155111", owner: abi.encodePacked(otherUea)
            })
        );

        vm.prank(otherUea);
        uint256 otherId = registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);

        ITAPRegistry.BindEntry[] memory bindings = registry.getBindings(otherId);
        assertEq(bindings.length, 0);
    }

    // ──────────────────────────────────────────────
    //  Native Push account (no separate registry)
    // ──────────────────────────────────────────────

    function test_RegisterAutoBind_NativePush_ZeroRegistry_NoBind() public {
        address nativeUser = makeAddr("nativeUser");

        vm.prank(nativeUser);
        uint256 agentId = registry.register(AGENT_URI, CARD_HASH, address(0), 0);

        ITAPRegistry.BindEntry[] memory bindings = registry.getBindings(agentId);
        assertEq(bindings.length, 0);

        ITAPRegistry.AgentRecord memory rec = registry.getAgentRecord(agentId);
        assertTrue(rec.nativeToPush);
    }

    // ──────────────────────────────────────────────
    //  MAX_BINDINGS respected
    // ──────────────────────────────────────────────

    function test_RegisterAutoBind_MaxBindings_Reverts() public {
        vm.prank(ueaUser);
        uint256 agentId = registry.register(AGENT_URI, CARD_HASH);

        vm.startPrank(ueaUser);
        for (uint256 i = 0; i < 64; i++) {
            string memory chainId = vm.toString(i + 100);
            ITAPRegistry.BindRequest memory req = ITAPRegistry.BindRequest({
                chainNamespace: "eip155",
                chainId: chainId,
                registryAddress: ERC8004_ETH,
                boundAgentId: i,
                proofType: ITAPRegistry.BindProofType.OWNER_KEY_SIGNED,
                proofData: _signBind(
                    ueaUserKey,
                    ueaUser,
                    "eip155",
                    chainId,
                    ERC8004_ETH,
                    i,
                    i + 10,
                    block.timestamp + 1 hours
                ),
                nonce: i + 10,
                deadline: block.timestamp + 1 hours
            });
            registry.bind(req);
        }
        vm.stopPrank();

        assertEq(registry.getBindings(agentId).length, 64);

        address fullUser = makeAddr("fullUser");
        factory.addUEA(
            fullUser,
            UniversalAccountId({
                chainNamespace: "eip155", chainId: "11155111", owner: abi.encodePacked(ueaUser)
            })
        );

        vm.prank(fullUser);
        vm.expectRevert(
            abi.encodeWithSelector(RegistryErrors.MaxBindingsExceeded.selector, agentId)
        );
        registry.register("ipfs://full", keccak256("full"), ERC8004_BASE, 99);
    }

    // ──────────────────────────────────────────────
    //  Unbind auto-bound entry, then rebind
    // ──────────────────────────────────────────────

    function test_RegisterAutoBind_UnbindAndRebind() public {
        vm.prank(ueaUser);
        uint256 agentId = registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);

        vm.prank(ueaUser);
        registry.unbind("eip155", "11155111", ERC8004_ETH);

        assertEq(registry.getBindings(agentId).length, 0);

        ITAPRegistry.BindRequest memory req = ITAPRegistry.BindRequest({
            chainNamespace: "eip155",
            chainId: "11155111",
            registryAddress: ERC8004_ETH,
            boundAgentId: 5,
            proofType: ITAPRegistry.BindProofType.OWNER_KEY_SIGNED,
            proofData: _signBind(
                ueaUserKey,
                ueaUser,
                "eip155",
                "11155111",
                ERC8004_ETH,
                5,
                1,
                block.timestamp + 1 hours
            ),
            nonce: 1,
            deadline: block.timestamp + 1 hours
        });

        vm.prank(ueaUser);
        registry.bind(req);

        assertEq(registry.getBindings(agentId).length, 1);
    }

    // ──────────────────────────────────────────────
    //  Paused → reverts
    // ──────────────────────────────────────────────

    function test_RegisterAutoBind_WhenPaused_Reverts() public {
        vm.prank(pauser);
        registry.pause();

        vm.prank(ueaUser);
        vm.expectRevert();
        registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);
    }

    // ──────────────────────────────────────────────
    //  Zero card hash → reverts
    // ──────────────────────────────────────────────

    function test_RegisterAutoBind_ZeroCardHash_Reverts() public {
        vm.prank(ueaUser);
        vm.expectRevert(RegistryErrors.AgentCardHashRequired.selector);
        registry.register(AGENT_URI, bytes32(0), ERC8004_ETH, 5);
    }

    // ──────────────────────────────────────────────
    //  Base overload still works unchanged
    // ──────────────────────────────────────────────

    function test_BaseRegister_StillWorks() public {
        vm.prank(ueaUser);
        uint256 agentId = registry.register(AGENT_URI, CARD_HASH);

        assertTrue(registry.isRegistered(agentId));
        assertEq(registry.getBindings(agentId).length, 0);
    }

    // ──────────────────────────────────────────────
    //  proofType is OWNER_KEY_SIGNED
    // ──────────────────────────────────────────────

    function test_RegisterAutoBind_ProofTypeIsOwnerKeySigned() public {
        vm.prank(ueaUser);
        uint256 agentId = registry.register(AGENT_URI, CARD_HASH, ERC8004_ETH, 5);

        ITAPRegistry.BindEntry[] memory bindings = registry.getBindings(agentId);
        assertEq(uint8(bindings[0].proofType), uint8(ITAPRegistry.BindProofType.OWNER_KEY_SIGNED));
    }
}
