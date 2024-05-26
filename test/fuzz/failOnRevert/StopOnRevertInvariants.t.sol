// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

// Invariants:
// protocol must never be insolvent / undercollateralized
// TODO: users cant create stablecoins with a bad health factor
// TODO: a user should only be able to be liquidated if they have a bad health factor

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { BKEngine } from "../../../src/BKEngine.sol";
import { BKCoin } from "../../../src/BKCoin.sol";
import { HelperConfig } from "../../../script/HelperConfig.s.sol";
import { DeployBKC } from "../../../script/DeployBKC.s.sol";
// import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol"; Updated mock location
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { StopOnRevertHandler } from "./StopOnRevertHandler.t.sol";
import { console } from "forge-std/console.sol";

contract StopOnRevertInvariants is StdInvariant, Test {
    BKEngine public bkce;
    BKCoin public bkc;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    address public constant USER = address(1);
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    StopOnRevertHandler public handler;

    function setUp() external {
        DeployBKC deployer = new DeployBKC();
        (bkc, bkce, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        handler = new StopOnRevertHandler(bkce, bkc);
        targetContract(address(handler));
        // targetContract(address(ethUsdPriceFeed)); Why can't we just do this?
    }

    function invariant_protocolMustHaveMoreValueThatTotalSupplyDollars() public view {
        uint256 totalSupply = bkc.totalSupply();
        uint256 wethDeposted = ERC20Mock(weth).balanceOf(address(bkce));
        uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(bkce));

        uint256 wethValue = bkce.getUsdValue(weth, wethDeposted);
        uint256 wbtcValue = bkce.getUsdValue(wbtc, wbtcDeposited);

        console.log("wethValue: %s", wethValue);
        console.log("wbtcValue: %s", wbtcValue);

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersCantRevert() public view {
        bkce.getAdditionalFeedPrecision();
        bkce.getCollateralTokens();
        bkce.getLiquidationBonus();
        bkce.getLiquidationBonus();
        bkce.getLiquidationThreshold();
        bkce.getMinHealthFactor();
        bkce.getPrecision();
        bkce.getDsc();
        // bkce.getTokenAmountFromUsd();
        // bkce.getCollateralTokenPriceFeed();
        // bkce.getCollateralBalanceOfUser();
        // getAccountCollateralValue();
    }
}
