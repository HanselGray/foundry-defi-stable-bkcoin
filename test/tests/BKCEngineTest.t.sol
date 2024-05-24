// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployBKC} from "../../script/DeployBKC.s.sol";
import {BKCoin} from "../../src/BKCoin.sol";
import {BKEngine} from "../../src/BKEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";


contract BKEngineTest is Test {
    DeployBKC deployer;
    BKCoin bkc;
    BKEngine bkce;
    HelperConfig config;

    address ethUsdPriceFeed;
    address weth;

    address btcUsdPriceFeed;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;
    
    function setUp() public {
        deployer = new DeployBKC();
        (bkc, bkce, config) = deployer.run();

        (ethUsdPriceFeed,,weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////////
    /// Price feed tests /////
    /////////////////////////
    function testGetUsdValue() public{
        uint256 ethAmount = 15e18;
        // Since we set ETH price to be at 2000/ETH => 15e18* 2000 = 30000e18 = 3e22;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = bkce.getUsdValue(weth,ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

      /////////////////////////////////
     /// deposit Collateral tests ////
    /////////////////////////////////


    function testRevertsIfCollateralZero() public{
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(bkce), AMOUNT_COLLATERAL);

        vm.expectRevert(BKEngine.BKEngine__NonPostiveRejected.selector);
        bkce.depositCollateral(weth, 0);
        vm.stopPrank();
    }
}