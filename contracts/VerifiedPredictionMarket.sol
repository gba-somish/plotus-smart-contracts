pragma solidity 0.5.7;

import "./external/openzeppelin-solidity/math/SafeMath.sol";
import "./external/oraclize/ethereum-api/usingOraclize.sol";
import "./config/MarketConfig.sol";
import "./interface/IChainLinkOracle.sol";
import "https://github.com/starkware-libs/veedo/blob/master/contracts/BeaconContract.sol";


contract Beacon{
    
    function getLatestRandomness()external view returns(uint256,bytes32){}
    
}


contract IPlotus {

    enum MarketType {
      HourlyMarket,
      DailyMarket,
      WeeklyMarket
    }
    address public owner;
    function() external payable{}
    function callPlacePredictionEvent(address _user,uint _value, uint _predictionPoints, uint _prediction,uint _leverage) public{
    }
    function callClaimedEvent(address _user , uint _reward, uint _stake) public {
    }
    function callMarketResultEvent(uint _commision, uint _donation, uint _totalReward, uint winningOption) public {
    }
}

contract Market is usingOraclize {
    using SafeMath for uint;

    enum PredictionStatus {
      Started,
      Closed,
      ResultDeclared
    }
    
  
    uint internal startTime;
    uint internal expireTime;
    string internal FeedSource;
    uint public rate;
    uint public minBet;
    uint public WinningOption;
    bytes32 internal marketResultId;
    uint public rewardToDistribute;
    PredictionStatus internal predictionStatus;
    uint internal predictionForDate;
    
    mapping(address => mapping(uint => uint)) public ethStaked;
    mapping(address => mapping(uint => uint)) internal LeverageEth;
    mapping(address => mapping(uint => uint)) public userPredictionPoints;
    mapping(address => bool) internal userClaimedReward;

    IPlotus internal pl;
    MarketConfig internal marketConfig;
    
    struct option
    {
      uint minValue;
      uint maxValue;
      uint predictionPoints;
      uint ethStaked;
      uint ethLeveraged;
      address[] stakers;
    }

    mapping(uint=>option) public optionsAvailable;

    IChainLinkOracle internal chainLinkOracle;

    modifier OnlyOwner() {
      require(msg.sender == pl.owner() || msg.sender == address(pl));
      _;
    }
    
    function setBeaconContractAddress(address _address) public  {
        BeaconContractAddress=_address;
    }
    
     address public BeaconContractAddress=0x79474439753C7c70011C3b00e06e559378bAD040;
    
    function generateRandomNumber() public view returns(bytes32){
        uint blockNumber;
        bytes32 randomNumber;
        Beacon beacon=Beacon(BeaconContractAddress);
        (blockNumber,randomNumber)=beacon.getLatestRandomness();
        return randomNumber;
       
    }

    function initiate(uint[] memory _uintparams,string memory _feedsource,address marketConfigs) public {
      pl = IPlotus(msg.sender);
      marketConfig = MarketConfig(marketConfigs);
      startTime = _uintparams[0];
      FeedSource = _feedsource;
      predictionForDate = _uintparams[1];
      rate = _uintparams[2];
      // optionsAvailable[0] = option(0,0,0,0,0,address(0));
      (uint predictionTime, , , , , ) = marketConfig.getPriceCalculationParams();
      expireTime = startTime + predictionTime;
      require(expireTime > now);
      setOptionRanges(_uintparams[3],_uintparams[4]);
      marketResultId = oraclize_query(predictionForDate, "URL", "json(https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT).price");
      chainLinkOracle = IChainLinkOracle(marketConfig.getChainLinkPriceOracle());
    }

    function () external payable {
      revert("Can be deposited only through placePrediction");
    }

    function marketStatus() internal view returns(PredictionStatus){
      if(predictionStatus == PredictionStatus.Started && now >= expireTime) {
        return PredictionStatus.Closed;
      }
        return predictionStatus;
    }
  
    function _calculateOptionPrice(uint _option, uint _totalStaked, uint _ethStakedOnOption) internal view returns(uint _optionPrice) {
      _optionPrice = 0;
      uint currentPriceOption = 0;
      (uint predictionTime,uint optionStartIndex,uint stakeWeightage,uint stakeWeightageMinAmount,uint predictionWeightage,uint minTimeElapsed) = marketConfig.getPriceCalculationParams();
      if(now > expireTime) {
        return 0;
      }
      if(_totalStaked > stakeWeightageMinAmount) {
        _optionPrice = (_ethStakedOnOption).mul(1000000).div(_totalStaked.mul(stakeWeightage));
      }
      uint currentPrice = uint(chainLinkOracle.latestAnswer()).div(10**8);
      uint maxDistance;
      
      (, bytes32 random) = getLatestRandomness();
      uint ran  = uint(random).mod(subscribers.length.sub(winners.length));
      
      if(currentPrice < optionsAvailable[2].minValue + ran ) {
        currentPriceOption = 1;
        maxDistance = 2;
      } else if(currentPrice > optionsAvailable[2].maxValue + ran) {
        currentPriceOption = 3;
        maxDistance = 2;
      } else {
        currentPriceOption = 2;
        maxDistance = 1;
      }
        //  for(uint i=1;i <= _totalOptions;i++){
        // if(currentPrice <= optionsAvailable[i].maxValue && currentPrice >= optionsAvailable[i].minValue){
        //   currentPriceOption = i;
        // }
        // }    
      uint distance = currentPriceOption > _option ? currentPriceOption.sub(_option) : _option.sub(currentPriceOption);
      // uint maxDistance = currentPriceOption > (_totalOptions.div(2))? (currentPriceOption.sub(optionStartIndex)): (_totalOptions.sub(currentPriceOption));
      // uint maxDistance = 7 - (_option > distance ? _option - distance: _option + distance);
      uint timeElapsed = now > startTime ? now.sub(startTime) : 0;
      timeElapsed = timeElapsed > minTimeElapsed ? timeElapsed: minTimeElapsed;
      _optionPrice = _optionPrice.add((((maxDistance+1).sub(distance)).mul(1000000).mul(timeElapsed)).div((maxDistance+1).mul(predictionWeightage).mul(predictionTime)));
       _optionPrice = _optionPrice.div(100);
    }

    function setOptionRanges(uint _midRangeMin, uint _midRangeMax) internal{
     optionsAvailable[1].minValue = 0;
     optionsAvailable[1].maxValue = _midRangeMin.sub(1);
     optionsAvailable[2].minValue = _midRangeMin;
     optionsAvailable[2].maxValue = _midRangeMax;
     optionsAvailable[3].minValue = _midRangeMax.add(1);
     optionsAvailable[3].maxValue = ~uint256(0) ;
    }

    function _calculatePredictionValue(uint _prediction, uint _stake, uint _totalContribution, uint _priceStep, uint _leverage) internal view returns(uint _predictionValue) {
      uint value;
      uint flag = 0;
      uint _ethStakedOnOption = optionsAvailable[_prediction].ethStaked;
      _predictionValue = 0;
      while(_stake > 0) {
        if(_stake <= (_priceStep)) {
          value = (uint(_stake)).div(rate);
          _predictionValue = _predictionValue.add(value.mul(_leverage).div(_calculateOptionPrice(_prediction, _totalContribution, _ethStakedOnOption + flag.mul(_priceStep))));
          break;
        } else {
          _stake = _stake.sub(_priceStep);
          value = (uint(_priceStep)).div(rate);
          _predictionValue = _predictionValue.add(value.mul(_leverage).div(_calculateOptionPrice(_prediction, _totalContribution, _ethStakedOnOption + flag.mul(_priceStep))));
          _totalContribution = _totalContribution.add(_priceStep);
          flag++;
        }
      } 
    }

    function estimatePredictionValue(uint _prediction, uint _stake, uint _leverage) public view returns(uint _predictionValue){
      (, uint totalOptions, , , , , uint priceStep) = marketConfig.getBasicMarketDetails();
      return _calculatePredictionValue(_prediction, _stake, address(this).balance, priceStep, _leverage);
    }


    function getOptionPrice(uint _prediction) public view returns(uint) {
      (, uint totalOptions, , , , , ) = marketConfig.getBasicMarketDetails();
     return _calculateOptionPrice(_prediction, address(this).balance, optionsAvailable[_prediction].ethStaked);
    }

    function getData() public view returns
       (string memory _feedsource,uint[] memory minvalue,uint[] memory maxvalue,
        uint[] memory _optionPrice, uint[] memory _ethStaked,uint _predictionType,uint _expireTime, uint _predictionStatus){
        uint totalOptions;
        (_predictionType, totalOptions, , , , , ) = marketConfig.getBasicMarketDetails();
        _feedsource = FeedSource;
        _expireTime =expireTime;
        _predictionStatus = uint(marketStatus());
        minvalue = new uint[](3);
        maxvalue = new uint[](3);
        _optionPrice = new uint[](3);
        _ethStaked = new uint[](3);
        for (uint i = 0; i < 3; i++) {
        _ethStaked[i] = optionsAvailable[i+1].ethStaked;
        minvalue[i] = optionsAvailable[i+1].minValue;
        maxvalue[i] = optionsAvailable[i+1].maxValue;
        _optionPrice[i] = _calculateOptionPrice(i+1, address(this).balance, optionsAvailable[i+1].ethStaked);
       }
    }

    function getMarketResults() public view returns(uint256, uint256, uint256, address[] memory, uint256) {
      return (WinningOption, optionsAvailable[WinningOption].predictionPoints, rewardToDistribute, optionsAvailable[WinningOption].stakers, optionsAvailable[WinningOption].ethStaked);
    }

    function placePrediction(uint _prediction,uint _leverage) public payable {
      require(now >= startTime && now <= expireTime);
      (, ,uint minPrediction, , , , uint priceStep) = marketConfig.getBasicMarketDetails();
      require(msg.value >= minPrediction,"Min prediction amount required");
      minBet = minPrediction;
      uint optionPrice = _calculatePredictionValue(_prediction, msg.value, address(this).balance.sub(msg.value), priceStep, _leverage);
       // _calculateOptionPrice(_prediction, address(this).balance.sub(msg.value), msg.value);
      // uint optionPrice = getOptionPrice(_prediction); // need to fix getOptionPrice function.
      // uint predictionPoints = (((msg.value)).mul(_leverage)).div(optionPrice);
      uint predictionPoints = optionPrice;
      if(userPredictionPoints[msg.sender][_prediction] == 0) {
        optionsAvailable[_prediction].stakers.push(msg.sender);
      }
      userPredictionPoints[msg.sender][_prediction] = userPredictionPoints[msg.sender][_prediction].add(predictionPoints);
      ethStaked[msg.sender][_prediction] = ethStaked[msg.sender][_prediction].add(msg.value);
      LeverageEth[msg.sender][_prediction] = LeverageEth[msg.sender][_prediction].add(msg.value.mul(_leverage));
      optionsAvailable[_prediction].predictionPoints = optionsAvailable[_prediction].predictionPoints.add(predictionPoints);
      optionsAvailable[_prediction].ethStaked = optionsAvailable[_prediction].ethStaked.add(msg.value);
      optionsAvailable[_prediction].ethLeveraged = optionsAvailable[_prediction].ethLeveraged.add(msg.value.mul(_leverage));
      pl.callPlacePredictionEvent(msg.sender,msg.value, predictionPoints, _prediction, _leverage);
    }

    function calculatePredictionResult(uint _value) public {
      require(msg.sender == pl.owner() || msg.sender == oraclize_cbAddress());
      require(now >= predictionForDate,"Time not reached");
      require(_value > 0,"value should be greater than 0");
     (,uint totalOptions, , , ,uint lossPercentage, ) = marketConfig.getBasicMarketDetails();
      uint totalReward = 0;
      uint distanceFromWinningOption = 0;
      predictionStatus = PredictionStatus.ResultDeclared;
      
      (, bytes32 random) = getLatestRandomness();
      uint ran  = uint(random).mod(subscribers.length.sub(winners.length));
      
      if(_value < optionsAvailable[2].minValue + ran) {
        WinningOption = 1;
      } else if(_value > optionsAvailable[2].maxValue + ran ) {
        WinningOption = 3;
      } else {
        WinningOption = 2;
      }
      
      
      for(uint i=1;i <= totalOptions;i++){
       distanceFromWinningOption = i>WinningOption ? i.sub(WinningOption) : WinningOption.sub(i);    
       totalReward = totalReward.add((distanceFromWinningOption.mul(lossPercentage).mul(optionsAvailable[i].ethLeveraged)).div(100));
      }
      //Get donation, commission addresses and percentage
      (address payable donationAccount, uint donation, address payable commissionAccount, uint commission) = marketConfig.getFundDistributionParams();
       commission = commission.mul(totalReward).div(100);
       donation = donation.mul(totalReward).div(100);
       rewardToDistribute = totalReward.sub(commission).sub(donation);
       commissionAccount.transfer(commission);
       donationAccount.transfer(donation);
      if(optionsAvailable[WinningOption].ethStaked == 0){
       address(pl).transfer(rewardToDistribute);
      }

       pl.callMarketResultEvent(commission, donation, rewardToDistribute, WinningOption);    
    }

    function getReturn(address _user)public view returns(uint){
     uint ethReturn = 0; 
     uint distanceFromWinningOption = 0;
      (,uint totalOptions, , , ,uint lossPercentage, ) = marketConfig.getBasicMarketDetails();
       if(predictionStatus != PredictionStatus.ResultDeclared ) {
        return 0;
       }
     for(uint i=1;i<=totalOptions;i++){
      distanceFromWinningOption = i>WinningOption ? i.sub(WinningOption) : WinningOption.sub(i); 
      ethReturn =  _calEthReturn(ethReturn,_user,i,lossPercentage,distanceFromWinningOption);
      }     
     uint reward = userPredictionPoints[_user][WinningOption].mul(rewardToDistribute).div(optionsAvailable[WinningOption].predictionPoints);
     uint returnAmount =  reward.add(ethReturn);
     return returnAmount;
    }

    function getPendingReturn(address _user)public view returns(uint){
     if(userClaimedReward[_user]) return 0;
     return getReturn(_user);
    }
    
    //Split getReturn() function otherwise it shows compilation error(e.g; stack too deep).
    function _calEthReturn(uint ethReturn,address _user,uint i,uint lossPercentage,uint distanceFromWinningOption)internal view returns(uint){
        return ethReturn.add(ethStaked[_user][i].sub((LeverageEth[_user][i].mul(distanceFromWinningOption).mul(lossPercentage)).div(100)));
    }

    function claimReturn(address payable _user) public {
      require(!userClaimedReward[_user],"Already claimed");
      require(predictionStatus == PredictionStatus.ResultDeclared,"Result not declared");
      userClaimedReward[_user] = true;
      (uint returnAmount) = getReturn(_user);
       _user.transfer(returnAmount);
      pl.callClaimedEvent(_user,returnAmount, ethStaked[_user][WinningOption]);
    }

    function __callback(bytes32 myid, string memory result) public {
      // if(myid == closeMarketId) {
      //   _closeBet();
      // } else if(myid == marketResultId) {
      require ((myid==marketResultId));
      //Check oraclise address
      calculatePredictionResult(parseInt(result));
      // }
    }

}
