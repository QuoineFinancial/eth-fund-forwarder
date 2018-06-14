pragma solidity ^0.4.24;

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
    address public owner;
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev The Ownable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    constructor() public {
        owner = msg.sender;
    }
 
    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) onlyOwner public {
        require(newOwner != address(0));
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}


/**
 * @title Pausable
 * @dev Base contract which allows children to implement an emergency stop mechanism.
 */
contract Pausable is Ownable {
    event Pause();
    event Unpause();

    bool public paused = false;


    /**
    * @dev Modifier to make a function callable only when the contract is not paused.
    */
    modifier whenNotPaused() {
        require(!paused);
        _;
    }

    /**
    * @dev Modifier to make a function callable only when the contract is paused.
    */
    modifier whenPaused() {
        require(paused);
        _;
    }

    /**
    * @dev called by the owner to pause, triggers stopped state
    */
    function pause() onlyOwner whenNotPaused public {
        paused = true;
        emit Pause();
    }

    /**
    * @dev called by the owner to unpause, returns to normal state
    */
    function unpause() onlyOwner whenPaused public {
        paused = false;
        emit Unpause();
    }
}

//ERC20 Token interface
contract ContractToken {
    function transfer(address to, uint256 value) public returns (bool);
    function balanceOf(address user) public returns (uint256);
}

/**
 * @title FundForwardContract used for forwarding ETH and token from UserWallet to exchange wallet
 */
contract FundForwardContract {    
    Wallet wallet;
    event FundForwarded(address contractToken, address from, address to, uint amount);
    
    constructor(address _wallet) public {
        wallet = Wallet(_wallet);
    }
    
    /**
     * @dev Throws if called by any account other than fund forwarder.
     */
    modifier onlyFundForwarder() {
        require(msg.sender == wallet.fundForwarder());
        _;
    }
    /**
     * @dev Throws if wallet is not running.
     */    
    modifier walletRunning() {
        require(wallet.paused() == false);
        _;
    }
    /**
     * @notice Forward assets from userWallets to fundDestination
     * @dev only forwarder from wallet has the right to call this function
     */
    function forward(address _id)
    onlyFundForwarder
    walletRunning
    public 
    returns (bool success) {
        success = false;
        address destination = wallet.fundDestination();
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
            success = destination.transfer(amount);
        }
        
        if (success) {
            emit FundForwarded(_id, this, destination, amount);
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

// Generate new address for user
// The new address can be used for ETH and other ERC20 Token
contract Generator is Ownable{
    event LogAddress(address _address);
    
    // new wallet is created only if it was called by the owner,
    function generate(address vendor) 
    onlyOwner
    public
    returns (address newAddress) {
        newAddress = address(new UserWallet(vendor));
        emit LogAddress(newAddress);
    }
}

/**
 * @title Wallet contract
 * fundforwarder who has the right to move fund to main wallet
 * update forwarder contract for new contract tokens
 */
 
contract Wallet is Pausable {
    address public fundDestination; // default address keep ETH and token
    address public fundForwarder; // default address has the right to call forward on UserWallet
    address public defaultForwardContract = address(new FundForwardContract(this));
    mapping(address => address) forwardContracts;

    constructor(address _fundForwarder) public {
        fundDestination = msg.sender;
        fundForwarder = _fundForwarder;
    }
    
    function changeFundDestination(address _fundDestination) onlyOwner public {
        fundDestination = _fundDestination;
    }

    function changeFundForwarder(address _fundForwarder) onlyOwner public {
        fundForwarder = _fundForwarder;
    }
    
    /**
     * @notice Allow FundForwardContract customization for individual token
     * @dev only owner can call this function
     */    
    function changeForwardContract(address _token, address _address) onlyOwner public {
        forwardContracts[_token] = _address;
    }
    
    /**
     * @notice Allow FundForwardContract customization for individual token
     * @dev only owner can call this function
     */        
    function getForwardContract(address _token) public returns (address res) {
        res = forwardContracts[_token];
        if (res == 0) res = defaultForwardContract;
    }
    
}
