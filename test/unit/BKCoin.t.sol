// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { BKCoin } from "../../src/BKCoin.sol";
import { Test, console } from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

contract DecentralizedStablecoinTest is StdCheats, Test {
    BKCoin bkc;

    function setUp() public {
        bkc = new BKCoin();
    }

    function testMustMintMoreThanZero() public {
        vm.prank(bkc.owner());
        vm.expectRevert();
        bkc.mint(address(this), 0);
    }

    function testMustBurnMoreThanZero() public {
        vm.startPrank(bkc.owner());
        bkc.mint(address(this), 100);
        vm.expectRevert();
        bkc.burn(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanYouHave() public {
        vm.startPrank(bkc.owner());
        bkc.mint(address(this), 100);
        vm.expectRevert();
        bkc.burn(101);
        vm.stopPrank();
    }

    function testCantMintToZeroAddress() public {
        vm.startPrank(bkc.owner());
        vm.expectRevert();
        bkc.mint(address(0), 100);
        vm.stopPrank();
    }
}
