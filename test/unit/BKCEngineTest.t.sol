// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployBKC} from "../../script/DeployBKC.s.sol";
import {BKCoin} from "../../src/BKCoin.sol";
import {BKEngine} from "../../src/BKEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import { MockMoreDebtBKC } from "../mocks/MockMoreDebtBKC.sol";
import { MockFailedMintBKC } from "../mocks/MockFailedMintBKC.sol";
import { MockFailedTransferFrom } from "../mocks/MockFailedTransferFrom.sol";
import { MockFailedTransfer } from "../mocks/MockFailedTransfer.sol";
import { Test, console } from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

contract BKEngineTest is StdCheats, Test {
    event CollateralRetrieved(address indexed RetrieveFrom, address indexed RetrieveTo, address token, uint256 amount); 
    // if RetrieveFrom != RetrieveedTo, then it was liquidated

    BKCoin public bkc;
    BKEngine public bkce;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public weth;

    address public btcUsdPriceFeed;
    address public wbtc;

    uint256 public deployerKey;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    address public user = address(1);
    

    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;
    
    function setUp() public {
        DeployBKC _deployer = new DeployBKC();
        (bkc, bkce, helperConfig) = _deployer.run();

        if (block.chainid == 31_337) {
            vm.deal(user, STARTING_ERC20_BALANCE);
        } 
        // Should we put our integration tests here?
        // else {
        //     user = vm.addr(deployerKey);
        //     ERC20Mock mockErc = new ERC20Mock("MOCK", "MOCK", user, 100e18);
        //     MockV3Aggregator aggregatorMock = new MockV3Aggregator(
        //         helperConfig.DECIMALS(),
        //         helperConfig.ETH_USD_PRICE()
        //     );
        //     vm.etch(weth, address(mockErc).code);
        //     vm.etch(wbtc, address(mockErc).code);
        //     vm.etch(ethUsdPriceFeed, address(aggregatorMock).code);
        //     vm.etch(btcUsdPriceFeed, address(aggregatorMock).code);
        // }

        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_ERC20_BALANCE);
    }
      ///////////////////////
     // Constructor Tests // STATUS: PASS
    ///////////////////////

    address[] public tokenAddress;
    address[] public priceFeedAddress;

    function testRevertsIFTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddress.push(weth);
        priceFeedAddress.push(ethUsdPriceFeed);
        priceFeedAddress.push(btcUsdPriceFeed);
        
        vm.expectRevert(BKEngine.BKEngine__TokenAddressAndPriceFeedAddressMustBeSameLength.selector);
        new BKEngine(tokenAddress, priceFeedAddress, address(bkc));
    }



      ////////////////////
     /// Price tests //// STATUS: PASS
    ////////////////////

    function testGetUsdValue() public{
        uint256 ethAmount = 15e18;
        // Since we set ETH price to be at 2000/ETH => 15e18* 2000 = 30000e18 = 3e22;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = bkce.getUsdValue(weth,ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        // If we want $100 of WETH @ $2000/WETH, that would be 0.05 WETH
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = bkce.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(expectedWeth, actualWeth);
    }


      /////////////////////////////////
     /// deposit Collateral tests ////
    /////////////////////////////////

    // this test needs it's own setup
    function testRevertsIfTransferFromFails() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockBkc = new MockFailedTransferFrom();
        tokenAddress = [address(mockBkc)];
        priceFeedAddress = [ethUsdPriceFeed];
        vm.prank(owner);
        BKEngine mockBkce = new BKEngine(tokenAddress, priceFeedAddress, address(mockBkc));
        mockBkc.mint(user, amountCollateral);

        vm.prank(owner);
        mockBkc.transferOwnership(address(mockBkce));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(address(mockBkc)).approve(address(mockBkce), amountCollateral);
        // Act / Assert
        vm.expectRevert(BKEngine.BKEngine__TransferFailed.selector);
        mockBkce.depositCollateral(address(mockBkc), amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfCollateralZero() public{
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(bkce), amountCollateral);

        vm.expectRevert(BKEngine.BKEngine__NonPostiveRejected.selector);
        bkce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    // function testRevertWithUnapprovedCollateral() public {
    //     ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", user, amountCollateral);
    //     vm.startPrank(user);
    //     vm.expectRevert(BKEngine.BKEngine__NotAllowedToken.selector);
    //     bkce.depositCollateral(address(ranToken), amountCollateral);
    //     vm.stopPrank();
    // }
    
    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(bkce), amountCollateral);
        bkce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = bkc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral{
        (uint256 totalBkcMinted, uint256 collateralValueInUsd) = bkce.getAccountInformation(user);

        uint256 expectedTotalBkcMinted = 0;
        uint256 expectedDepositTotal = bkce.getTokenAmountFromUsd(weth, collateralValueInUsd);
    
        assertEq(totalBkcMinted, expectedTotalBkcMinted);
        assertEq(amountCollateral, expectedDepositTotal);
    }



      ///////////////////////////////////////
     // depositCollateralAndMintBKC Tests //
    ///////////////////////////////////////

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (amountCollateral * (uint256(price) * bkce.getAdditionalFeedPrecision())) / bkce.getPrecision();
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(bkce), amountCollateral);

        uint256 expectedHealthFactor =
            bkce.calculateHealthFactor(amountToMint, bkce.getUsdValue(weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(BKEngine.BKEngine__WeakHealthFactor.selector, expectedHealthFactor));
        bkce.depositCollateralAndMintBKC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedBkc() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(bkce), amountCollateral);
        bkce.depositCollateralAndMintBKC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedBkc {
        uint256 userBalance = bkc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }



      ///////////////////
     // mintDsc Tests //
    ///////////////////


    // This test needs it's own custom setup
    function testRevertsIfMintFails() public {
        // Arrange - Setup
        MockFailedMintBKC mockBkc = new MockFailedMintBKC();
        tokenAddress = [weth];
        priceFeedAddress = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        BKEngine mockBkce = new BKEngine(tokenAddress, priceFeedAddress, address(mockBkc));
        mockBkc.transferOwnership(address(mockBkce));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockBkce), amountCollateral);

        vm.expectRevert(BKEngine.BKEngine__MintFailed.selector);
        mockBkce.depositCollateralAndMintBKC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(bkce), amountCollateral);
        bkce.depositCollateralAndMintBKC(weth, amountCollateral, amountToMint);
        vm.expectRevert(BKEngine.BKEngine__NonPostiveRejected.selector);
        bkce.mintBKC(0);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositedCollateral {
        // 0xe580cc6100000000000000000000000000000000000000000000000006f05b59d3b20000
        // 0xe580cc6100000000000000000000000000000000000000000000003635c9adc5dea00000
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (amountCollateral * (uint256(price) * bkce.getAdditionalFeedPrecision())) / bkce.getPrecision();

        vm.startPrank(user);
        uint256 expectedHealthFactor =
            bkce.calculateHealthFactor(amountToMint, bkce.getUsdValue(weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(BKEngine.BKEngine__WeakHealthFactor.selector, expectedHealthFactor));
        bkce.mintBKC(amountToMint);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral {
        vm.prank(user);
        bkce.mintBKC(amountToMint);

        uint256 userBalance = bkc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }



      ///////////////////
     // burnBKC Tests //
    ///////////////////

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(bkce), amountCollateral);
        bkce.depositCollateralAndMintBKC(weth, amountCollateral, amountToMint);
        vm.expectRevert(BKEngine.BKEngine__NonPostiveRejected.selector);
        bkce.burnBKC(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.prank(user);
        vm.expectRevert();
        bkce.burnBKC(1);
    }

    function testCanBurnBkc() public depositedCollateralAndMintedBkc {
        vm.startPrank(user);
        bkc.approve(address(bkce), amountToMint);
        bkce.burnBKC(amountToMint);
        vm.stopPrank();

        uint256 userBalance = bkc.balanceOf(user);
        assertEq(userBalance, 0);
    }



    ///////////////////////////////////
    // retrieveCollateral Tests //
    //////////////////////////////////

    // this test needs it's own setup
    function testRevertsIfTransferFails() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockBkc = new MockFailedTransfer();
        tokenAddress = [address(mockBkc)];
        priceFeedAddress = [ethUsdPriceFeed];
        vm.prank(owner);
        BKEngine mockBkce = new BKEngine(tokenAddress, priceFeedAddress, address(mockBkc));
        mockBkc.mint(user, amountCollateral);

        vm.prank(owner);
        mockBkc.transferOwnership(address(mockBkce));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(address(mockBkc)).approve(address(mockBkce), amountCollateral);
        // Act / Assert
        mockBkce.depositCollateral(address(mockBkc), amountCollateral);
        vm.expectRevert(BKEngine.BKEngine__TransferFailed.selector);
        mockBkce.retrieveCollateral(address(mockBkc), amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfRetrieveAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(bkce), amountCollateral);
        bkce.depositCollateralAndMintBKC(weth, amountCollateral, amountToMint);
        vm.expectRevert(BKEngine.BKEngine__NonPostiveRejected.selector);
        bkce.retrieveCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanRetrieveCollateral() public depositedCollateral {
        vm.startPrank(user);
        bkce.retrieveCollateral(weth, amountCollateral);
        uint256 userBalance = ERC20Mock(weth).balanceOf(user);
        assertEq(userBalance, amountCollateral);
        vm.stopPrank();
    }

    // function testEmitCollateralRetrievedWithCorrectArgs() public depositedCollateral {
    //     vm.expectEmit(true, true, true, true, address(bkce));
    //     emit CollateralRetrieved(user, user, weth, amountCollateral);
    //     vm.startPrank(user);
    //     bkce.retrieveCollateral(weth, amountCollateral);
    //     vm.stopPrank();
    // }



      ////////////////////////////////////
     // retrieveCollateralForBKC Tests //
    ////////////////////////////////////

    function testMustRetrieveMoreThanZero() public depositedCollateralAndMintedBkc {
        vm.startPrank(user);
        bkc.approve(address(bkce), amountToMint);
        vm.expectRevert(BKEngine.BKEngine__NonPostiveRejected.selector);
        bkce.retrieveCollateralForBKC(weth, 0, amountToMint);
        vm.stopPrank();
    }

    function testCanRetrieveDepositedCollateral() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(bkce), amountCollateral);
        bkce.depositCollateralAndMintBKC(weth, amountCollateral, amountToMint);
        bkc.approve(address(bkce), amountToMint);
        bkce.retrieveCollateralForBKC(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        uint256 userBalance = bkc.balanceOf(user);
        assertEq(userBalance, 0);
    }



    ////////////////////////
    // healthFactor Tests //
    ////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedBkc {
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = bkce.getHealthFactor(user);
        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collatareral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 100 = 100 health factor
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedBkc {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        // Rememeber, we need $200 at all times if we have $100 of debt

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = bkce.getHealthFactor(user);
        // 180*50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION) = 90 / 100 (totalDscMinted) =
        // 0.9
        assert(userHealthFactor == 0.9 ether);
    }



    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    // This test needs it's own setup
    // function testMustImproveHealthFactorOnLiquidation() public {
    //     // Arrange - Setup
    //     MockMoreDebtBKC mockBkc = new MockMoreDebtBKC(ethUsdPriceFeed);
    //     tokenAddress = [weth];
    //     priceFeedAddress = [ethUsdPriceFeed];
    //     address owner = msg.sender;
    //     vm.prank(owner);
    //     BKEngine mockBkce = new BKEngine(tokenAddress, priceFeedAddress, address(mockBkc));
    //     mockBkc.transferOwnership(address(mockBkce));
    //     // Arrange - User
    //     vm.startPrank(user);
    //     ERC20Mock(weth).approve(address(mockBkce), amountCollateral);
    //     mockBkce.depositCollateralAndMintBKC(weth, amountCollateral, amountToMint);
    //     vm.stopPrank();

    //     // Arrange - Liquidator
    //     collateralToCover = 1 ether;
    //     ERC20Mock(weth).mint(liquidator, collateralToCover);

    //     vm.startPrank(liquidator);
    //     ERC20Mock(weth).approve(address(mockBkce), collateralToCover);
    //     uint256 debtToCover = 10 ether;
    //     mockBkce.depositCollateralAndMintBKC(weth, collateralToCover, amountToMint);
    //     mockBkc.approve(address(mockBkce), debtToCover);
    //     // Act
    //     int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
    //     MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
    //     // Act/Assert
    //     vm.expectRevert(BKEngine.BKEngine__HealthFactorNotImproved.selector);
    //     mockBkce.liquidate( user, weth, debtToCover);
    //     vm.stopPrank();
    // }

    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedBkc {
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(bkce), collateralToCover);
        bkce.depositCollateralAndMintBKC(weth, collateralToCover, amountToMint);
        bkc.approve(address(bkce), amountToMint);

        vm.expectRevert(BKEngine.BKEngine__GoodHealthFactor.selector);
        bkce.liquidate( user, weth, amountToMint);
        vm.stopPrank();
    }

    modifier liquidated() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(bkce), amountCollateral);
        bkce.depositCollateralAndMintBKC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = bkce.getHealthFactor(user);

        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(bkce), collateralToCover);
        bkce.depositCollateralAndMintBKC(weth, collateralToCover, amountToMint);
        bkc.approve(address(bkce), amountToMint);
        bkce.liquidate(user, weth, amountToMint); // We are covering their whole debt
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        uint256 expectedWeth = bkce.getTokenAmountFromUsd(weth, amountToMint)
            + (bkce.getTokenAmountFromUsd(weth, amountToMint) / bkce.getLiquidationBonus());
        uint256 hardCodedExpected = 6_111_111_111_111_111_110;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Get how much WETH the user lost
        uint256 amountLiquidated = bkce.getTokenAmountFromUsd(weth, amountToMint)
            + (bkce.getTokenAmountFromUsd(weth, amountToMint) / bkce.getLiquidationBonus());

        uint256 usdAmountLiquidated = bkce.getUsdValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = bkce.getUsdValue(weth, amountCollateral) - (usdAmountLiquidated);

        (, uint256 userCollateralValueInUsd) = bkce.getAccountInformation(user);
        uint256 hardCodedExpectedValue = 70_000_000_000_000_000_020;
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = bkce.getAccountInformation(liquidator);
        assertEq(liquidatorDscMinted, amountToMint);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 totalBkcMinted,) = bkce.getAccountInformation(user);
        assertEq(totalBkcMinted, 0);
    }




    ///////////////////////////////////
    // View & Pure Function Tests //
    //////////////////////////////////
    function testGetCollateralTokenPriceFeed() public view{
        address priceFeed = bkce.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUsdPriceFeed);
    }

    function testGetCollateralTokens() public view{
        address[] memory collateralTokens = bkce.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetMinHealthFactor() public view{
        uint256 minHealthFactor = bkce.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public view{
        uint256 liquidationThreshold = bkce.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation() public depositedCollateral {
        (, uint256 collateralValue) = bkce.getAccountInformation(user);
        uint256 expectedCollateralValue = bkce.getUsdValue(weth, amountCollateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(bkce), amountCollateral);
        bkce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        uint256 collateralBalance = bkce.getCollateralBalanceOfUser(user, weth);
        assertEq(collateralBalance, amountCollateral);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(bkce), amountCollateral);
        bkce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        uint256 collateralValue = bkce.getAccountCollateralValue(user);
        uint256 expectedCollateralValue = bkce.getUsdValue(weth, amountCollateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetDsc() public view{
        address bkcAddress = bkce.getDsc();
        assertEq(bkcAddress, address(bkc));
    }

    function testLiquidationPrecision() public {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = bkce.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }

    // How do we adjust our invariant tests for this?
    // function testInvariantBreaks() public depositedCollateralAndMintedDsc {
    //     MockV3Aggregator(ethUsdPriceFeed).updateAnswer(0);

    //     uint256 totalSupply = bkc.totalSupply();
    //     uint256 wethDeposted = ERC20Mock(weth).balanceOf(address(bkce));
    //     uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(bkce));

    //     uint256 wethValue = bkce.getUsdValue(weth, wethDeposted);
    //     uint256 wbtcValue = bkce.getUsdValue(wbtc, wbtcDeposited);

    //     console.log("wethValue: %s", wethValue);
    //     console.log("wbtcValue: %s", wbtcValue);
    //     console.log("totalSupply: %s", totalSupply);

    //     assert(wethValue + wbtcValue >= totalSupply);
    // }


}

