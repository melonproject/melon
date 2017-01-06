pragma solidity ^0.4.4;

import "../dependencies/SafeMath.sol";
import "../dependencies/ERC20.sol";

/// @title Melon Voucher Contract
/// @author Melonport AG <team@melonport.com>
contract MelonVoucher is ERC20, SafeMath {

    // FILEDS

    // Constant token specific fields
    string public constant name = "Melon Voucher";
    string public constant symbol = "MLN";
    uint public constant decimals = 18;
    uint public constant THAWING_DURATION = 2 years; // Time needed for iced vouchers to thaw into liquid vouchers
    uint public constant MAX_TOTAL_VOUCHER_AMOUNT = 1250000 * 10 ** decimals; // Max amount of total vouchers raised during all contributions

    // Fields that are only changed in constructor
    address public minter; // Contribution contract(s)
    address public melonport; // Can change to other minting contribution contracts but only until total amount of voucher minted
    uint public startTime; // Contribution start time in seconds
    uint public endTime; // Contribution end time in seconds

    // Fields that can be changed by functions
    mapping (address => uint) lockedBalances;

    // MODIFIERS

    modifier only_minter {
        assert(msg.sender == minter);
        _;
    }

    modifier only_melonport {
        assert(msg.sender == melonport);
        _;
    }

    modifier is_later_than(uint x) {
        assert(now > x);
        _;
    }

    modifier max_total_voucher_amount_not_reached(uint amount) {
        assert(safeAdd(totalSupply, amount) <= MAX_TOTAL_VOUCHER_AMOUNT);
        _;
    }

    // CONSTANT METHODS

    function lockedBalanceOf(address _owner) constant returns (uint balance) {
        return lockedBalances[_owner];
    }

    // METHODS

    /// Pre: All fields, except { minter, melonport, startTime, endTime } are valid
    /// Post: All fields, including { minter, melonport, startTime, endTime } are valid
    function MelonVoucher(address setMinter, address setMelonport, uint setStartTime, uint setEndTime) {
        minter = setMinter;
        melonport = setMelonport;
        startTime = setStartTime;
        endTime = setEndTime;
    }

    /// Pre: Address of contribution contract (minter) is set
    /// Post: Mints voucher into tradeable tranche
    function mintLiquidVoucher(address recipient, uint amount)
        external
        only_minter
        max_total_voucher_amount_not_reached(amount)
    {
        balances[recipient] = safeAdd(balances[recipient], amount);
        totalSupply = safeAdd(totalSupply, amount);
    }

    /// Pre: Address of contribution contract (minter) is set
    /// Post: Mints Voucher into iced tranche. Become liquid after completion of the melonproject or two years.
    function mintIcedVoucher(address recipient, uint amount)
        external
        only_minter
        max_total_voucher_amount_not_reached(amount)
    {
        lockedBalances[recipient] = safeAdd(lockedBalances[recipient], amount);
        totalSupply = safeAdd(totalSupply, amount);
    }

    /// Pre: Thawing period has passed - iced funds have turned into liquid ones
    /// Post: All funds available for trade
    function unlockBalance(address recipient)
        is_later_than(endTime + THAWING_DURATION)
    {
        balances[recipient] = safeAdd(balances[recipient], lockedBalances[recipient]);
        lockedBalances[recipient] = 0;
    }

    /// Pre: Prevent transfers until contribution period is over.
    /// Post: Transfer MLN from msg.sender
    /// Note: ERC20 interface
    function transfer(address recipient, uint amount)
        is_later_than(endTime)
        returns (bool success)
    {
        return super.transfer(recipient, amount);
    }

    /// Pre: Prevent transfers until contribution period is over.
    /// Post: Transfer MLN from arbitrary address
    /// Note: ERC20 interface
    function transferFrom(address sender, address recipient, uint amount)
        is_later_than(endTime)
        returns (bool success)
    {
        return super.transferFrom(sender, recipient, amount);
    }

    /// Pre: Melonport address is set.
    /// Post: New minter can now create vouchers up to MAX_TOTAL_VOUCHER_AMOUNT.
    /// Note: This allows additional contribution periods at a later stage, while still using the same ERC20 compliant contract.
    function changeMintingAddress(address newAddress) only_melonport { minter = newAddress; }
}
