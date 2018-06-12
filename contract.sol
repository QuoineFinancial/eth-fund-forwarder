pragma solidity ^0.4.24;

//ERC20 Token interface
contract ContractToken {
    function transfer(address to, uint256 value) public returns (bool);
    function balanceOf(address user) public returns (uint256);
}

// Contract used for forwarding ETH and token from UserWallet to exchange wallet
contract FundForwardContract {
    Wallet wallet;
    
    constructor(address _wallet) public {
        wallet = Wallet(_wallet);
    }
    
    modifier onlyFundForwarder() {
        require(msg.sender == wallet.fundForwarder());
        _;
    }
    
    modifier walletRunning() {
        require(wallet.running() == true);
        _;
    }

    // only forwarder from wallet has the right to call this function
    function forward(address _id)
    onlyFundForwarder
    walletRunning
    public 
    returns (bool success) {
        success = false;
        address destination = wallet.mainWallet();
        uint amount;

        // default address 0x000...00 for transfer ETH
        // otherwise, load contract token and call transfer method
        // transfer all available ETH / (_id) token to exchange wallet
        if (_id != address(0)) {
            ContractToken token = ContractToken(_id);
            amount = token.balanceOf(this);
            success = token.transfer(destination, amount);
        } else {
            amount = address(this).balance;
            success = destination.send(amount);
        }
        
        if (success) {
            wallet.logForward(_id, this, destination, amount);
        }
    }
}

// The contract at user's address
// This contract will delegate fund forwarder contract the right to withdraw money to exchange address
contract UserWallet {
    Wallet wallet;
    
    constructor(address _wallet) public {
        wallet = Wallet(_wallet);
    }
    
    modifier onlyFundForwarder() {
        require(msg.sender == wallet.fundForwarder());
        _;
    }

    // Allow this contract to receive ETH
    function () public payable { }
    
    // Allow this contract to receive token
    function tokenFallback(address _from, uint _value, bytes _data) public {
        (_from);
        (_value);
        (_data);
     }

    // only fundforwarder has the right to call forward
    function forward(address _id) 
        onlyFundForwarder
        public
    returns (bool) {
        // give the fundforwarder the right to transfer token/ETH out of this address
        return wallet.getForwardContract(_id).delegatecall(msg.data);
    }
}

contract Owner {
    address public mainWallet; // default address keep ETH and token
    address public owner; // owner has the right to change mainWallet, and fundforwarder
    address public fundForwarder; // default address has the right to call forward on UserWallet
    
    constructor(address _fundForwarder) public {
        owner = msg.sender;
        mainWallet = msg.sender;
        fundForwarder = _fundForwarder;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
    
    function changeMainWallet(address _mainWallet) onlyOwner public {
        mainWallet = _mainWallet;
    }
    
    function changeOwner(address _owner) onlyOwner public {
        owner = _owner;
    }

    function changeFundForwarder(address _fundForwarder) onlyOwner public {
        fundForwarder = _fundForwarder;
    }
}

// Generate new address for user
// The new address can be used for ETH and other ERC20 Token
contract Generator {
    address public owner; // default address has the right to make new UserWallet contract
    
    event LogAddress(address _address);
    
    constructor() public {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    } 
    
    // new wallet is created only if it was called by the owner,
    function generate(address vendor) 
        onlyOwner
        public
    returns (address newAddress) {
        newAddress = address(new UserWallet(vendor));
        emit LogAddress(newAddress);
    }
}

// Wallet controlls
// * main wallet address for ETH and tokens
// * fundforwarder who has the right to move fund to main wallet
// * update forwarder contract for new contract tokens
contract Wallet is Owner {
    mapping(address => address) forwardContract;
    address public defaultForwardContract = address(new FundForwardContract(this));
    bool public running = true;

    constructor(address _fundForwarder) Owner(_fundForwarder) { }
    
    event LogForward(address contractToken, address from, address to, uint amount);
    
    function updateForwardContract(address _token, address _address) onlyOwner public {
        forwardContract[_token] = _address;
    }
    
    function resume() onlyOwner public {
        running = false;
    }
    
    function pause() onlyOwner public {
        running = true;
    }
    
    // by default, every tokens and ETH will be forward by defaultForwarder
    function getForwardContract(address _token) public returns (address res) {
        res = forwardContract[_token];
        if (res == 0) res = defaultForwardContract;
    }
    
    function logForward(address token, address from, address to, uint amount) public {
        emit LogForward(token, from, to, amount);
    }
}