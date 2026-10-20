// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {GoatPro} from "../src/GoatPro.sol";

/// @dev Local deployment fixture only; not a production launch factory or pool implementation.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (GoatPro) {
        return new GoatPro{salt: salt}();
    }

    function distribute(GoatPro token, address distributor, address pool, address remainder) external {
        uint256 supply = token.totalSupply();
        require(token.transfer(distributor, supply / 10));
        require(token.transfer(pool, supply / 2));
        require(token.transfer(remainder, supply * 4 / 10));
    }
}

contract LaunchFlowTest is Test {
    function test_Create2DeploymentAndExactLaunchTransfers() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        bytes32 salt = keccak256("local launch test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(GoatPro).creationCode))
                    )
                )
            )
        );

        GoatPro token = factory.deploy(salt);
        uint256 supply = 1_000_000_000 ether;
        assertEq(address(token), predicted);
        assertEq(token.totalSupply(), supply);
        assertEq(token.balanceOf(address(factory)), supply);
        assertEq(token.balanceOf(address(this)), 0);

        // Local actors stand for each launch role; none is a configured chain address.
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool");
        address remainder = makeAddr("remainder");
        address claimant = makeAddr("claimant");
        address trader = makeAddr("trader");
        factory.distribute(token, distributor, pool, remainder);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), supply / 10);
        assertEq(token.balanceOf(pool), supply / 2);
        assertEq(token.balanceOf(remainder), supply * 4 / 10);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, supply / 10));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), supply / 10);

        // Verify exact token movements in both directions, without simulating AMM pricing.
        vm.prank(pool);
        assertTrue(token.transfer(trader, 123 ether));
        assertEq(token.balanceOf(trader), 123 ether);
        assertEq(token.balanceOf(pool), supply / 2 - 123 ether);
        vm.prank(trader);
        assertTrue(token.transfer(pool, 123 ether));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(pool), supply / 2);
        assertEq(token.totalSupply(), supply);
    }
}
