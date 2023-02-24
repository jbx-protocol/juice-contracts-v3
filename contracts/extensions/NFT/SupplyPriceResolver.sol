// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './interfaces/INFTSupply.sol';
import './interfaces/INFTPriceResolver.sol';

contract SupplyPriceResolver is INFTPriceResolver {
  uint256 internal immutable basePrice;
  uint256 internal immutable multiplier;
  uint256 internal immutable tierSize;
  uint256 internal immutable priceCap;
  PriceFunction internal immutable priceFunction;

  /**
   * @notice Creates a resolver that calculates a tiered price based on current token supply. Price will be either multipied by multiplier * (currentSupply % tierSize) or multiplier ** (currentSupply % tierSize).
   * @param _basePrice Minimum price to return.
   * @param _multiplier Price multiplyer.
   * @param _tierSize Price tier size.
   * @param _priceCap Maximum price to return.
   * @param _priceFunction Price multiplier application, linear or exponential.
   */
  constructor(
    uint256 _basePrice,
    uint256 _multiplier,
    uint256 _tierSize,
    uint256 _priceCap,
    PriceFunction _priceFunction
  ) {
    basePrice = _basePrice;
    multiplier = _multiplier;
    tierSize = _tierSize;
    priceCap = _priceCap;
    priceFunction = _priceFunction;
  }

  function getPrice(
    address _token,
    address,
    uint256
  ) public view virtual override returns (uint256 price) {
    uint256 currentSupply = INFTSupply(_token).totalSupply();

    if (priceFunction == PriceFunction.LINEAR) {
      price = multiplier * (currentSupply / tierSize) * basePrice;
    } else if (priceFunction == PriceFunction.EXP) {
      price = multiplier ** (currentSupply / tierSize) * basePrice;
    } else if (priceFunction == PriceFunction.CONSTANT) {
      // price = basePrice; // NOTE, price is 0 here and will be set to basePrice below
    }

    if (price > priceCap) {
      price = priceCap;
    } else if (price == 0) {
      price = basePrice;
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
