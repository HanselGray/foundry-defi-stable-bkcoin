// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.19;

import {BKCoin} from "./BKCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
/**
 * @title BKEngine
 * @author Thoi Mo Senh Ca
 *
 *
 * The system is designed to be a minimal stablecoin system, and have the tokens maintain a 1.00$ peg
 * This stable coin has the following properties:
 * - Exogeneous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI, minus the Governance module.
 *
 * System should always be 'over-collateralized', meaning that the total value of our collateral should always be greater than our total amount of BKC by a margin.
 *
 * @notice This contract is the core of the BKCoin system. It handles all the logic for mining and redeeming BKC, as well as depositing & withdrawing collateral.
 * @notice This is very loosely based on the makerDAO DSS (Dai Stablecoin System)
 */

contract BKEngine is ReentrancyGuard {
    ///////////////////
    // Errors       ///
    ///////////////////
    error BKEngine__NonPostiveRejected();
    error BKEngine__TokenAddressAndPriceFeedAddressMustBeSameLength();
    error BKEngine__NotAllowedToken();
    error BKEngine__TransferFailed();
    error BKEngine__WeakHealthFactor(uint256 healthFactor);
    error BKEngine__MintFailed();

    /////////////////////////
    // State variables    ///
    /////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD= 150;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private _sPriceFeeds;
    mapping(address user => mapping(address token => uint256 amount))
        private _sCollateralDeposited;
    mapping(address user => uint256 amountBkcMinted) private _sBkcMinted;

    address[] private _sCollateralTokens;
    BKCoin private immutable _iBkc;

    ///////////////////
    // Events       ///
    ///////////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    ///////////////////
    // Modifiers    ///
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert BKEngine__NonPostiveRejected();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (_sPriceFeeds[token] == address(0)) {
            revert BKEngine__NotAllowedToken();
        }
        _;
    }

    ///////////////////
    // Functions    ///
    ///////////////////

    constructor(
        address[] memory tokenAddress,
        address[] memory priceFeedAddress,
        address bkcAddress
    ) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert BKEngine__TokenAddressAndPriceFeedAddressMustBeSameLength();
        }
        // USD Price Feed check
        for (uint256 i = 0; i < tokenAddress.length; ++i) {
            _sPriceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            _sCollateralTokens.push(tokenAddress[i]);
        }

        _iBkc = BKCoin(bkcAddress);
    }

    ////////////////////////////
    // External functions    ///
    ////////////////////////////

    function depositCollateralAndMintBKC() external {}

    /**
     * @notice follows CEI: Checks -> Effects -> Interactions
     * @param tokenCollateralAddress: Address of token to deposit as collateral
     * @param amountCollateral: Amount of collateral to deposit, should be more than zero
     *
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _sCollateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert BKEngine__TransferFailed();
        }
    }

    function retrieveCollateralForBKC() external {}

    function retrieveCollateral() external {}

    /**
     * @notice follows CEI: Checks -> Effects -> Interactions
     * @param amountBkc: amount of BKC to mint
     * @notice must follow the over-collateralized rule
     */
    function mintBKC(
        uint256 amountBkc
    ) external moreThanZero(amountBkc) nonReentrant {
        _sBkcMinted[msg.sender] += amountBkc;

        // If minted too much, revert changes
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = _iBkc.mint(msg.sender, amountBkc);

        if(!minted){
            revert BKEngine__MintFailed();
        }
    }

    function burnBKC() external {}

    function liquidate() external {}

    function healthCheck() external view {}

    ////////////////////////////////////////
    // Private and Internal functions    ///
    ////////////////////////////////////////

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalBkcMinted, uint256 collateralValueInUsd)
    {
        totalBkcMinted = _sBkcMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /*
     * Returns how close to liquidation a user is
     * If a user's health factor goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalBkcMinted,
            uint256 totalCollateralValue
        ) = _getAccountInformation(user);

        uint256 collateralThresholdFloor = (totalBkcMinted * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // Example
        // total collat value = 1000usd ETH
        // minted = 800 usd BKC
        // collateral floor = 800*150/100 = 1200 usd
        // healthFactor = (1000 / 1200) < 1 => UNDER-COLLATERALIZED, can be liquidate

        return (totalCollateralValue * PRECISION) / collateralThresholdFloor;
        
    }

    /*
     * 1. Check if user have enough health factor
     * 2. Revert if doesn't pass check
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR) {
            revert BKEngine__WeakHealthFactor(userHealthFactor);
        }
    }

    ////////////////////////////////////////////
    // Public and External view functions    ///
    ////////////////////////////////////////////
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralInUsd) {
        for (uint256 i = 0; i < _sCollateralTokens.length; ++i) {
            address token = _sCollateralTokens[i];
            uint256 amount = _sCollateralDeposited[user][token];
            totalCollateralInUsd += getUsdValue(token, amount);
        }
        return totalCollateralInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        // Using Chainlink AggregatorV3Interface to get price feeds for a token
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            _sPriceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; // (price * 1e18) / 1e18 -> for normalization    }
    }
}
