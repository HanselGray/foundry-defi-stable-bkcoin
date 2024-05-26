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
    error BKEngine__GoodHealthFactor();
    error BKEngine__HealthFactorNotImproved();

    /////////////////////////
    // State variables    ///
    /////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 150;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
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
    event CollateralRedeemed(
        address indexed from,
        address indexed to,
        address indexed token,
        uint256 amount
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

    /**
     * @param amount: amount of Bkc to burn
     */
    function burnBKC(uint256 amount) public moreThanZero(amount) nonReentrant {
        _burnBKC(msg.sender, msg.sender, amount);
        _revertIfHealthFactorIsBroken(msg.sender); // Just for safety, very unlikely would happen,
    }

    /**
     * @param tokenCollateralAddress: Address of token to deposit as collateral
     * @param amountCollateral: Amount of collateral to deposit, should be more than zero
     * @param amountBKC: Amount of BKC to mint
     * @notice This will deposit and mint collateral in one transaction
     */

    function depositCollateralAndMintBKC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountBKC
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintBKC(amountBKC);
    }

    /**
     * @param tokenCollateralAddress Address of collateral to redeem,
     * @param amountCollateral Amount of collateral to redeem
     * @param amountBkcToBurn Amount of BKC to burn **NOTE: This should be equal to the amount
     of Collateral retrieve times a certain coefficient.
     */
    function retrieveCollateralForBKC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountBkcToBurn
    ) external {
        burnBKC(amountBkcToBurn);
        _retrieveCollateral(
            msg.sender,
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        // redeemCollateral already checks health factor
    }

    function retrieveCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        _retrieveCollateral(
            msg.sender,
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * Follows CEI: Checks -> Effects -> Interactions
     */
    function liquidate(
        address user,
        address tokenCollateralAddress,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert BKEngine__GoodHealthFactor();
        }

        // Burn BKC "debt" and take collateral from user
        // Example bad user: $140 ETH, $100 BKC -> debtToCover = $100
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            tokenCollateralAddress,
            debtToCover
        );

        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;

        _retrieveCollateral(
            user,
            msg.sender,
            tokenCollateralAddress,
            totalCollateralToRedeem
        );

        _burnBKC(user, msg.sender, debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert BKEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ////////////////////////
    // Public functions  ///
    ////////////////////////

    /**
     * @notice follows CEI: Checks -> Effects -> Interactions
     * @param amountBkc: amount of BKC to mint
     * @notice must follow the over-collateralized rule
     */
    function mintBKC(
        uint256 amountBkc
    ) public moreThanZero(amountBkc) nonReentrant {
        _sBkcMinted[msg.sender] += amountBkc;

        // If minted too much, revert changes
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = _iBkc.mint(msg.sender, amountBkc);

        if (!minted) {
            revert BKEngine__MintFailed();
        }
    }

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
        public
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

    function healthCheck() external view {}

    ////////////////////////////////////////
    // Private and Internal functions    ///
    ////////////////////////////////////////

    function _retrieveCollateral(
        address from,
        address to,
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) private moreThanZero(amountCollateral) nonReentrant {
        _sCollateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );

        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert BKEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(from);
    }

    /**
     * @notice Low-level function, DO NOT CALL except after performing health checks
     */
    function _burnBKC(
        address onBehalfOf,
        address bkcFrom,
        uint256 amount
    ) private moreThanZero(amount) nonReentrant {
        _sBkcMinted[onBehalfOf] -= amount;
        bool success = _iBkc.transferFrom(bkcFrom, address(this), amount);
        if (!success) {
            revert BKEngine__TransferFailed();
        }
        _iBkc.burn(amount);

        _revertIfHealthFactorIsBroken(msg.sender); // Just for safety, very unlikely would happen,
    }

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

    function _calculateHealthFactor(
        uint256 totalBkcMinted,
        uint256 totalCollateralValue
    ) internal pure returns (uint256) {
        // If never minted -> Health always good
        if (totalBkcMinted == 0) {
            return type(uint256).max;
        }

        // Example
        // total collat value = 1000usd ETH
        // minted = 800 usd BKC
        // collateral floor = 800*150/100 = 1200 usd
        // healthFactor = (1000 / 1200) < 1 => UNDER-COLLATERALIZED, can be liquidate

        uint256 collateralThresholdFloor = (totalBkcMinted *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (totalCollateralValue * PRECISION) / collateralThresholdFloor;
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

        return _calculateHealthFactor(totalBkcMinted, totalCollateralValue);
    }

    function _getUsdValue(
        address token,
        uint256 amount
    ) private view returns (uint256) {
        // Using Chainlink AggregatorV3Interface to get price feeds for a token
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            _sPriceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        // 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        // Hence the formula (price * 1e18) / 1e18 -> for normalization

        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /*
     * 1. Check if user have enough health factor
     * 2. Revert if doesn't pass check
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert BKEngine__WeakHealthFactor(userHealthFactor);
        }
    }

    ///////////////////////////////////////////////////
    // Public and External view & Pure functions    ///
    ///////////////////////////////////////////////////

    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }


    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalBkcMinted, uint256 collateralValueInUsd)
    {
        (totalBkcMinted, collateralValueInUsd) = _getAccountInformation(user);
    }


    function getUsdValue(
        address token,
        uint256 amount // in WEI
    ) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }


    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return _sCollateralDeposited[user][token];
    }


    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralInUsd) {
        for (uint256 i = 0; i < _sCollateralTokens.length; ++i) {
            address token = _sCollateralTokens[i];
            uint256 amount = _sCollateralDeposited[user][token];
            totalCollateralInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralInUsd;
    }


    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            _sPriceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION); // MAKING SURE THINGS ALLIGN WITH THE PRECISION HERE
    }
    

    // STATUS: DONE
    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return _sCollateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(_iBkc);
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return _sPriceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
