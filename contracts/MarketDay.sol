pragma solidity 0.5.7;

import "./Market.sol";

contract MarketDaily is Market {

    constructor(
     uint[] memory _uintparams,
     string memory _feedsource,
     address payable[] memory _addressParams
    ) 
    public
    payable Market(_uintparams, _feedsource, _addressParams)
    {
      expireTime = startTime + 1 days;
      betType = uint(IPlotus.MarketType.DailyMarket);

      //provable_query(expireTime.sub(now), "URL", FeedSource, 500000); //comment to deploy
    }

    function getPrice(uint _prediction) public view returns(uint) {
      return optionPrice[_prediction];
    }

    function setPrice(uint _prediction, uint _value) public returns(uint ,uint){
      optionPrice[_prediction] = _calculateOptionPrice(_prediction);
    }

    function _calculateOptionPrice(uint _option) internal view returns(uint _optionPrice) {
      if(address(this).balance > 20 ether) {
        _optionPrice = (optionsAvailable[_option].ethStaked).mul(10000)
                      .div((address(this).balance).mul(40));
      }

      uint timeElapsed = now - startTime;
      timeElapsed = timeElapsed > 4 hours ? timeElapsed: 4 hours;
      _optionPrice = _optionPrice.add(
              (_getDistance(_option).sub(6)).mul(10000).mul(timeElapsed.div(1 hours))
             )
             .div(
              360 * 24
             );
    }
}