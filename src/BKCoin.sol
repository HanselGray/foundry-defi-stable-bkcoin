// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
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

pragma solidity ^0.8.18;

import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/** 
 * @title BKCoin
 * @author Thoi Mo Senh Ca
 * Collateral: wETH and wBTC
 * Stability: Pegged to USD
 * This is just the ERC20 token for our stablecoin system
 */
contract BKCoin is ERC20Burnable, Ownable {
    error BKCoin__MustBeMoreThanZero();
    error BKCoin__BurnAmountExceedBalance();
    error BKCoin__NotZeroAddress();

    constructor() ERC20("BKCoin", "BKC")  {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        
        if (_amount <= 0) {
            revert BKCoin__MustBeMoreThanZero();
        }

        if (balance < _amount) {
            revert BKCoin__BurnAmountExceedBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns(bool){
        if(_to == address(0)){
            revert BKCoin__NotZeroAddress();
        }
        if(_amount <= 0){
            revert BKCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }


}
