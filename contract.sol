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

/**
 * @title ContractToken
 * ERC20 Contract Interfaces
 */
contract ContractToken {
    function transfer(address to, uint256 value) public returns (bool);
    function balanceOf(address user) public returns (uint256);
}

/**
 * @title FundForwardContract 
 * for forwarding ETH and token from UserWallet to exchange wallet
 */
contract FundForwardContract {
    Wallet wallet;
    event FundForwarded(address contractToken, address from, address to, uint amount);
    
    /**
     * @dev The constructor links this instance to the main wallet
     */
    constructor(address _wallet) public {
        wallet = Wallet(_wallet);
    }
    
    /**
     * @dev Throws if called by any account other than wallet.fundForwarder
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
     * @notice Forward assets from user address to fundDestination
     * @dev only wallet.fundForwarder from wallet has the right to call this function
     * @param _id ERC20 contract address
     */
    function forward(address _id)
    onlyFundForwarder
    walletRunning
    public 
    returns (bool) {
        address destination = wallet.fundDestination();
        uint amount;

        // default address 0x000...00 for transfer ETH
        // otherwise, load contract token and call transfer method
        // transfer all available ETH / (_id) token to exchange wallet
        if (_id != address(0)) {
            ContractToken token = ContractToken(_id);
            amount = token.balanceOf(this);
            require(amount > 0);
            token.transfer(destination, amount);
        } else {
            amount = address(this).balance;
            require(amount > 0);
            destination.transfer(amount);
        }
        emit FundForwarded(_id, this, destination, amount);
        return true;
    }
}

/**
 * @title User Wallet 
 * individual user address which receives external funding
 * The fund will then be forwarded to exchange settlement address using FundForwardContract delegation
 */
contract UserWallet {
    Wallet wallet;
    
    /**
     * @dev The constructor links this instance to the main wallet
     */
    constructor(address _wallet) public {
        wallet = Wallet(_wallet);
    }
    
    modifier onlyFundForwarder() {
        require(msg.sender == wallet.fundForwarder());
        _;
    }

    /**
     * @dev Allow this contract to receive ETH
     */
    function () public payable { }

    /**
     * @dev Allow this contract to receive token
     */    
    function tokenFallback(address _from, uint _value, bytes _data) public {
        (_from);
        (_value);
        (_data);
    }

    /**
     * @notice Delegate asset forwarding to FundForwardContract
     * @dev only wallet fundForwarder has the right to call forward
     * @param _id ERC20 contract address  
     */
    function forward(address _id) 
    onlyFundForwarder
    public
    returns (bool) {
        // give the fundforwarder the right to transfer token/ETH out of this address
        return wallet.getForwardContract(_id).delegatecall(msg.data);
    }
}


/**
 * @title UserWalletGenerator
 * Generate new address for user. The address can be used for ETH and other ERC20 Token
 */
contract UserWalletGenerator is Ownable {
    event LogAddress(address _address);
    
    // new wallet is created only if it was called by the owner,
    /**
     * @notice Generate user address
     * @param wallet the wallet to generate UserWallet for 
     */    
    function generate(address wallet) 
    onlyOwner
    public
    returns (address newAddress) {
        newAddress = address(new UserWallet(wallet));
        emit LogAddress(newAddress);
    }
}

/**
 * @title Wallet contract
 * manages fundDestination which receives funds from user wallets
 * manages fundForwarder which forwards funds from user wallets to fundDestination
 * manages forwardContracts which determines which contract to use for each token
 */
contract Wallet is Pausable {
    address public fundDestination; // default address keep ETH and token
    address public fundForwarder; // default address has the right to call forward on UserWallet
    address public defaultForwardContract = address(new FundForwardContract(this));
    mapping(address => address) forwardContracts;

    /**
     * @dev The constructor allows specifying the fundForwarder for this Wallet
     */
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
    function getForwardContract(address _token) public view returns (address res) {
        res = forwardContracts[_token];
        if (res == 0) res = defaultForwardContract;
    }
}
