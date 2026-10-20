// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {GoatPro} from "../src/GoatPro.sol";

/// @dev A closed set of holders lets the invariant sum every reachable balance.
/// Receipts and payments are recorded from successful call inputs, never from the
/// token's resulting balances. Failed calls must leave this history unchanged.
contract GoatProHandler is Test {
    GoatPro public immutable token;
    address[4] public actors;
    mapping(address => uint256) public received;
    mapping(address => uint256) public sent;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(GoatPro token_) {
        token = token_;
        actors[0] = makeAddr("holder0");
        actors[1] = makeAddr("holder1");
        actors[2] = makeAddr("holder2");
        actors[3] = makeAddr("holder3");
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBalance = token.balanceOf(from);
        uint256 toBalance = token.balanceOf(to);
        amount = bound(amount, 0, fromBalance);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? fromBalance : fromBalance - amount);
        assertEq(token.balanceOf(to), from == to ? toBalance : toBalance + amount);
        _recordTransfer(from, to, amount);
    }

    function transferFullBalance(uint256 fromSeed, uint256 toSeed) external {
        transfer(fromSeed, toSeed, token.balanceOf(actors[fromSeed % actors.length]));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    /// @dev Make revocation and transitions between finite/infinite approval common.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint8 mode) external {
        uint256[4] memory amounts = [uint256(0), 1, type(uint256).max - 1, type(uint256).max];
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], amounts[mode % 4]);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 fromBalance = token.balanceOf(owner);
        uint256 toBalance = token.balanceOf(to);
        amount = bound(amount, 0, allowance < fromBalance ? allowance : fromBalance);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(token.balanceOf(owner), owner == to ? fromBalance : fromBalance - amount);
        assertEq(token.balanceOf(to), owner == to ? toBalance : toBalance + amount);
        assertEq(token.allowance(owner, spender), allowance == type(uint256).max ? allowance : allowance - amount);
        if (allowance != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
        _recordTransfer(owner, to, amount);
    }

    function rejectTransferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = token.balanceOf(from);
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function rejectTransferFromAboveBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = token.balanceOf(owner);
        amount = bound(amount, balance + 1, type(uint256).max);
        // The allowance check succeeds, so a revert must roll its consumption back.
        _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function rejectTransferFromAboveAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 approval)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        approval = bound(approval, 0, token.balanceOf(owner));
        _approve(owner, spender, approval);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, approval + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, approval + 1);
    }

    function rejectZeroReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 limit = token.balanceOf(owner);
        if (delegated && expectedAllowance[owner][spender] < limit) {
            limit = expectedAllowance[owner][spender];
        }
        amount = bound(amount, 0, limit);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : owner);
        if (delegated) {
            token.transferFrom(owner, address(0), amount);
        } else {
            token.transfer(address(0), amount);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(actors[ownerSeed % actors.length]);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) internal {
        sent[from] += amount;
        received[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract GoatProInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    GoatPro internal token;
    GoatProHandler internal handler;

    function setUp() public {
        token = new GoatPro();
        handler = new GoatProHandler(token);
        for (uint256 i; i < 4; ++i) {
            token.transfer(handler.actors(i), SUPPLY / 4);
        }

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = GoatProHandler.transfer.selector;
        selectors[1] = GoatProHandler.approve.selector;
        selectors[2] = GoatProHandler.transferFrom.selector;
        selectors[3] = GoatProHandler.transferFullBalance.selector;
        selectors[4] = GoatProHandler.approveBoundary.selector;
        selectors[5] = GoatProHandler.rejectTransferAboveBalance.selector;
        selectors[6] = GoatProHandler.rejectTransferFromAboveBalance.selector;
        selectors[7] = GoatProHandler.rejectTransferFromAboveAllowance.selector;
        selectors[8] = GoatProHandler.rejectZeroReceiver.selector;
        selectors[9] = GoatProHandler.rejectZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_TotalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_AllTokensRemainAccountedFor() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    /// @dev Conservation alone misses a transfer to the wrong holder. Every holder
    /// must retain its initial allocation plus receipts, less authorized payments.
    function invariant_EachHolderMatchesItsTransferHistory() public view {
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(
                token.balanceOf(actor) + handler.sent(actor),
                SUPPLY / 4 + handler.received(actor),
                "holder balance diverged from authorized transfers"
            );
        }
    }

    /// @dev Checks all pairs, including uninvolved holders/spenders and self-approval.
    /// Failed delegated transfers cannot consume allowance, even after a long history.
    function invariant_AllowancesMatchApprovalAndSpendingHistory() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    /// @dev Deterministically exercises every handler before relying on random
    /// selection, including nonzero delegated spending, failure, and recovery.
    function test_HandlerExercisesFailureAndRecoverySequence() public {
        handler.approveBoundary(0, 1, 3);
        handler.transferFrom(0, 1, 2, 1);
        handler.approveBoundary(0, 1, 2);
        handler.transferFrom(0, 1, 0, 1);
        handler.approveBoundary(0, 1, 0);
        handler.rejectTransferFromAboveAllowance(0, 1, 2, 0);
        handler.rejectTransferAboveBalance(0, 2, type(uint256).max);
        handler.rejectTransferFromAboveBalance(0, 1, 2, type(uint256).max);
        handler.rejectZeroReceiver(0, 1, 1, true);
        handler.rejectZeroReceiver(0, 1, 0, false);
        handler.rejectZeroSpender(0, type(uint256).max);
        handler.approve(0, 1, 7);
        handler.transferFrom(0, 1, 2, 7);
        handler.transferFullBalance(2, 3);
        handler.transfer(3, 0, 1);

        invariant_TotalSupplyNeverChanges();
        invariant_AllTokensRemainAccountedFor();
        invariant_EachHolderMatchesItsTransferHistory();
        invariant_AllowancesMatchApprovalAndSpendingHistory();
    }
}
