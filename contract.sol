pragma solidity ^0.4.24;

contract ContractToken {
    function transfer(address to, uint256 value) public returns (bool);
    function balanceOf(address user) public returns (uint256);
}

contract FundForwarder {
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

    function forward(address _id)
    onlyFundForwarder
    walletRunning
    public 
    returns (bool) {
        bool success = false;
        address destination = wallet.mainWallet();
        uint amount;

        if (_id != address(0)) {
            ContractToken token = ContractToken(_id);
            amount = token.balanceOf(this);
            success = token.transfer(destination, amount);
        } else {
            amount = address(this).balance;
            success = destination.send(amount);
        }
        
        if (success) {
            wallet.logForward(this, destination, _id, amount);
        }
        
        return success;
    }
}

contract UserWallet {
    Wallet wallet;
    
    constructor(address _wallet) public {
        wallet = Wallet(_wallet);
    }
    
    modifier onlyFundForwarder() {
        require(msg.sender == wallet.fundForwarder());
        _;
    }

    function () public payable { }
    
    function tokenFallback(address _from, uint _value, bytes _data) public {
        (_from);
        (_value);
        (_data);
     }

    function forward(address _id) 
        onlyFundForwarder
        public
    returns (bool) {
        return wallet.getForwarder(_id).delegatecall(msg.data);
    }
}

contract Owner {
    address public mainWallet;
    address public owner;
    address public fundForwarder;
    
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

contract Generator {
    address public admin;
    address public owner;
    mapping(address => bool) whiteList;
    
    event LogAddress(address _address);
    
    constructor(address _admin) public {
        admin = _admin;
        owner = msg.sender;
    }
    
    modifier onlyAdmin() {
        require(msg.sender == admin);
        _;
    }
    
    modifier makable(address vendor) {
        require(msg.sender == owner);
        require(whiteList[vendor] == true);
        _;
    } 
    
    function generate(address vendor) 
        makable(vendor)
        public
    returns (address newAddress) {
        newAddress = address(new UserWallet(vendor));
        emit LogAddress(newAddress);
    }
    
    function updateWhitelist(address _address, bool _state) onlyAdmin public {
        whiteList[_address] = _state;
    }
}

contract Wallet is Owner {
    mapping(address => address) forwarder;
    address public defaultForwarder = address(new FundForwarder(this));
    bool public running = true;

    constructor(address _fundForwarder) Owner(_fundForwarder) { }
    
    event LogForward(address from, address to, address contractToken, uint amount);
    
    function updateForwarder(address _token, address _address) onlyOwner public {
        forwarder[_token] = _address;
    }
    
    function resume() onlyOwner public {
        running = false;
    }
    
    function pause() onlyOwner public {
        running = true;
    }
    
    function getForwarder(address _token) public returns (address) {
        address res = forwarder[_token];
        if (res == 0) res = defaultForwarder;
        return res;
    }
    
    function logForward(address from, address to, address _token, uint amount) public {
        emit LogForward(from, to, _token, amount);
    }
}