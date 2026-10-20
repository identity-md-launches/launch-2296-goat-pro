// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {GoatPro} from "../src/GoatPro.sol";

/// @dev A closed set of holders lets the invariant sum every reachable balance.
/// Each action also checks exact deltas and allowances, including self-transfers.
contract GoatProHandler is Test {
    GoatPro public immutable token;
    address[4] public actors;

    constructor(GoatPro token_) {
        token = token_;
        actors[0] = makeAddr("holder0");
        actors[1] = makeAddr("holder1");
        actors[2] = makeAddr("holder2");
        actors[3] = makeAddr("holder3");
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBalance = token.balanceOf(from);
        uint256 toBalance = token.balanceOf(to);
        amount = bound(amount, 0, fromBalance);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? fromBalance : fromBalance - amount);
        assertEq(token.balanceOf(to), from == to ? toBalance : toBalance + amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowance = token.allowance(owner, spender);
        uint256 fromBalance = token.balanceOf(owner);
        uint256 toBalance = token.balanceOf(to);
        amount = bound(amount, 0, allowance < fromBalance ? allowance : fromBalance);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(token.balanceOf(owner), owner == to ? fromBalance : fromBalance - amount);
        assertEq(token.balanceOf(to), owner == to ? toBalance : toBalance + amount);
        assertEq(token.allowance(owner, spender), allowance == type(uint256).max ? allowance : allowance - amount);
    }
}

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

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = GoatProHandler.transfer.selector;
        selectors[1] = GoatProHandler.approve.selector;
        selectors[2] = GoatProHandler.transferFrom.selector;
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
}
