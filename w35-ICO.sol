pragma solidity ^0.4.18;

library SafeMath {
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0) {
      return 0;
    }
    uint256 c = a * b;
    assert(c / a == b);
    return c;
  }
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}

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

interface TokenContract {
    function transfer(address _recipient, uint256 _amount) public returns (bool);
    function balanceOf(address _holder) public view returns (uint256);
}

contract CrowdSale is Ownable {
    using SafeMath for uint256;
    
    TokenContract private tkn;
    address private walletAddress;
    uint256[7] private pricePerWave =  [2370, 2212, 2054, 1896, 1817, 1738, 1659];
    uint256[7] private weisPerWave = [1888 * 1 ether, 5888 * 1 ether, 9888 * 1 ether, 
                                    13888 * 1 ether, 17888 * 1 ether, 21888 * 1 ether,
                                    25888 * 1 ether];
    uint8 private currentWave = 0;
    address[] public preIcoInvestors;
    address[] public secondWaveInvestors;
    address private preIcoWallet;
    uint256 public icoStartTime;
    uint256 public icoEndTime;
    uint256 private extendedTime;
    bool private icoExtended = false;
    bool private icoPaused = false;
    bool private icoFinished = false;
    bool private softCapReached = false;
    uint256 public amountWeiRaised;
    uint256 public tokensSold;
    uint256 private refundPrice;
    uint256 public minInvestment = 100 finney;
    uint256 public maxInvestment = 1500 ether;

    struct Invested {
        uint256 amountToken;
        uint256 amountWei;
    }

    mapping(address => Invested) private investors;

    modifier icoIsFinished {
        require(!validPurchase());
        _;
    }

    modifier refunding() {
        require(!validPurchase() && !softCapReached);
        _;
    }

    modifier migrators() {
        require(msg.sender == owner || msg.sender == walletAddress);
        _;
    }

    modifier notPaused() {
        require(!icoPaused);
        _;
    }

    function pauseIco(bool _paused) onlyOwner external {
        icoPaused = _paused;
    }


    function getStatus() onlyOwner external returns (bool, bool, bool, bool, uint8, uint256, uint256, address) {
        return (icoPaused, icoExtended, !validPurchase(), softCapReached, currentWave, refundPrice, extendedTime, preIcoWallet);
    }
    
    function CrowdSale() public {
        tkn = TokenContract(0x0 );               // set the address
        icoStartTime = now; // here the start time
        icoEndTime = icoStartTime + (90 * 1 days);  
        walletAddress = msg.sender;
        preIcoWallet = msg.sender;
        refundPrice = 0;      // set the default that u want
    }

    // added max of wei in price
    function setRefundPrice(uint256 priceInWei) onlyOwner external {
        require(priceInWei < (1250 szabo));  // = 1.25 finney
        refundPrice = priceInWei;
    }

    function sendFundsToWallet() icoIsFinished onlyOwner external {
        walletAddress.transfer(this.balance);
    }

    function setPreIcoWallet(address _preIcoWallet) onlyOwner external {
        require(_preIcoWallet != address(0));
        preIcoWallet = _preIcoWallet;
    }

    function setExtendedTime(uint8 _timeInDays) onlyOwner external {
        extendedTime = _timeInDays;
    }

    function setWallet(address _walletAddress) onlyOwner external {
        require(_walletAddress != address(0));
        walletAddress = walletAddress;
    }

    function makeRefund(address _toWho, uint256 _amount) private {
        uint256 amount;
        if (_amount > refundPrice) {
            amount = _amount.sub(refundPrice);
            investors[_toWho].amountWei = 0;
            if (this.balance > amount) {
                _toWho.transfer(amount);
            }
        }
    }

    function refundToAll() refunding onlyOwner external {
        uint256 amount = 1;
        for (uint256 i = 0; i < secondWaveInvestors.length; i++) {
           amount = investors[secondWaveInvestors[i]].amountWei;
            if ((amount > refundPrice) ) {
            amountWeiRaised = amountWeiRaised.sub(amount);
            makeRefund(secondWaveInvestors[i], amount);
            } 
        }   
    }

    function emergencyMigration() onlyOwner external {
        uint256 actualTokenBalance;
        actualTokenBalance = tkn.balanceOf(this);    
        walletAddress.transfer(this.balance);
        sendTokens(walletAddress, actualTokenBalance);
    }

    // clean de blockchain and get the gas
    function terminateContract() onlyOwner icoIsFinished external {
        selfdestruct(walletAddress);
    }

    // check if the period is ok and extend ICO if needed
    function validPurchase() internal returns (bool) {
        bool withinPeriod = now >= icoStartTime && now <= icoEndTime;
        if (icoFinished) {return false;}
        if (withinPeriod) {
            return true;
        } else {
            if (icoExtended) {
                icoFinished = true;
                return false;
            } else {
                icoEndTime += (extendedTime * 1 days);
                icoExtended = true;
                return true;
            }
        }
    }

    function sendTokens(address _investor, uint256 _tokensToSend) private {
        // with a require to ensure that the tokens where sent
        require(tkn.transfer(_investor, _tokensToSend));                 
    }

    // determine if the invested ammount need to be split in 2 waves
    function executeSell(address _investor, uint256 _investedWei) private {
        uint256 tokensToBuy;
       if ((_investedWei + amountWeiRaised) > (weisPerWave[currentWave])) {
            multiWaveSell(_investor, _investedWei);
        } else {
            tokensToBuy = pricePerWave[currentWave].mul(_investedWei);
            singleWaveSell(_investor, _investedWei, tokensToBuy);
        }
    }

    function singleWaveSell(address _investor, uint256 _investedWei, uint256 _tokensToBuy) private {
        investors[_investor].amountToken = investors[_investor].amountToken.add(_tokensToBuy);
        if (currentWave > 0) {
            investors[_investor].amountWei = investors[_investor].amountWei.add(_investedWei);
            }
        amountWeiRaised = amountWeiRaised.add(_investedWei);
        tokensSold = tokensSold.add(_tokensToBuy); 
        NewInvestment(_investor, _investedWei, currentWave); 
        if (!softCapReached) {
            preSoftCapSell(_investor, _investedWei);
           }  
        sendTokens(_investor, _tokensToBuy);
    }

    function multiWaveSell(address _investor, uint256 _investedWei) private {
        uint256 sellFromCurrent;
        uint256 sellFromNext;
        uint256 returnToInvestor;
        uint256 tokensToBuy;
        if (currentWave == 6) {
            sellFromCurrent = (weisPerWave[6]).sub(amountWeiRaised);
            returnToInvestor = _investedWei.sub(sellFromCurrent);
            tokensToBuy = pricePerWave[currentWave].mul(sellFromCurrent);
            singleWaveSell(_investor, sellFromCurrent, tokensToBuy);
            _investor.transfer(returnToInvestor);
            icoFinished = true;
        }   else {
            sellFromCurrent = (weisPerWave[currentWave]).sub(amountWeiRaised);
            sellFromNext = _investedWei.sub(sellFromCurrent);
            tokensToBuy = pricePerWave[currentWave].mul(sellFromCurrent);
            singleWaveSell(_investor, sellFromCurrent, tokensToBuy);
            currentWave += 1;
            if (currentWave > 1) {softCapReached = true;}
            tokensToBuy = pricePerWave[currentWave].mul(sellFromNext);
            singleWaveSell(_investor, sellFromNext, tokensToBuy);
        } 
    }

    function preSoftCapSell(address _investor, uint256  _investedWei) private {
        if (currentWave == 0) {
            preIcoInvestors.push(_investor);
            if (_investedWei <= this.balance) {
                 preIcoWallet.transfer(_investedWei);
            }
        } else {
            secondWaveInvestors.push(_investor);
        }
    }

    function getRefund() refunding external returns (bool) {
        address toWho = msg.sender;
        uint256 amount = investors[toWho].amountWei;
        if (amount > refundPrice) {
            makeRefund(toWho, amount);
            amountWeiRaised = amountWeiRaised.sub(amount);
            return true;
        } else {return false;}
    }

    function () payable notPaused public {
        require((msg.value > minInvestment) && (msg.value < maxInvestment));
        require(validPurchase());
        executeSell(msg.sender, msg.value);
    }

    event NewInvestment(address indexed tknInvestor, uint256 amount, uint256 wave);

}
