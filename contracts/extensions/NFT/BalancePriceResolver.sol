// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './interfaces/INFTSupply.sol';
import './SupplyPriceResolver.sol';

contract BalancePriceResolver is SupplyPriceResolver {
  bool internal immutable freeSample;
  uint256 internal immutable nthFree;
  uint256 internal immutable freeMintCap;

  /**
   * @notice blah
   * @param _basePrice Minimum price to return.
   * @param _freeSample blah.
   * @param _nthFree blah.
   * @param _freeMintCap blah.
   * @param _priceCap Maximum price to return.
   * @param _priceFunction Price multiplier application, linear, exponential, contant.
   * @param _multiplier blah
   * @param _tierSize blah
   */
  constructor(
    uint256 _basePrice,
    bool _freeSample,
    uint256 _nthFree,
    uint256 _freeMintCap,
    uint256 _priceCap,
    PriceFunction _priceFunction,
    uint256 _multiplier,
    uint256 _tierSize
  ) SupplyPriceResolver(_basePrice, _multiplier, _tierSize, _priceCap, _priceFunction) {
    freeSample = _freeSample;
    nthFree = _nthFree;
    freeMintCap = _freeMintCap;
  }

  function getPrice(
    address _token,
    address _minter,
    uint256 _tokenid
  ) public view virtual override returns (uint256 price) {
    uint256 minterBalance = INFTSupply(_token).balanceOf(_minter);

    if (minterBalance == 0 && freeSample) {
      price = 0;
    } else if (
      nthFree != 0 &&
      (minterBalance + 1) % nthFree == 0 &&
      ((freeMintCap > 0 && minterBalance + 1 <= nthFree * freeMintCap))
    ) {
      price = 0;
    } else {
      price = super.getPrice(_token, _minter, _tokenid);
    }
  }

  function getPriceWithParams(
    address _token,
    address _minter,
    uint256 _tokenid,
    bytes calldata
  ) public view virtual override returns (uint256 price) {
    price = getPrice(_token, _minter, _tokenid);
  }
}
