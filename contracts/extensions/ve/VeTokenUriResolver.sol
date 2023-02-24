// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/Strings.sol';

import './interfaces/IJBVeTokenUriResolver.sol';

/**
 * @dev Based on JBVeTokenUriResolver from https://github.com/jbx-protocol/juice-ve-nft/tree/master/contracts.
 */
contract VeTokenUriResolver is IJBVeTokenUriResolver, Ownable {
  error INVALID_LOCK_DURATION();
  error INSUFFICIENT_BALANCE();

  string public baseUri;
  string public contractUri;
  uint256[] public tokenRanges;

  /**
   * Creates a basic token uri resolver. This this is also meant to be an example of how to generate token uris for ve NFTs.
   *
   * @param _owner Contract administrator.
   * @param _baseUri Base uri for the associated VE NFT.
   * @param _contractUri Contract metadata uri for the associated VE NFT.
   * @param _tokenRanges Token ranges, must be sorted in ascending order. Used to calcuate token uri.
   */
  constructor(
    address _owner,
    string memory _baseUri,
    string memory _contractUri,
    uint256[] memory _tokenRanges
  ) {
    baseUri = _baseUri;
    contractUri = _contractUri;

    for (uint256 i; i != _tokenRanges.length; ) {
      tokenRanges.push(_tokenRanges[i]);
      unchecked {
        ++i;
      }
    }

    _transferOwnership(_owner);
  }

  /**
   * @notice Opensea-style metadata uri.
   */
  function contractURI() public view override returns (string memory) {
    return contractUri;
  }

  /**
   * @notice Set base uri the associated VE NFT will use.
   *
   * @dev Uri must terminate with a '/'.
   */
  function setBaseURI(string memory _baseUri) public onlyOwner {
    baseUri = _baseUri;
  }

  function setContractUri(string memory _contractUri) public onlyOwner {
    contractUri = _contractUri;
  }

  /**
   * @notice Computes the metadata url.
   *
   * @param _tokenId Token ID.
   * @param _amount Lock Amount.
   * @param _duration Lock time in seconds.
   * @param _lockedUntil Lock end time.
   * @param _lockDurationOptions The options that the duration can be.
   *
   * @return The metadata url.
   */
  function tokenURI(
    uint256 _tokenId,
    uint256 _amount,
    uint256 _duration,
    uint256 _lockedUntil,
    uint256[] memory _lockDurationOptions
  ) external view override returns (string memory) {
    _tokenId;
    _lockedUntil;

    if (_amount <= 0) {
      revert INSUFFICIENT_BALANCE();
    }

    if (_duration <= 0) {
      revert INVALID_LOCK_DURATION();
    }

    return
      string(
        abi.encodePacked(
          baseUri,
          Strings.toString(
            _getTokenRange(_amount) * 5 + _getTokenStakeMultiplier(_duration, _lockDurationOptions)
          )
        )
      );
  }

  /**
   * @notice Returns index slot which is used to generate token uri. The input parmeter is the full token amount associated with the ve NFT.
   *
   * @param _amount Locked token amount associated with the ve NFT.
   */
  function _getTokenRange(uint256 _amount) private view returns (uint256 index) {
    uint256 length = tokenRanges.length;

    for (; index != length; ) {
      if (_amount < tokenRanges[index]) {
        return index;
      }
      unchecked {
        ++index;
      }
    }
  }

  /**
   * @notice Returns the token duration multiplier needed to index into the righteous veBanny mediallion background.
   *
   * @param _duration Time in seconds corresponding with one of five acceptable staking durations.
   * The Staking durations below were gleaned from the JBVeNft.sol contract line 55-59.
   * Returns the duration multiplier used to index into the proper veBanny mediallion on IPFS.
   */
  function _getTokenStakeMultiplier(
    uint256 _duration,
    uint256[] memory _lockDurationOptions
  ) private pure returns (uint256) {
    for (uint256 _i = 0; _i < _lockDurationOptions.length; ) {
      if (_lockDurationOptions[_i] == _duration) return _i + 1;
      unchecked {
        ++_i;
      }
    }
    revert INVALID_LOCK_DURATION();
  }
}
