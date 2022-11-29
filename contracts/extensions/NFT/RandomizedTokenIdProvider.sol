// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/utils/Strings.sol';

import './interfaces/INFTSupply.sol';
import './interfaces/ITokenIdProvider.sol';
import './interfaces/ITokenURIProvider.sol';

/**
 * @notice Uniswap IQuoter interface snippet taken from uniswap v3 periphery library.
 */
interface IQuoter {
  function quoteExactInputSingle(
    address tokenIn,
    address tokenOut,
    uint24 fee,
    uint256 amountIn,
    uint160 sqrtPriceLimitX96
  ) external returns (uint256 amountOut);
}

contract RandomizedTokenIdProvider is ITokenIdProvider, ITokenURIProvider {
  using Strings for uint256;

  /**
   * @notice Error indicating the next token id exceeds max supply of the calling token.
   */
  error SUPPLY_EXCEEDED();

  IQuoter public constant uniswapQuoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
  address public constant WETH9 = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
  address public constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

  INFTSupply public token;
  string public baseUri;

  /**
   * @param _token Token associated with this provider, must respond to `ownerOf(uint256)`.
   * @param _baseUri Root asset URI with trailing slash.
   */
  constructor(INFTSupply _token, string memory _baseUri) {
    token = _token;
    baseUri = _baseUri;
  }

  function tokenId(
    uint256 _amount,
    uint256 _currentSupply,
    uint256 _maxSupply,
    address _account,
    uint256
  ) external returns (uint256 id) {
    if (_currentSupply + 1 > _maxSupply) {
      revert SUPPLY_EXCEEDED();
    }

    uint256 ethPrice;
    if (_amount != 0) {
      ethPrice = uniswapQuoter.quoteExactInputSingle(
        WETH9,
        DAI,
        3000, // fee
        _amount,
        0 // sqrtPriceLimitX96
      );
    }

    id = uint256(keccak256(abi.encodePacked(_account, block.number, ethPrice))) % (_maxSupply + 1);

    while (tokenId == 0 || token.ownerOf(id) != address(0)) {
      id = ++id % (_maxSupply + 1);
    }
  }

  /**
   * @notice Appends token id to the base uri supplied in the contructor.
   *
   * @param _tokenId Token id
   */
  function tokenURI(uint256 _tokenId) public returns (string memory uri) {
    uri = string(abi.encodePacked(baseUri, _tokenId.toString()));
  }
}
