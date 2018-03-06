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
    function transfer(address _recipient, uint256 _amount) external returns (bool);
    function balanceOf(address _holder) external view returns (uint256);
}

contract CrowdSale is Ownable {
    using SafeMath for uint256;
    
    TokenContract private tkn;
    address public tokenAddress;
    address private walletAddress;
    uint256[7] private pricePerWave =  [2370, 2212, 2054, 1896, 1817, 1738, 1659];
    uint256[7] private tokensPerWave = [4474560000000000000000000, 13322560000000000000000000, 21538560000000000000000000,
                                        29122560000000000000000000, 36390560000000000000000000, 43342560000000000000000000,
                                        49978560000000000000000000];
    uint256[7] private weisPerWave = [1888000000000000000000, 5888000000000000000000, 9888000000000000000000, 
                                    13888000000000000000000, 17888000000000000000000, 21888000000000000000000,
                                    25888000000000000000000];
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
    uint256 public amountWeiRised;
    uint256 public tokensSold;
    uint256 private refundPrice;

    struct Invested {
        uint256 amountToken;
        uint256 amountWei;
        uint256 amountUnsent;
    }

    mapping(address => Invested) investors;

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

    function pauseIco() onlyOwner public {
        icoPaused = !icoPaused;
    }

    function getStatus() onlyOwner public returns (bool, bool, bool, bool, uint8, uint256, uint256, address) {
        return (icoPaused, icoExtended, !validPurchase(), softCapReached, currentWave, refundPrice, extendedTime, preIcoWallet);
    }
    
    function CrowdSale(address _tokenAddress) public {
        tokenAddress = _tokenAddress;            
        tkn = TokenContract(0xf1C7F8d79FD01cF16eF819B4A932E002f286F5d4);               
        icoStartTime = now;  // set the time !!!!!!!!!!!!!!!!!!!!
        icoEndTime = icoStartTime + (90 * 1 days);  
        walletAddress = msg.sender;
        preIcoWallet = msg.sender;
        refundPrice = 2000000;
        extendedTime = 21;         
    }


    function setRefundPrice(uint256 priceInWei) onlyOwner public {
        refundPrice = priceInWei;
    }

    function sendFundsToWallet() icoIsFinished onlyOwner public {
        walletAddress.transfer(this.balance);
    }

    function setPreIcoWallet(address _preIcoWallet) onlyOwner public {
        require(_preIcoWallet != address(0));
        preIcoWallet = _preIcoWallet;
    }

    function setExtendedTime(uint8 _timeInDays) onlyOwner public {
        extendedTime = _timeInDays;
    }

    function setWallet(address _walletAddress) onlyOwner public {
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

    function refundToAll() refunding onlyOwner public {
        uint256 amount = 1;
        for (uint256 i = 0; i < secondWaveInvestors.length; i++) {
           amount = investors[secondWaveInvestors[i]].amountWei;
            if ((amount > refundPrice) ) {
            amountWeiRised = amountWeiRised.sub(amount);
            makeRefund(secondWaveInvestors[i], amount);
            } 
        }   
    }

    function emergencyMigration() onlyOwner public {
        uint256 actualTokenBalance;
        actualTokenBalance = tkn.balanceOf(this);    
        walletAddress.transfer(this.balance);
        sendTokens(walletAddress, actualTokenBalance);
    }

    // clean de blockchain and get the gas
    function terminateContract() onlyOwner icoIsFinished public {
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
       if ((_investedWei + amountWeiRised) > (weisPerWave[currentWave])) {
            multiWaveSell(_investor, _investedWei);
        } else {
            tokensToBuy = pricePerWave[currentWave].mul(_investedWei);
            singleWaveSell(_investor, _investedWei, tokensToBuy);
        }
    }

    function singleWaveSell(address _investor, uint256 _investedWei, uint256 _tokensToBuy) private {
        investors[_investor].amountToken = investors[_investor].amountToken.add(_tokensToBuy);
        if (currentWave > 0) {investors[_investor].amountWei = investors[_investor].amountWei.add(_investedWei);}
        amountWeiRised = amountWeiRised.add(_investedWei);
        tokensSold = tokensSold.add(_tokensToBuy); 
        NewInvestment(_investor, _investor, _investedWei, currentWave); 
        if (!softCapReached) {
            preSoftCapSell(_investor, _tokensToBuy, _investedWei);
           // sendTokens(_investor, _tokensToBuy);
            }  else {sendTokens(_investor, _tokensToBuy);} 
    }

    function multiWaveSell(address _investor, uint256 _investedWei) private {
        uint256 sellFromCurrent;
        uint256 sellFromNext;
        uint256 returnToInvestor;
        uint256 tokensToBuy;
        if (currentWave == 6) {
            sellFromCurrent = (weisPerWave[6]).sub(amountWeiRised);
            returnToInvestor = _investedWei.sub(sellFromCurrent);
            tokensToBuy = pricePerWave[currentWave].mul(sellFromCurrent);
            singleWaveSell(_investor, sellFromCurrent, tokensToBuy);
            _investor.transfer(returnToInvestor);
            icoFinished = true;
        }   else {
            sellFromCurrent = (weisPerWave[currentWave]).sub(amountWeiRised);
            sellFromNext = _investedWei.sub(sellFromCurrent);
            tokensToBuy = pricePerWave[currentWave].mul(sellFromCurrent);
            singleWaveSell(_investor, sellFromCurrent, tokensToBuy);
            currentWave += 1;
            if (currentWave > 1) {softCapReached = true;}
            tokensToBuy = pricePerWave[currentWave].mul(sellFromNext);
            singleWaveSell(_investor, sellFromNext, tokensToBuy);
        } 
    }

    function preSoftCapSell(address _investor, uint256 _tokens,uint256  _investedWei) private {
        if (currentWave == 0) {
            investors[_investor].amountUnsent = investors[_investor].amountUnsent.add(_tokens);   
            preIcoInvestors.push(_investor);
            if (_investedWei <= this.balance) {
                 preIcoWallet.transfer(_investedWei);
            }

        } else {
            investors[_investor].amountUnsent = investors[_investor].amountUnsent.add(_tokens);
            secondWaveInvestors.push(_investor);
        }
    }

    function sendPreICO() onlyOwner public {
        uint256 tokensToSend;
        for (uint256 i = 0; i < preIcoInvestors.length; i++) {
            tokensToSend = investors[preIcoInvestors[i]].amountUnsent;
            investors[preIcoInvestors[i]].amountUnsent = 0;
            if (tokensToSend > 0) {sendTokens(preIcoInvestors[i], tokensToSend);}
        }  
    }

    function sendSecondWave() onlyOwner public {
        uint256 tokensToSend;
        for (uint256 i = 0; i < secondWaveInvestors.length; i++) {
            tokensToSend = investors[secondWaveInvestors[i]].amountUnsent;
            investors[secondWaveInvestors[i]].amountUnsent = 0;
            if (tokensToSend > 0) {sendTokens(secondWaveInvestors[i], tokensToSend);}
        }  
    }

    function getRefund() refunding public returns (bool) {
        address toWho = msg.sender;
        uint256 amount = investors[toWho].amountWei;
        if (amount > refundPrice) {
            makeRefund(toWho, amount);
            amountWeiRised = amountWeiRised.sub(amount);
            return true;
        } else {return false;}
    }

    function () payable notPaused public {
        require(validPurchase());
        require(msg.value > 0);
        executeSell(msg.sender, msg.value);
    }

    event NewInvestment(address indexed tknInvestor, address adddressInvestor, uint256 amount, uint256 wave);
    event TokensSent(bool tokensSent);

}
