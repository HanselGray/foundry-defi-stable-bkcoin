// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {BKCoin} from "../src/BKCoin.sol";
import {BKEngine} from "../src/BKEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployBKC is Script {
    address[] public tokenAddress;
    address[] public priceFeedAddress;

    function run() external returns (BKCoin, BKEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey
        ) = config.activeNetworkConfig();

        tokenAddress = [weth, wbtc];
        priceFeedAddress = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);

        BKCoin bkc = new BKCoin();
        BKEngine engine = new BKEngine(
            tokenAddress,
            priceFeedAddress,
            address(bkc)
        );
        bkc.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (bkc, engine, config);
    }
}
