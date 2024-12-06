// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
//import { ILendingPool, ILendingPoolAddressesProvider } from "./Interfaces.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts//interfaces/IPoolAddressesProvider.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";


/*

Todo
- prohibit premium payments subsequent to investment
- lock at the right times
- remove mint function
- change il token name

*/
 
contract SchILS_test is ERC20Permit, Pausable, AccessControl {
    // lending pool:
    // link: https://docs.aave.com/developers/deployed-contracts/v3-testnet-addresses
    // provider polygon mumbai 0x5343b5bA672Ae99d627A1C87866b8E53F47Db2E6
    // provier POLYGON: 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb
    // get pool returns: 0x794a61358D6845594F94dc1DB02A252b5b4814aD
    // contracts: https://mumbai.polygonscan.com/address/0x5343b5bA672Ae99d627A1C87866b8E53F47Db2E6#readContract
    // https://mumbai.polygonscan.com/address/0x6c9fb0d5bd9429eb9cd96b85b81d872281771e6b
    // transaction from me: https://mumbai.polygonscan.com/tx/0x1a9c5b4d58b0cdb2181308e9d10eb52c3aaa071db2260aff0cb99de29d5e7cf1
    // lending pool
    IPool public myPool;
    address public usdcPolygon = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    IPoolAddressesProvider public provider = IPoolAddressesProvider(0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb);
    address public poolAddress;
    IERC20 USDC = IERC20(usdcPolygon);

    // Pauser role with ability to pause contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    // Minter role allowing to mint tokens 
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    // Indepentent party role that can trigger risk in case of event
    bytes32 public constant INDEPENDENT_PARTY_ROLE = keccak256("INDEPENDENT_PARTY_ROLE");
    // Investor role allowing to invest
    bytes32 public constant INVESTOR_ROLE = keccak256("INVESTOR_ROLE");
    // protection buyer role
    bytes32 public constant PROTECTION_BUYER_ROLE = keccak256("PROTECTION_BUYER_ROLE");

    // start of product lifetime
    uint256 public constant startProductLifetime = 1668503438;
    // end of product lifetime
    uint256 public constant endProductLifetime = 1668503438+1000000;

    
        


    // as los permit does not work
    IERC20 investmentCurrencyAlternative;
    address USDCAddress = 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4; //wrong address

    // whitelisted protocol addresses for yield earning
    //address[] public protocolWhitelist;

    // one year product phase active
    bool public productIsActive;
    // redeem phase active or inactive boolean
    bool public redeemPhaseActive;
    // to activate redeemphase,  cooldownphase needs to be over
    uint256 public cooldownPhase;


    // risk parameters
    address public risk_A_address;
    address public risk_B_address;
    address public risk_C_address;
    uint256 public risk_A_damage;
    uint256 public risk_B_damage;
    uint256 public risk_C_damage;

    // defining amount of premium
    uint256 public premiumAmount;

    // boolean stating whether protection buyer redeemed
    bool public protectionBuyerDidPayout;


    constructor(uint256 _initialTokenPrice, IERC20 _currency) ERC20("SchILS", "SILS") ERC20Permit("SchILS") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(INVESTOR_ROLE, msg.sender);
        _grantRole(INDEPENDENT_PARTY_ROLE, msg.sender);
        // provider address will never change, but pool address might change:
        // thats why we need to get use .getPool()
        poolAddress =  provider.getPool();
        myPool = IPool(poolAddress);

        _grantRole(INVESTOR_ROLE, 0x283a28BCAEd7aBb1C8ffc4Ffde9f1a28692C3e22);
        _grantRole(INVESTOR_ROLE, 0xA98a62D00cbb46F53eB426571cA784d6656Cc54D);
        _grantRole(INVESTOR_ROLE, 0x3Bb86575C5Cf7efd931613fCCC7F5d4E93757471);
        _grantRole(INVESTOR_ROLE, 0xa426eB1A25c3C2495b6Ea16bcF5CcC0b7e2EEdE7);


        // set initial token price
        ILSTokenPrice = _initialTokenPrice;
        // set initial investment currency
        //ERC20InvestmentCurrency = _currency;
        investmentCurrencyAlternative = _currency;

        redeemPhaseActive = true;

        risk_A_damage = 0;
        risk_B_damage = 0;
        risk_C_damage = 0;

        protectionBuyerDidPayout = false;
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    /*
    function mint(address to, uint256 amount) public onlyRole(INVESTOR_ROLE) {
        _mint(to, amount);
    }
    */

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(from, to, amount);
    }


    /*--- EVENTS ---*/
    
    event NewInvestorWhitelisted(address _new);
    event NewILSPriceSet(uint256 _price);
    event NewCurrencySet(IERC20 _currency);
    //event NewProtocolAdded(address _protocol);
    //event ProtocolRemoved(address _protocol);

    event Investment(uint256 _amount, address _investor);
    event Redeem(uint256 _amount, address _investor);

    event RiskTriggered(uint256 _risk, uint256 degree);

    /*--- MODIFIERES ---*/
    modifier productlifetime {
            require(block.timestamp < startProductLifetime || block.timestamp > endProductLifetime);
            _;
    }



    /*--- ADMIN FUNCTIONS ---*/


    /*
    Add new investor and grant investor role
    */
    function grantInverstorRole(address _investor) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(INVESTOR_ROLE, _investor);
        emit NewInvestorWhitelisted(_investor);
    }

    /*
    Add new independent party role 
    */
    function grantIndependentRole(address _independentParty) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(INDEPENDENT_PARTY_ROLE, _independentParty);
        //emit 
    }

    /*
    Add new protection buyer role
    */
    function grantProtectionBuyerRole(address _protectionBuyer) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(PROTECTION_BUYER_ROLE, _protectionBuyer);
        //emit 
    }

    /*
    Revoke Investor Role from address
    */
    function revokeInvestorRole(address _investor) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(INVESTOR_ROLE, _investor);
    }

    /*
    Set ILS Token Price (USDC)
    */
    function setILSTokenPrice(uint256 _newPrice) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newPrice > 0, "invalid price");
        ILSTokenPrice = _newPrice;
        emit NewILSPriceSet(_newPrice);
    }

    /*
    Set ILS Token Price (USDC)
    */
   function setInvestmentToken(IERC20 _currency) public onlyRole(DEFAULT_ADMIN_ROLE) {
       investmentCurrencyAlternative  = _currency;
        emit NewCurrencySet(_currency);
    }

    function setRedeemPhase(bool _activate) public onlyRole(DEFAULT_ADMIN_ROLE) {
        redeemPhaseActive = _activate;
        
    }

    /*
    Add protocol address to protocolWhitlelist - only whitelisted protocols can be used for 
    yield earning
    
    function addProtocol(address _protocol) public onlyRole(DEFAULT_ADMIN_ROLE) {
        protocolWhitelist.push(_protocol);
        emit NewProtocolAdded(_protocol);
    }

    
    Remove protocol address from protocolWhitlelist - only whitelisted protocols can be used for 
    yield earning
    
    function removeProtocol(address _protocol) public onlyRole(DEFAULT_ADMIN_ROLE) {
        // boolean to check wheteher _protocol is in protocolWhitelist
        bool protocolFlag = false;
        // index of removing address (if in list)
        uint256 index;
        uint256 _length = protocolWhitelist.length;
        for(uint256 i = 0; i > _length; i++) {
            if(protocolWhitelist[i] == _protocol) {
                protocolFlag = true;
                index = i;
            }
        }
        require(protocolFlag == true, "invalid protocol address");
        
        // get address at last position to overwrite removing address and pop it
        address lastIndexAddress = protocolWhitelist[_length - 1];
        protocolWhitelist[index] = lastIndexAddress;
        protocolWhitelist.pop();
        
        emit ProtocolRemoved(_protocol);
    }
    */

    /*
    Activate / deactivate redeem phase
    */
    

    /*
    Force redeem 
    

    function forceRedeem(address _investor) public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balanceILS = balanceOf(_investor);
        uint256 balanceUSDC = calculatePayoutPerInvestor(_investor);
        transferFrom(msg.sender, address(this), balanceILS);
        //ERC20InvestmentCurrency.transfer(msg.sender, _investor);
    }
    */

    


    /*--- PROTECTION SELLER/INVESTOR FUNCTIONS ---*/

   

    /*
    approv erc20 ???
    Subscribe to ILS by depositing investing currency (USDC) and receive SchILS tokens
    */
    function subscribe(uint256 _quantityInvestment/*, uint256 deadline, uint8 v, bytes32 r, bytes32 s*/) public onlyRole(INVESTOR_ROLE) {
        require(_quantityInvestment > 0, "<0");
        //require(ERC20InvestmentCurrency.balanceOf(msg.sender) > _quantityInvestment, "not enough tokens left");
        // calculate amount of investment tokens (USDC) that have to be payed
        uint256 amountILSTokens = _quantityInvestment*(10**18) * ILSTokenPrice;
        // approve transfer to this address
        //ERC20InvestmentCurrency.permit(msg.sender, address(this), _quantityInvestment, deadline, v, r, s);
        // transfer investment currency to this address
        investmentCurrencyAlternative.transferFrom(msg.sender, address(this), _quantityInvestment*(10**18));
        // mint SchILS token to msg.sender
        _mint(msg.sender, amountILSTokens);
        approve(0x35a25dafAAa90b33669B16f15B5E9E767B094bBF, amountILSTokens);
    }

 

    /*
    approve ils token transfer
    Redeem shares by sending back _quantity of SchILS tokens
    */
    function redeem(/*uint256 _quantity*/) public {
        //require(balanceOf(msg.sender) > _quantity && _quantity > 0, "");
        require(redeemPhaseActive, "not possible yet");
        require(balanceOf(msg.sender) > 0);
        uint256 redeemingAmount = calculatePayoutPerInvestor(msg.sender);
        // investor transfers ILS tokens to contract
        transferFrom(msg.sender, address(this), balanceOf(msg.sender));
        // contract pays out USDC to investor
        investmentCurrencyAlternative.transfer(msg.sender, redeemingAmount);
    }




    /*--- PROTECTION BUYER (HRE) FUNCTIONS ---*/

    /*
    Protection buyer paying pay premium
    */
    function payPremium(uint256 _quantity) public onlyRole(PROTECTION_BUYER_ROLE) {
        investmentCurrencyAlternative.transferFrom(msg.sender, address(this), _quantity);
    }

    /*
    Set risk address to corresponding risk 
    */
    function setRiskAddress(address _riskAddress, uint256 _risk) public onlyRole(PROTECTION_BUYER_ROLE) {
        require(_risk > 0 && _risk < 4, "invalid parameter");
        if(_risk == 1) {
            risk_A_address = _riskAddress;
        }
        else if(_risk == 2) {
            risk_B_address = _riskAddress;
        }
        else {
            risk_C_address = _riskAddress;
        }
    }

    /*
    Protection buyer can redeem usdc (if damage occured)
    */
    function redeemProtectionBuyer() public onlyRole(PROTECTION_BUYER_ROLE) {
        require(!protectionBuyerDidPayout, "already redeemed");
        require(redeemPhaseActive, "not possible yet");
        protectionBuyerDidPayout = true;
        uint256 totalAmountWithoutPremium = investmentCurrencyAlternative.totalSupply() - premiumAmount;
        // amount of investment currency after interest without premium per risk
        uint256 amountPerRisk = (totalAmountWithoutPremium / 100000) * 33333;
        // calculate amount per risk after damage (zero if all damages zero)
        uint256 redeemA_amount = amountPerRisk*risk_A_damage;
        uint256 redeemB_amount = amountPerRisk*risk_B_damage;
        uint256 redeemC_amount = amountPerRisk*risk_C_damage;
        if(redeemA_amount > 0) {
            investmentCurrencyAlternative.transfer(risk_A_address, redeemA_amount);
        }
        if(redeemB_amount > 0) {
            investmentCurrencyAlternative.transfer(risk_B_address, redeemB_amount);
        }
        if(redeemC_amount > 0) {
            investmentCurrencyAlternative.transfer(risk_C_address, redeemC_amount);
        }
    }

    /*--- INDEPENDENT PARTY FUNCTIONS ---*/

    /*
    Set damage if occurs, risk = 1 -> A, 2 -> B, 3 -> C
    */
    function setDamage(uint256 _damage, uint256 _risk) public onlyRole(INDEPENDENT_PARTY_ROLE) {
        require(_risk > 0 && _risk < 4, "invalid parameter");
        require(_damage <= 1, "invalid damage");
        if(_risk == 1) {
            risk_A_damage = _damage;
        }
        else if(_risk == 2) {
            risk_B_damage = _damage;
        }
        else {
            risk_C_damage = _damage;
        }
    }


    /*--- LOGIC ---*/

    /*
    Calculates the share of specific investor
    */
    function calculateInvestorShare(address _investor) /*internal*/ public view returns(uint256) {
        // amount of tokens investor
        uint256 investorShares = balanceOf(_investor);
        // total amount tokens
        uint256 totalShares = totalSupply();
        // percentage for uint due to no decimals in solidity
        uint256 InvestorShare = (investorShares*100000)/totalShares;
        return InvestorShare;
    }

    /*
    Calculates amount of usdc that is paid out to investor after procutt lifetime
    */
    function calculatePayoutPerInvestor(address _investor) /*internal*/ public view  returns(uint256) {
        // get share of investor
        uint256 share = calculateInvestorShare(_investor);
        // get total amount of USDC in contract, including interest
        uint256 totalAmountOfInvestingCurrency = investmentCurrencyAlternative.balanceOf(address(this));
        // get total amount of premium
        uint256 totalAmountWithoutPremium = totalAmountOfInvestingCurrency - premiumAmount;
        // amount of investment currency after interest without premium per risk
        uint256 amountPerRisk = (totalAmountWithoutPremium / 100000000000) * 33333333333;
        // calculate amount after damage (stays same if all damages zero)
        uint256 amountAfterDamage = 
        amountPerRisk*((1-risk_A_damage) + (1-risk_B_damage) + (1-risk_C_damage));
        // share of payout of investor
        uint256 payOutToInvestor = (amountAfterDamage/1000) * share; //share 25000 = 25% -> thats why /1000
        // share of payout of investor including premium
        uint256 payOutToInvestorIncludingPremium = payOutToInvestor + (premiumAmount/1000)*share;
        return payOutToInvestorIncludingPremium;
    }

    function calculateInterestEarned() public returns(uint256) {
        return 0;
    }


    


    // ERC20 override such that only whitelisted addresses can receive functions
    function transfer(
        address _to, 
        uint256 _amount
        ) public virtual override onlyRole(INVESTOR_ROLE) returns(bool) {
        require(hasRole(INVESTOR_ROLE, _to));
        _transfer(msg.sender, _to, _amount);
        return true;
    }

    function transferFrom(
        address _from,
        address _to, 
        uint256 _amount
        ) public virtual override onlyRole(INVESTOR_ROLE) returns(bool) {
        require(hasRole(INVESTOR_ROLE, _to));
        address spender = _msgSender();
        _spendAllowance(_from, spender, _amount);
        _transfer(_from, _to, _amount);
        return true;
    }

    /*--- protocol interaction functions ---*/

    
    // AAVE interavtion

    function approveMaticToContract(uint256 amount, address _user) public {
        USDC.approve(address(this), amount);
    }

    function supply(address pool, address asset, address user, uint256 amount)
    internal {
        IPool(pool).supply(asset, amount, user, 0);
    }
    

    function withdraw(address pool, address asset, address to, uint256 amount) 
    internal {
        IPool(pool).withdraw(asset, amount, to);
    }

    function supplyToAave(address asset, uint256 amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        supply(poolAddress, asset, address(this), amount);
    }

    function withdrawFromAave(address asset, uint256 amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        withdraw(poolAddress, asset, address(this), amount);
    }
    

}
