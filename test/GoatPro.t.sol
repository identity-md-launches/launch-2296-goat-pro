// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {GoatPro} from "../src/GoatPro.sol";

/// forge-config: default.fuzz.runs = 1000
contract GoatProTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    GoatPro internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new GoatPro();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "Goat Pro");
        assertEq(token.symbol(), "GPRO");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsMint() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        new GoatPro();
    }

    function test_ConstructorUsesImmediateDeployerInsteadOfTransactionOrigin() public {
        vm.prank(alice, bob);
        GoatPro deployed = new GoatPro();
        assertEq(deployed.balanceOf(alice), SUPPLY);
        assertEq(deployed.balanceOf(bob), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_TransferReturnsTrueAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 125 ether);
        assertTrue(token.transfer(alice, 125 ether));
        assertEq(token.balanceOf(alice), 125 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 125 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireSupply() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferZeroFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToSelfPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToContractRequiresNoReceiverCallback() public {
        NoTokenReceiver receiver = new NoTokenReceiver();
        assertTrue(token.transfer(address(receiver), 7 ether));
        assertEq(token.balanceOf(address(receiver)), 7 ether);
    }

    function test_RevertTransferToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertZeroTransferToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_RevertTransferExceedingBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertTransferMaximumUint() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApproveReturnsTrueAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 25 ether);
        assertTrue(token.approve(spender, 25 ether));
        assertEq(token.allowance(address(this), spender), 25 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_ApproveReplacesAllowanceAndCanRevoke() public {
        assertTrue(token.approve(spender, 25 ether));
        assertTrue(token.approve(spender, 10 ether));
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
    }

    function test_ApproveDoesNotRequireBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertApproveZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromSpendsFiniteAllowanceAndEmitsTransfer() public {
        token.approve(spender, 100 ether);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 40 ether));

        assertEq(token.allowance(address(this), spender), 60 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 40 ether);
        assertEq(token.balanceOf(alice), 40 ether);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromCanExhaustAllowance() public {
        token.approve(spender, 100 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 100 ether));
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 100 ether);
    }

    function test_TransferFromPreservesInfiniteAllowance() public {
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 40 ether));
        assertTrue(token.transferFrom(address(this), bob, 60 ether));
        vm.stopPrank();

        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 40 ether);
        assertEq(token.balanceOf(bob), 60 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100 ether);
    }

    function test_TransferFromZeroAmountRequiresNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromToSelfSpendsAllowanceWithoutChangingBalance() public {
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 4 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 6 ether);
    }

    function test_RevertTransferFromWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertTransferFromByUnapprovedCaller() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 10 ether);
    }

    function test_RevertTransferFromOwnAccountWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
    }

    function test_RevertTransferFromInsufficientBalancePreservesAllowance() public {
        token.transfer(alice, 10 ether);
        vm.prank(alice);
        token.approve(spender, 20 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 11 ether)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 11 ether);

        assertEq(token.allowance(alice, spender), 20 ether);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertTransferFromToZeroPreservesAllowance() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 4 ether);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DeployerAndStrangerCannotMintBurnFreezeOrUpgrade() public {
        token.transfer(alice, 100 ether);
        bytes[] memory calls = new bytes[](20);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", 1 ether);
        calls[4] = abi.encodeWithSignature("initialize(address)", bob);
        calls[5] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[6] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[7] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);
        calls[8] = abi.encodeWithSignature("pause()");
        calls[9] = abi.encodeWithSignature("unpause()");
        calls[10] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[11] = abi.encodeWithSignature("freeze(address)", alice);
        calls[12] = abi.encodeWithSignature("seize(address)", alice);
        calls[13] = abi.encodeWithSignature("setBlacklist(address,bool)", alice, true);
        calls[14] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[15] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[16] = abi.encodeWithSignature("setOwner(address)", bob);
        calls[17] = abi.encodeWithSignature("owner()");
        calls[18] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[19] = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", bob, bytes(""));

        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded, "unexpected deployer privilege");
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded, "unexpected stranger privilege");
        }

        // Deployment grants no right to spend another holder's tokens.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);

        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function test_RuntimeContainsNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff, "forbidden runtime opcode");
        }
    }

    function testFuzz_TransferConservesSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromSpendsOnlyApprovedAmount(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY);
        amount = bound(amount, 0, approved);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevertInsufficientAllowanceIsAtomic(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_RevertInsufficientBalanceIsAtomic(uint256 balance, uint256 amount) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max);
        token.transfer(alice, balance);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(alice);
        token.transfer(bob, amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApproveOverwritesOnlyCallersAllowance(uint256 first, uint256 second) public {
        token.approve(spender, first);
        vm.prank(alice);
        token.approve(spender, second);
        assertEq(token.allowance(address(this), spender), first);
        assertEq(token.allowance(alice, spender), second);
        token.approve(spender, second);
        assertEq(token.allowance(address(this), spender), second);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferToAnyNonzeroRecipient(address recipient, uint256 amount) public {
        recipient = address(uint160(bound(uint256(uint160(recipient)), 1, type(uint160).max)));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        if (recipient == address(this)) {
            assertEq(token.balanceOf(address(this)), SUPPLY);
        } else {
            assertEq(token.balanceOf(recipient), amount);
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }
}

/// @dev Test-only recipient that cannot accept calls, demonstrating ordinary ERC-20 transfers.
contract NoTokenReceiver {
    fallback() external {
        revert("no callbacks");
    }
}
