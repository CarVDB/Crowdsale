pragma solidity ^0.4.18;

contract Ownable {
  address public owner;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  function Ownable() public {
    owner = msg.sender;
  }
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }
  function transferOwnership(address newOwner) public onlyOwner {
    require(newOwner != address(0));
    OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }

}


contract Stats is Ownable {
    bool public isPaused;
    bool public isExtended;
    bool public finished;
    bool public softcapReached;
    uint8 public currentWave;
    uint256 public refundPrice;
    uint256 public extendedTime;
    address public preIcoWallet;
    address public defaultWallet;
    address public icoContract;

  modifier onlyContract() {
    require(msg.sender == icoContract);
    _;
  }

  function monitor(bool _isPaused, bool _isExtended, bool _finished, bool _softCapReached, 
                  uint8 _currentWave, uint256 _refundPrice, uint256 _extendedTime, 
                  address _preIcoWallet, address _defaultWallet) onlyContract public 
                  {
      isPaused = _isPaused;
      isExtended = _isExtended;
      finished = _finished;
      softcapReached = _softCapReached;
      currentWave = _currentWave;
      refundPrice = _refundPrice;
      extendedTime = _extendedTime;
      preIcoWallet = _preIcoWallet;
      defaultWallet = _defaultWallet;
  }

  function terminateContract() onlyOwner external {
      selfdestruct(owner);
  }

  function setIcoContract(address _icoContract) onlyOwner external {
    icoContract = _icoContract;
  }

}
