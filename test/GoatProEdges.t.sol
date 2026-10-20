// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {GoatPro} from "../src/GoatPro.sol";

/// @dev Complements the core tests with allowance transitions, account aliases,
/// rollback followed by recovery, and exact round trips at the supply boundaries.
/// forge-config: default.fuzz.runs = 1000
contract GoatProEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    GoatPro internal token;
    address internal holder;
    address internal recipient;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new GoatPro();
        holder = makeAddr("edge holder");
        recipient = makeAddr("edge recipient");
        spender = makeAddr("edge spender");
    }

    function test_MaximumFiniteAllowanceIsConsumed() public {
        uint256 approval = type(uint256).max - 1;
        assertTrue(token.approve(spender, approval));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), approval - 1);
        assertEq(token.balanceOf(recipient), 1);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approval - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteApprovalCanBeRevokedAndReplacedWithFiniteApproval() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);

        token.approve(spender, 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 2));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.balanceOf(recipient), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
    }

    function test_SelfApprovalIsConsumedEvenWhenAllRolesAreTheSameAccount() public {
        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), address(this), 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), address(this), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_SelfTransfersCannotBypassBalanceChecks() public {
        bytes memory error =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1);
        vm.expectRevert(error);
        token.transfer(address(this), SUPPLY + 1);

        token.approve(spender, type(uint256).max);
        vm.expectRevert(error);
        vm.prank(spender);
        token.transferFrom(address(this), address(this), SUPPLY + 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteAllowanceDoesNotBypassBalanceChecks() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), recipient, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);

        // A rejected attempt must not poison a subsequent valid transfer.
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_AllowanceBelongsToCallerNotRecipientOrTransactionOrigin() public {
        token.approve(recipient, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender, recipient);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.allowance(address(this), recipient), 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);

        // Once this caller has its own approval, it can itself be the recipient.
        token.approve(spender, 1);
        vm.prank(spender, recipient);
        assertTrue(token.transferFrom(address(this), spender, 1));
        assertEq(token.allowance(address(this), recipient), 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_ApprovalSurvivesEmptyBalanceAndAppliesToFutureReceipts() public {
        vm.prank(holder);
        token.approve(spender, 3);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 3);

        token.transfer(holder, 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 2));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.allowance(holder, spender), 1);

        token.transfer(holder, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(recipient), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
    }

    function test_ZeroAddressCannotBeUsedAsATransferFromSource() public {
        uint256[3] memory amounts = [uint256(0), 1, type(uint256).max];
        for (uint256 i; i < amounts.length; ++i) {
            // Rejection is required whether the allowance or address check runs first.
            vm.expectRevert();
            vm.prank(spender);
            token.transferFrom(address(0), recipient, amounts[i]);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(address(0)), 0);
            assertEq(token.balanceOf(recipient), 0);
            assertEq(token.allowance(address(0), spender), 0);
        }
    }

    function test_OneWeiDelegatedRoundTrip() public {
        _delegatedRoundTrip(1);
    }

    function test_WholeSupplyDelegatedRoundTrip() public {
        _delegatedRoundTrip(SUPPLY);
    }

    function testFuzz_DelegatedRoundTripRestoresBalances(uint256 amount) public {
        _delegatedRoundTrip(bound(amount, 0, SUPPLY));
    }

    function testFuzz_ZeroTransferFromEmptyHolderPreservesApproval(uint256 approval) public {
        vm.prank(holder);
        assertTrue(token.approve(spender, approval));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, recipient, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 0));

        assertEq(token.allowance(holder, spender), approval);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientBalanceRollsBackFiniteAllowanceThenAllowsRetry(
        uint256 balance,
        uint256 amount,
        uint256 approval
    ) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        approval = bound(approval, amount, type(uint256).max - 1);
        token.transfer(holder, balance);
        vm.prank(holder);
        token.approve(spender, approval);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount));
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);
        assertEq(token.allowance(holder, spender), approval);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);

        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, balance));
        assertEq(token.allowance(holder, spender), approval - balance);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InvalidReceiverRollsBackAllowanceThenAllowsRetry(uint256 amount, uint256 approval, bool infinite)
        public
    {
        amount = bound(amount, 0, SUPPLY);
        approval = infinite ? type(uint256).max : bound(approval, amount, type(uint256).max - 1);
        token.approve(spender, approval);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, amount));
        assertEq(token.allowance(address(this), spender), infinite ? approval : approval - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
    }

    function _delegatedRoundTrip(uint256 amount) internal {
        // The returning holder may approve its spender before receiving anything.
        vm.prank(holder);
        assertTrue(token.approve(recipient, amount));
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, amount));
        assertEq(token.balanceOf(holder), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), 0);

        vm.prank(recipient);
        assertTrue(token.transferFrom(holder, address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(holder, recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
