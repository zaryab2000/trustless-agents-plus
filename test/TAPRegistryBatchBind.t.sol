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

contract TAPRegistryBatchBindTest is Test {
    TAPRegistry public registry;
    MockUEAFactory public factory;

    address public admin = makeAddr("admin");
    address public pauser = makeAddr("pauser");
    address public ueaUser;
    uint256 public ueaUserKey;
    uint256 public ueaAgentId;

    bytes32 constant CARD_HASH = keccak256("agent-card");
    string constant AGENT_URI = "ipfs://QmTest";
    address constant ERC8004 = address(0x8004A169FB4a3325136EB29fA0ceB6D2e539a432);

    bytes32 public constant BIND_TYPEHASH = keccak256(
        "Bind(address canonicalOwner,string chainNamespace,string chainId,"
        "address registryAddress,uint256 boundAgentId,uint256 nonce,uint256 deadline)"
    );

    function setUp() public {
        (ueaUser, ueaUserKey) = makeAddrAndKey("ueaUser");

        factory = new MockUEAFactory();
        factory.addUEA(
            ueaUser,
            UniversalAccountId({
                chainNamespace: "eip155", chainId: "1", owner: abi.encodePacked(ueaUser)
            })
        );

        TAPRegistry impl = new TAPRegistry(factory);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl), admin, abi.encodeCall(TAPRegistry.initialize, (admin, pauser))
        );
        registry = TAPRegistry(address(proxy));

        vm.prank(ueaUser);
        ueaAgentId = registry.register(AGENT_URI, CARD_HASH);
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

    function _makeReq(
        string memory chainId,
        uint256 boundAgentId,
        uint256 nonce
    ) internal view returns (ITAPRegistry.BindRequest memory) {
        uint256 deadline = block.timestamp + 1 hours;
        return ITAPRegistry.BindRequest({
            chainNamespace: "eip155",
            chainId: chainId,
            registryAddress: ERC8004,
            boundAgentId: boundAgentId,
            proofType: ITAPRegistry.BindProofType.OWNER_KEY_SIGNED,
            proofData: _signBind(
                ueaUserKey, ueaUser, "eip155", chainId, ERC8004, boundAgentId, nonce, deadline
            ),
            nonce: nonce,
            deadline: deadline
        });
    }

    // ──────────────────────────────────────────────
    //  Happy path
    // ──────────────────────────────────────────────

    function test_BatchBind_SingleEntry_Works() public {
        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](1);
        reqs[0] = _makeReq("1", 42, 1);

        vm.prank(ueaUser);
        registry.batchBind(reqs);

        ITAPRegistry.BindEntry[] memory bindings = registry.getBindings(ueaAgentId);
        assertEq(bindings.length, 1);
        assertEq(bindings[0].chainId, "1");
        assertEq(bindings[0].boundAgentId, 42);
        assertTrue(bindings[0].verified);
    }

    function test_BatchBind_ThreeEntries_AllBound() public {
        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](3);
        reqs[0] = _makeReq("1", 42, 1);
        reqs[1] = _makeReq("8453", 17, 2);
        reqs[2] = _makeReq("42161", 8, 3);

        vm.prank(ueaUser);
        registry.batchBind(reqs);

        ITAPRegistry.BindEntry[] memory bindings = registry.getBindings(ueaAgentId);
        assertEq(bindings.length, 3);
        assertEq(bindings[0].boundAgentId, 42);
        assertEq(bindings[1].boundAgentId, 17);
        assertEq(bindings[2].boundAgentId, 8);
    }

    function test_BatchBind_MaxBatch_Succeeds() public {
        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](10);
        for (uint256 i; i < 10; i++) {
            reqs[i] = _makeReq(vm.toString(i + 100), i, i + 1);
        }

        vm.prank(ueaUser);
        registry.batchBind(reqs);

        ITAPRegistry.BindEntry[] memory bindings = registry.getBindings(ueaAgentId);
        assertEq(bindings.length, 10);
    }

    function test_BatchBind_EventsEmittedPerEntry() public {
        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](3);
        reqs[0] = _makeReq("1", 42, 1);
        reqs[1] = _makeReq("8453", 17, 2);
        reqs[2] = _makeReq("42161", 8, 3);

        vm.expectEmit(true, false, false, true);
        emit ITAPRegistry.AgentBound(
            ueaAgentId,
            "eip155",
            "1",
            ERC8004,
            42,
            ITAPRegistry.BindProofType.OWNER_KEY_SIGNED,
            true
        );
        vm.expectEmit(true, false, false, true);
        emit ITAPRegistry.AgentBound(
            ueaAgentId,
            "eip155",
            "8453",
            ERC8004,
            17,
            ITAPRegistry.BindProofType.OWNER_KEY_SIGNED,
            true
        );
        vm.expectEmit(true, false, false, true);
        emit ITAPRegistry.AgentBound(
            ueaAgentId,
            "eip155",
            "42161",
            ERC8004,
            8,
            ITAPRegistry.BindProofType.OWNER_KEY_SIGNED,
            true
        );

        vm.prank(ueaUser);
        registry.batchBind(reqs);
    }

    function test_BatchBind_ReverseLookupsCorrect() public {
        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](3);
        reqs[0] = _makeReq("1", 42, 1);
        reqs[1] = _makeReq("8453", 17, 2);
        reqs[2] = _makeReq("42161", 8, 3);

        vm.prank(ueaUser);
        registry.batchBind(reqs);

        (address c1, bool v1) = registry.canonicalOwnerFromBinding("eip155", "1", ERC8004, 42);
        (address c2, bool v2) = registry.canonicalOwnerFromBinding("eip155", "8453", ERC8004, 17);
        (address c3, bool v3) = registry.canonicalOwnerFromBinding("eip155", "42161", ERC8004, 8);

        assertEq(c1, ueaUser);
        assertEq(c2, ueaUser);
        assertEq(c3, ueaUser);
        assertTrue(v1);
        assertTrue(v2);
        assertTrue(v3);
    }

    function test_BatchBind_EquivalentToIndividualBinds() public {
        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](3);
        reqs[0] = _makeReq("1", 42, 1);
        reqs[1] = _makeReq("8453", 17, 2);
        reqs[2] = _makeReq("42161", 8, 3);

        vm.prank(ueaUser);
        registry.batchBind(reqs);

        ITAPRegistry.BindEntry[] memory bindings = registry.getBindings(ueaAgentId);

        assertEq(bindings[0].chainNamespace, "eip155");
        assertEq(bindings[0].chainId, "1");
        assertEq(bindings[0].registryAddress, ERC8004);
        assertEq(bindings[0].boundAgentId, 42);
        assertEq(uint8(bindings[0].proofType), uint8(ITAPRegistry.BindProofType.OWNER_KEY_SIGNED));
        assertTrue(bindings[0].verified);
        assertGt(bindings[0].linkedAt, 0);

        assertEq(bindings[1].chainId, "8453");
        assertEq(bindings[1].boundAgentId, 17);

        assertEq(bindings[2].chainId, "42161");
        assertEq(bindings[2].boundAgentId, 8);
    }

    // ──────────────────────────────────────────────
    //  Revert: batch-level errors
    // ──────────────────────────────────────────────

    function test_BatchBind_EmptyArray_Reverts() public {
        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](0);

        vm.prank(ueaUser);
        vm.expectRevert(RegistryErrors.EmptyBindBatch.selector);
        registry.batchBind(reqs);
    }

    function test_BatchBind_ExceedsMaxBatch_Reverts() public {
        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](11);
        for (uint256 i; i < 11; i++) {
            reqs[i] = _makeReq(vm.toString(i + 200), i, i + 1);
        }

        vm.prank(ueaUser);
        vm.expectRevert(abi.encodeWithSelector(RegistryErrors.BatchBindTooLarge.selector, 11, 10));
        registry.batchBind(reqs);
    }

    function test_BatchBind_UnregisteredAgent_Reverts() public {
        address nobody = makeAddr("nobody");
        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](1);
        reqs[0] = _makeReq("1", 42, 1);

        vm.prank(nobody);
        vm.expectRevert(
            abi.encodeWithSelector(
                RegistryErrors.AgentNotRegistered.selector, uint256(uint160(nobody)) % 10_000_000
            )
        );
        registry.batchBind(reqs);
    }

    function test_BatchBind_WhenPaused_Reverts() public {
        vm.prank(pauser);
        registry.pause();

        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](1);
        reqs[0] = _makeReq("1", 42, 1);

        vm.prank(ueaUser);
        vm.expectRevert();
        registry.batchBind(reqs);
    }

    // ──────────────────────────────────────────────
    //  Revert: per-entry errors (atomicity)
    // ──────────────────────────────────────────────

    function test_BatchBind_DuplicateChainInBatch_Reverts() public {
        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](2);
        reqs[0] = _makeReq("1", 42, 1);
        reqs[1] = _makeReq("1", 42, 2);

        vm.prank(ueaUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                RegistryErrors.BindingAlreadyClaimed.selector, "eip155", "1", ERC8004, 42
            )
        );
        registry.batchBind(reqs);
    }

    function test_BatchBind_DuplicateNonceInBatch_Reverts() public {
        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](2);
        reqs[0] = _makeReq("1", 42, 1);
        reqs[1] = _makeReq("8453", 17, 1);

        vm.prank(ueaUser);
        vm.expectRevert(abi.encodeWithSelector(RegistryErrors.BindNonceUsed.selector, 1));
        registry.batchBind(reqs);
    }

    function test_BatchBind_OneInvalidSignature_RevertsAll() public {
        (, uint256 wrongKey) = makeAddrAndKey("wrongSigner");
        uint256 deadline = block.timestamp + 1 hours;

        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](3);
        reqs[0] = _makeReq("1", 42, 1);
        reqs[1] = ITAPRegistry.BindRequest({
            chainNamespace: "eip155",
            chainId: "8453",
            registryAddress: ERC8004,
            boundAgentId: 17,
            proofType: ITAPRegistry.BindProofType.OWNER_KEY_SIGNED,
            proofData: _signBind(wrongKey, ueaUser, "eip155", "8453", ERC8004, 17, 2, deadline),
            nonce: 2,
            deadline: deadline
        });
        reqs[2] = _makeReq("42161", 8, 3);

        vm.prank(ueaUser);
        vm.expectRevert(RegistryErrors.InvalidBindSignature.selector);
        registry.batchBind(reqs);

        ITAPRegistry.BindEntry[] memory bindings = registry.getBindings(ueaAgentId);
        assertEq(bindings.length, 0);
    }

    function test_BatchBind_ExpiredDeadlineInBatch_Reverts() public {
        uint256 expiredDeadline = block.timestamp - 1;

        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](2);
        reqs[0] = _makeReq("1", 42, 1);
        reqs[1] = ITAPRegistry.BindRequest({
            chainNamespace: "eip155",
            chainId: "8453",
            registryAddress: ERC8004,
            boundAgentId: 17,
            proofType: ITAPRegistry.BindProofType.OWNER_KEY_SIGNED,
            proofData: _signBind(
                ueaUserKey, ueaUser, "eip155", "8453", ERC8004, 17, 2, expiredDeadline
            ),
            nonce: 2,
            deadline: expiredDeadline
        });

        vm.prank(ueaUser);
        vm.expectRevert(
            abi.encodeWithSelector(RegistryErrors.BindExpired.selector, expiredDeadline)
        );
        registry.batchBind(reqs);

        assertEq(registry.getBindings(ueaAgentId).length, 0);
    }

    function test_BatchBind_ExceedsMaxBindings_Reverts() public {
        vm.startPrank(ueaUser);
        for (uint256 i; i < 62; i++) {
            string memory chainId = vm.toString(i + 300);
            registry.bind(_makeReq(chainId, i + 1000, i + 50));
        }
        vm.stopPrank();

        assertEq(registry.getBindings(ueaAgentId).length, 62);

        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](3);
        reqs[0] = _makeReq("500", 500, 200);
        reqs[1] = _makeReq("501", 501, 201);
        reqs[2] = _makeReq("502", 502, 202);

        vm.prank(ueaUser);
        vm.expectRevert(
            abi.encodeWithSelector(RegistryErrors.MaxBindingsExceeded.selector, ueaAgentId)
        );
        registry.batchBind(reqs);

        assertEq(registry.getBindings(ueaAgentId).length, 62);
    }

    function test_BatchBind_EmptyChainId_Reverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](2);
        reqs[0] = _makeReq("1", 42, 1);
        reqs[1] = ITAPRegistry.BindRequest({
            chainNamespace: "eip155",
            chainId: "",
            registryAddress: ERC8004,
            boundAgentId: 17,
            proofType: ITAPRegistry.BindProofType.OWNER_KEY_SIGNED,
            proofData: _signBind(ueaUserKey, ueaUser, "eip155", "", ERC8004, 17, 2, deadline),
            nonce: 2,
            deadline: deadline
        });

        vm.prank(ueaUser);
        vm.expectRevert(RegistryErrors.InvalidChainIdentifier.selector);
        registry.batchBind(reqs);

        assertEq(registry.getBindings(ueaAgentId).length, 0);
    }

    function test_BatchBind_ZeroRegistry_Reverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](2);
        reqs[0] = _makeReq("1", 42, 1);
        reqs[1] = ITAPRegistry.BindRequest({
            chainNamespace: "eip155",
            chainId: "8453",
            registryAddress: address(0),
            boundAgentId: 17,
            proofType: ITAPRegistry.BindProofType.OWNER_KEY_SIGNED,
            proofData: _signBind(
                ueaUserKey, ueaUser, "eip155", "8453", address(0), 17, 2, deadline
            ),
            nonce: 2,
            deadline: deadline
        });

        vm.prank(ueaUser);
        vm.expectRevert(RegistryErrors.InvalidRegistryAddress.selector);
        registry.batchBind(reqs);
    }

    // ──────────────────────────────────────────────
    //  Interaction: batch + individual bind
    // ──────────────────────────────────────────────

    function test_BatchBind_AfterIndividualBind_Appends() public {
        vm.startPrank(ueaUser);

        registry.bind(_makeReq("1", 42, 1));

        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](2);
        reqs[0] = _makeReq("8453", 17, 2);
        reqs[1] = _makeReq("42161", 8, 3);
        registry.batchBind(reqs);

        vm.stopPrank();

        ITAPRegistry.BindEntry[] memory bindings = registry.getBindings(ueaAgentId);
        assertEq(bindings.length, 3);
        assertEq(bindings[0].boundAgentId, 42);
        assertEq(bindings[1].boundAgentId, 17);
        assertEq(bindings[2].boundAgentId, 8);
    }

    function test_BatchBind_NoncesConsumed_IndividualBindReuseFails() public {
        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](2);
        reqs[0] = _makeReq("1", 42, 1);
        reqs[1] = _makeReq("8453", 17, 2);

        vm.startPrank(ueaUser);
        registry.batchBind(reqs);

        ITAPRegistry.BindRequest memory req3 = _makeReq("42161", 8, 1);
        vm.expectRevert(abi.encodeWithSelector(RegistryErrors.BindNonceUsed.selector, 1));
        registry.bind(req3);
        vm.stopPrank();
    }

    function test_BatchBind_UnbindThenRebatch_Succeeds() public {
        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](2);
        reqs[0] = _makeReq("1", 42, 1);
        reqs[1] = _makeReq("8453", 17, 2);

        vm.startPrank(ueaUser);
        registry.batchBind(reqs);

        registry.unbind("eip155", "1", ERC8004);
        registry.unbind("eip155", "8453", ERC8004);

        assertEq(registry.getBindings(ueaAgentId).length, 0);

        ITAPRegistry.BindRequest[] memory reqs2 = new ITAPRegistry.BindRequest[](2);
        reqs2[0] = _makeReq("1", 42, 3);
        reqs2[1] = _makeReq("8453", 17, 4);
        registry.batchBind(reqs2);

        vm.stopPrank();

        assertEq(registry.getBindings(ueaAgentId).length, 2);
    }

    // ──────────────────────────────────────────────
    //  Gas comparison
    // ──────────────────────────────────────────────

    function test_BatchBind_GasVsIndividual() public {
        (address user2, uint256 user2Key) = makeAddrAndKey("gasUser2");
        factory.addUEA(
            user2,
            UniversalAccountId({
                chainNamespace: "eip155", chainId: "1", owner: abi.encodePacked(user2)
            })
        );
        vm.prank(user2);
        registry.register(AGENT_URI, CARD_HASH);

        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(ueaUser);
        uint256 gasIndividualStart = gasleft();
        for (uint256 i; i < 5; i++) {
            string memory chainId = vm.toString(i + 600);
            registry.bind(
                ITAPRegistry.BindRequest({
                    chainNamespace: "eip155",
                    chainId: chainId,
                    registryAddress: ERC8004,
                    boundAgentId: i + 700,
                    proofType: ITAPRegistry.BindProofType.OWNER_KEY_SIGNED,
                    proofData: _signBind(
                        ueaUserKey, ueaUser, "eip155", chainId, ERC8004, i + 700, i + 400, deadline
                    ),
                    nonce: i + 400,
                    deadline: deadline
                })
            );
        }
        uint256 gasIndividual = gasIndividualStart - gasleft();
        vm.stopPrank();

        ITAPRegistry.BindRequest[] memory reqs = new ITAPRegistry.BindRequest[](5);
        for (uint256 i; i < 5; i++) {
            string memory chainId = vm.toString(i + 800);
            reqs[i] = ITAPRegistry.BindRequest({
                chainNamespace: "eip155",
                chainId: chainId,
                registryAddress: ERC8004,
                boundAgentId: i + 900,
                proofType: ITAPRegistry.BindProofType.OWNER_KEY_SIGNED,
                proofData: _signBind(
                    user2Key, user2, "eip155", chainId, ERC8004, i + 900, i + 400, deadline
                ),
                nonce: i + 400,
                deadline: deadline
            });
        }

        vm.prank(user2);
        uint256 gasBatchStart = gasleft();
        registry.batchBind(reqs);
        uint256 gasBatch = gasBatchStart - gasleft();

        assertLt(gasBatch, gasIndividual);
    }
}
