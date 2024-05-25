// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployBKC} from "../../script/DeployBKC.s.sol";
import {BKCoin} from "../../src/BKCoin.sol";
import {BKEngine} from "../../src/BKEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";


contract BKEngineTest is Test {
    DeployBKC _deployer;
    BKCoin _bkc;
    BKEngine _bkce;
    HelperConfig _config;

    address _ethUsdPriceFeed;
    address _weth;

    address _btcUsdPriceFeed;
    address _wbtc;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;
    
    function setUp() public {
        _deployer = new DeployBKC();
        (_bkc, _bkce, _config) = _deployer.run();

        (_ethUsdPriceFeed,,_weth,,) = _config.activeNetworkConfig();

        ERC20Mock(_weth).mint(USER, STARTING_ERC20_BALANCE);
    }



      ///////////////////////////
     /// Price feed tests /////
    /////////////////////////

    address[] public tokenAddress;
    address[] public priceFeedAddress;

    function testRevertsIFTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddress.push(_weth);
        priceFeedAddress.push(_ethUsdPriceFeed);
        priceFeedAddress.push(_btcUsdPriceFeed);
        
        vm.expectRevert(BKEngine.BKEngine__TokenAddressAndPriceFeedAddressMustBeSameLength.selector);
        new BKEngine(tokenAddress, priceFeedAddress, address(_bkc));
    }

      /////////////////////////
     /// Price feed tests ////
    /////////////////////////

    function testGetUsdValue() public{
        uint256 ethAmount = 15e18;
        // Since we set ETH price to be at 2000/ETH => 15e18* 2000 = 30000e18 = 3e22;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = _bkce.getUsdValue(_weth,ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testgetTokenAmountFromUsd() public {
        
    }


      /////////////////////////////////
     /// deposit Collateral tests ////
    /////////////////////////////////

    function testRevertsIfCollateralZero() public{
        vm.startPrank(USER);
        ERC20Mock(_weth).approve(address(_bkce), AMOUNT_COLLATERAL);

        vm.expectRevert(BKEngine.BKEngine__NonPostiveRejected.selector);
        _bkce.depositCollateral(_weth, 0);
        vm.stopPrank();
    }
}

