pragma solidity ^0.4.18;

interface token {
    function transfer(address receiver, uint amount) public;
}

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

contract CrowdSale is Ownable {
    using SafeMath for uint256;

    // here goes the tokens contract address
    token public tokenAddress;
    // address where the funds will be transfered when ICO ends, set to owner in constructor
    address private walletAddress;
    uint16[7] private pricePerWave =  [2370, 2212, 2054, 1896, 1817, 1738, 1659];
    uint32[7] private tokensPerWave = [4474560, 13322560, 21538560, 29122560, 36390560, 43342560, 49978560];
    uint256[7] private weisPerWave = [1888000000000000000000, 5888000000000000000000, 9888000000000000000000, 
                                    13888000000000000000000, 17888000000000000000000, 21888000000000000000000,
                                    25888000000000000000000];
    uint8 private currentWave = 0;
    address[] public preIcoInvestors;
    address[] public secondWaveInvestors;

    uint256 public icoStartTime;
    uint256 public icoEndTime;
    bool private icoExtended = false;
    bool private icoPaused = false;
    bool private icoFinished = false;
    bool private softCapReached = false;
    uint256 amountWeiRised;
    uint256 tokensSold;
    uint256 refundPrice;

    struct Invested {
        uint256 amountToken;
        uint256 amountWei;
        uint256 amountUnsent;
        uint256 amountWeiPreIco;
    }

    mapping(address => Invested) investors;

    modifier icoIsFinished {
        require(icoFinished);
        _;
    }

    modifier icoIsLive {
        require(!icoFinished);
        _;
    }

   modifier onlyPayloadSize(uint size) {
        assert(msg.data.length >= size + 4);
        _;
   }

   modifier refunding(){
       require(icoFinished && !softCapReached);
       _;
   }

   modifier notPaused() {
       require(!icoPaused);
       _;
   }

   function pauseIco() onlyOwner public {
       icoPaused = true;
   }

   function unPauseIco() onlyOwner public {
       icoPaused = false;
   }

    function CrowdSale() public {

        // here the start time of the ICO in unix EPOCH format
        icoStartTime = 1519481796;
        icoEndTime = icoStartTime + (90 * 1 days);
        walletAddress = msg.sender;
        refundPrice = 2000000;

    }

    // set the "comision" price for the refunds (gas expenses), must be set in WEI
    // use ethgasstation to see the safe price
    function setRefundPrice(uint256 priceInWei) onlyOwner public {
        refundPrice = priceInWei;
    }

    // check if the period is ok and extend ICO if needed
    function validPurchase() internal returns (bool) {
        bool withinPeriod = now >= icoStartTime && now <= icoEndTime;
        if (withinPeriod) {
            return true;
        } else {
            if (icoExtended) {
                icoFinished = true;
                return false;
            } else {
                icoEndTime += (21 * 1 days);
                icoExtended = true;
            }
        }
    }

    function sendFundsToWallet() icoIsFinished onlyOwner public {
        walletAddress.transfer(amountWeiRised);
    }

    function sendTokens(address _investor, uint256 _tokensToSend) private {
        tokenAddress.transfer(_investor, _tokensToSend);
    }

    // determine if the invested ammount need to be split in 2 waves
    function executeSell(address _investor, uint256 _investedWei) private {
        uint256 tokensToBuy = pricePerWave[currentWave] * _investedWei;
        if ((tokensToBuy + tokensSold) > tokensPerWave[currentWave]) {
            multiWaveSell(_investor, _investedWei);
        } else {
            singleWaveSell(_investor, _investedWei, tokensToBuy);
        }
    }

    // update the variables used to refund and token post-delivery
    function preSoftCapSell(address _investor, uint256 _investedWei, uint256 _tokens) private {
        if (currentWave == 0) {
            investors[_investor].amountWeiPreIco.add(_investedWei);
            investors[_investor].amountUnsent.add(_tokens);   
            preIcoInvestors.push(_investor);         
        } else {
            investors[_investor].amountUnsent.add(_tokens);
            secondWaveInvestors.push(_investor);
        }
    }

    // post - send functions  >>> separated to prevent failure 
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

    // sell from 1 single wave
    function singleWaveSell(address _investor, uint256 _investedWei, uint256 _tokensToBuy) private {
        investors[_investor].amountToken.add(_tokensToBuy);
        investors[_investor].amountWei.add(_investedWei);
        amountWeiRised.add(_investedWei);
        tokensSold.add(_tokensToBuy);
        NewInvestment(_investor, _investedWei);
        if (!softCapReached) {
            preSoftCapSell(_investor, _investedWei, _tokensToBuy);
            } else {sendTokens(_investor, _tokensToBuy);}
        
    }

    // separate the imvested amount in waves
    function multiWaveSell(address _investor, uint256 _investedWei) private {
        uint256 sellFromCurrent;
        uint256 sellFromNext;
        uint256 returnToInvestor;
        uint256 tokensToBuy;
        if (currentWave == 6) {
            sellFromCurrent = weisPerWave[6] - amountWeiRised;
            returnToInvestor = _investedWei - sellFromCurrent;
            tokensToBuy = pricePerWave[currentWave] * sellFromCurrent;
            singleWaveSell(_investor, sellFromCurrent, tokensToBuy);
            _investor.transfer(returnToInvestor);
            icoFinished = true;
        } else {
            sellFromCurrent = weisPerWave[currentWave] - amountWeiRised;
            sellFromNext = _investedWei - sellFromCurrent;
            tokensToBuy = pricePerWave[currentWave] * sellFromCurrent;
            singleWaveSell(_investor, sellFromCurrent, tokensToBuy);

            currentWave += 1;
            if (currentWave > 1) {softCapReached = true;}
            tokensToBuy = pricePerWave[currentWave] * sellFromNext;
            singleWaveSell(_investor, sellFromNext, tokensToBuy);

        }
    }
    
    // fallback
    function () onlyPayloadSize(2 * 32) icoIsLive notPaused payable public {
        require(validPurchase());
        require(msg.value > 0);
        executeSell(msg.sender, msg.value);
    }

    // set withdraw wallet
    function setWallet(address _walletAddress) onlyOwner public {
        require(_walletAddress != address(0));
        walletAddress = walletAddress;
    }

    // refund to who call the function, this adds confidence to the investor
    function getRefund() refunding public {
        address toWho = msg.sender;
        uint256 amount = investors[toWho].amountWei - investors[toWho].amountWeiPreIco;
        makeRefund(toWho, amount, true);
    }


    // manual refund of pre-ico
    function refundPreIco(address _toWho, uint256 _amount) refunding onlyOwner public {
        address toWho = _toWho;
        uint256 available = investors[toWho].amountWeiPreIco;
        require(_amount < available);
        makeRefund(toWho, _amount, false);
    }

    // execute the refunds
    function makeRefund(address _toWho, uint256 _amount, bool _toZero) private {
        require((_amount - refundPrice) > 0);
        uint256 amount;
        address toWho;
        toWho = _toWho;
        amount = _amount - refundPrice;
        if (_toZero) {investors[toWho].amountWei = 0;}
        toWho.transfer(amount);
    }


    // refund to all investors auto
    function refundToAll() refunding onlyOwner public {
        uint256 amount;
        for (uint256 i = 0; i < secondWaveInvestors.length; i++) {
           amount = investors[secondWaveInvestors[i]].amountWei - investors[secondWaveInvestors[i]].amountWeiPreIco;
            if ((amount-refundPrice) > 0) {
                makeRefund(secondWaveInvestors[i], amount, true);
            }
        }   
    }

    // in case of any emergency as you said, can migrate to another contract
    // this function forwards the ether and the details of unsent tokens
    // via events, so you can use a dapp to catch the info
    // the ether invested in wei is already emited in a event

    function emergencyMigration() onlyOwner public {
        uint256 i;
        walletAddress.transfer(this.balance);
        if (!softCapReached) {
            for (i = 0; i < preIcoInvestors.length; i++) {
                UnsentBalance(preIcoInvestors[i], investors[preIcoInvestors[i]].amountUnsent);
            }
            for (i = 0; i < secondWaveInvestors.length; i++) {
                UnsentBalance(secondWaveInvestors[i], investors[secondWaveInvestors[i]].amountUnsent);
            }
        }
    }

    function terminateContract() onlyOwner icoIsFinished public {
        selfdestruct(walletAddress);
    }


    event UnsentBalance(address indexed investor, uint256 amount);
    event NewInvestment(address indexed investor, uint256 amount);

}
