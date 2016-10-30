pragma solidity ^0.4.2;

import "./dependencies/SafeMath.sol";
import "./dependencies/ERC20.sol";
import "./tokens/MelonToken_test.sol";
import "./tokens/PolkaDotToken_test.sol";

/// @title Contribution_test Contract
/// @author Melonport AG <team@melonport.com>
/// @notice This follows Condition-Orientated Programming as outlined here:
/// @notice   https://medium.com/@gavofyork/condition-orientated-programming-969f6ba0161a#.saav3bvva
contract Contribution_test is SafeMath {

    // FILEDS

    // Constant fields
    uint public constant ETHER_CAP = 1800000 ether; // max amount raised during contribution
    uint constant BLKS_PER_WEEK = 41710; // Rounded result of 3600*24*7/14.5
    uint constant UNIT = 10**3; // MILLI [m]
    uint constant ILLIQUID_PRICE = 1125; // One illiquid tier

    // Fields that are only changed in constructor
    address public melonport = 0x0; // All deposited ETH will be instantly forwarded to this address.
    address public parity = 0x0; // Token allocation for company
    address public signer = 0x0; // signer address see function() {} for comments
    uint public startBlock; // contribution start block (set in constructor)
    uint public endBlock; // contribution end block (set in constructor)
    // FOR TESTING PURPOSES ONLY:
    MelonToken_test public melonToken;
    PolkaDotToken_test public polkaDotToken;

    // Fields that can be changed by functions
    uint public presaleEtherRaised = 0; // this will keep track of the Ether raised during the contribution
    uint public presaleTokenSupply = 0; // this will keep track of the token supply created during the contribution
    bool public companyAllocated = false; // this will change to true when the company funds are allocated
    bool public halted = false; // the melonport address can set this to true to halt the contribution due to an emergency

    // EVENTS

    event Buy(address indexed sender, uint eth, uint tokens);
    event AllocateCompanyTokens(address indexed sender);

    // MODIFIERS

    modifier is_signer(uint8 v, bytes32 r, bytes32 s) {
        bytes32 hash = sha256(msg.sender);
        if (ecrecover(hash,v,r,s) != signer) throw;
        _;
    }

    modifier only_melonport {
        if (msg.sender != melonport) throw;
        _;
    }

    modifier is_not_halted {
        if (halted) throw;
        _;
    }

    modifier ether_cap_not_reached {
        if (safeAdd(presaleEtherRaised, msg.value) > ETHER_CAP) throw;
        _;
    }

    modifier msg_value_well_formed {
        if (msg.value < UNIT || msg.value % UNIT != 0) throw;
        _;
    }

    modifier when_company_not_allocated {
        if (companyAllocated) throw;
        _;
    }

    // FOR TESTING PURPOSES ONLY: blockNumber instead of block.number
    modifier block_number_at_least(uint x) {
        if (!(x <= blockNumber)) throw;
        _;
    }

    // FOR TESTING PURPOSES ONLY: blockNumber instead of block.number
    modifier block_number_at_most(uint x) {
        if (!(blockNumber <= x)) throw;
        _;
    }

    // FUNCTIONAL METHODS

    /// Pre: startBlock, endBlock specified in constructor,
    /// Post: Contribution_test liquid price in m{MLN+PDT}/ETH, where 1 MLN == 1000 mMLN, 1 PDT == 1000 mPDT
    function price() constant returns(uint)
    {
        // Four liquid tiers
        if (block.number>=startBlock && block.number < startBlock + 2*BLKS_PER_WEEK)
            return 1075;
        if (block.number>=startBlock + 2*BLKS_PER_WEEK && block.number < startBlock + 4*BLKS_PER_WEEK)
            return 1050;
        if (block.number>=startBlock + 4*BLKS_PER_WEEK && block.number < startBlock + 6*BLKS_PER_WEEK)
            return 1025;
        if (block.number>=startBlock + 6*BLKS_PER_WEEK && block.number < endBlock)
            return 1000;
        // Before or after contribution period
        return 0;
    }

    // FOR TESTING PURPOSES ONLY:
    /// Pre: Liquid price for a given blockNumber (!= block.number)
    /// Post: Liquid price for externally defined blockNumber
    function testPrice() constant returns(uint)
    {
        // Four liquid tiers
        if (blockNumber>=startBlock && blockNumber < startBlock + 2*BLKS_PER_WEEK)
            return 1075;
        if (blockNumber>=startBlock + 2*BLKS_PER_WEEK && blockNumber < startBlock + 4*BLKS_PER_WEEK)
            return 1050;
        if (blockNumber>=startBlock + 4*BLKS_PER_WEEK && blockNumber < startBlock + 6*BLKS_PER_WEEK)
            return 1025;
        if (blockNumber>=startBlock + 6*BLKS_PER_WEEK && blockNumber < endBlock)
            return 1000;
        // Before or after contribution period
        return 0;
    }

    // NON-CONDITIONAL IMPERATIVAL METHODS

    /// Pre: ALL fields, except { melonport, signer, startBlock, endBlock } are valid
    /// Post: All fields, including { melonport, signer, startBlock, endBlock } are valid
    function Contribution_test(address melonportInput, address parityInput, address signerInput, uint startBlockInput) {
        melonport = melonportInput;
        parity = parityInput;
        signer = signerInput;
        startBlock = startBlockInput;
        endBlock = startBlockInput + 8*BLKS_PER_WEEK;
        // Create Token Contracts
        melonToken = new MelonToken_test(this, startBlock, endBlock);
        polkaDotToken = new PolkaDotToken_test(this, startBlock, endBlock);
    }

    /// Pre: Melonport even before contribution period
    /// Post: Allocate funds of the two companies to their company address.
    function allocateCompanyTokens()
        only_melonport()
        when_company_not_allocated()
    {
        melonToken.mintIlliquidToken(melonport, ETHER_CAP * 1200 / 30000); // 12 percent for melonport
        melonToken.mintIlliquidToken(parity, ETHER_CAP * 300 / 30000); // 3 percent for parity
        polkaDotToken.mintIlliquidToken(melonport, 2 * ETHER_CAP * 75 / 30000); // 0.75 percent for melonport
        polkaDotToken.mintIlliquidToken(parity, 2 * ETHER_CAP * 1425 / 30000); // 14.25 percent for parity
        companyAllocated = true;
        AllocateCompanyTokens(msg.sender);
    }

    /// Pre: Buy entry point, msg.value non-zero multiplier of UNIT wei, where 1 wei = 10 ** (-18) ether
    ///  All contribution depositors must have read and accpeted the legal agreement on https://contribution.melonport.com.
    ///  By doing so they receive the signature sig.v, sig.r and sig.s needed to contribute.
    /// Post: Bought MLN and PDT tokens accoriding to price() and msg.value of LIQUID tranche
    function buyLiquid(uint8 v, bytes32 r, bytes32 s) payable { buyLiquidRecipient(msg.sender, v, r, s); }

    /// Pre: Generated signature (see Pre: text of buyLiquid()) for a specific address
    /// Post: Bought MLN and PDT tokens on behalf of recipient accoriding to price() and msg.value of LIQUID tranche
    function buyLiquidRecipient(address recipient, uint8 v, bytes32 r, bytes32 s)
        payable
        is_signer(v, r, s)
        block_number_at_least(startBlock)
        block_number_at_most(endBlock)
        is_not_halted()
        msg_value_well_formed()
        ether_cap_not_reached()
    {
        // FOR TESTING PURPOSES ONLY: testPrice() instead of price()
        uint tokens = safeMul(msg.value / UNIT, testPrice());
        melonToken.mintLiquidToken(recipient, tokens / 3);
        polkaDotToken.mintLiquidToken(recipient, 2 * tokens / 3);
        presaleEtherRaised = safeAdd(presaleEtherRaised, msg.value);
        if(!melonport.send(msg.value)) throw;
        Buy(recipient, msg.value, tokens);
    }

    /// Pre: Generated signature (see Pre: text of buyLiquid())
    /// Post: Bought MLN and DPT tokens accoriding to price() and msg.value of ILLIQUID tranche
    function buyIlliquid(uint8 v, bytes32 r, bytes32 s) payable { buyIlliquidRecipient(msg.sender, v, r, s); }

    /// Pre: Generated signature (see Pre: text of buyLiquid()) for a specific address
    /// Post: Bought MLN and PDT tokens on behalf of recipient accoriding to price() and msg.value of ILLIQUID tranche
    function buyIlliquidRecipient(address recipient, uint8 v, bytes32 r, bytes32 s)
        payable
        is_signer(v, r, s)
        block_number_at_least(startBlock)
        block_number_at_most(endBlock)
        is_not_halted()
        msg_value_well_formed()
        ether_cap_not_reached()
    {
        uint tokens = safeMul(msg.value / UNIT, ILLIQUID_PRICE);
        melonToken.mintIlliquidToken(recipient, tokens / 3);
        polkaDotToken.mintIlliquidToken(recipient, 2 * tokens / 3);
        presaleEtherRaised = safeAdd(presaleEtherRaised, msg.value);
        if(!melonport.send(msg.value)) throw;
        Buy(recipient, msg.value, tokens);
    }

    function halt() only_melonport() { halted = true; }

    function unhalt() only_melonport() { halted = false; }

    function changeFounder(address newFounder) only_melonport() { melonport = newFounder; }

    // FOR TESTING PURPOSES ONLY:
    /// Pre: Assuming parts of code used where block.number is replaced (testcase) w blockNumber
    /// Post: Sets blockNumber for testing
    uint public blockNumber = 0;
    function setBlockNumber(uint blockNumberInput) {
        blockNumber = blockNumberInput;
        melonToken.setBlockNumber(blockNumber);
        polkaDotToken.setBlockNumber(blockNumber);
    }

}
