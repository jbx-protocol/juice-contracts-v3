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

  uint8 public constant decimals = 18;
  string public baseUri = 'ipfs://QmSCaNi3VeyrV78qWiDgxdkJTUB7yitnLKHsPHudguc9kv/';
  string public contractUri;

  /**
   *
   * @param _owner Contract administrator.
   * @param _baseUri Base uri for the associated VE NFT.
   * @param _contractUri Opensea-style metadata uri for the associated VE NFT.
   */
  constructor(address _owner, string memory _baseUri, string memory _contractUri) {
    baseUri = _baseUri;
    contractUri = _contractUri;

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
   * @notice Returns the veBanny character index needed to compute the righteous veBanny on IPFS.
   *
   * @dev The range values referenced below were gleaned from the following Notion URL.
   * https://www.notion.so/juicebox/veBanny-proposal-from-Jango-2-68c6f578bef84205a9f87e3f1057aa37
   *
   * @param _amount Amount of locked Juicebox.
   *
   * @return The token range index or veBanny character commensurate with amount of locked Juicebox.
   */
  function _getTokenRange(uint256 _amount) private pure returns (uint256) {
    // Reduce amount to exclude decimals
    _amount = _amount / 10 ** decimals;

    if (_amount < 100) {
      return 0;
    } else if (_amount < 200) {
      return 1;
    } else if (_amount < 300) {
      return 2;
    } else if (_amount < 400) {
      return 3;
    } else if (_amount < 500) {
      return 4;
    } else if (_amount < 600) {
      return 5;
    } else if (_amount < 700) {
      return 6;
    } else if (_amount < 800) {
      return 7;
    } else if (_amount < 900) {
      return 8;
    } else if (_amount < 1_000) {
      return 9;
    } else if (_amount < 2_000) {
      return 10;
    } else if (_amount < 3_000) {
      return 11;
    } else if (_amount < 4_000) {
      return 12;
    } else if (_amount < 5_000) {
      return 13;
    } else if (_amount < 6_000) {
      return 14;
    } else if (_amount < 7_000) {
      return 15;
    } else if (_amount < 8_000) {
      return 16;
    } else if (_amount < 9_000) {
      return 17;
    } else if (_amount < 10_000) {
      return 18;
    } else if (_amount < 12_000) {
      return 19;
    } else if (_amount < 14_000) {
      return 20;
    } else if (_amount < 16_000) {
      return 21;
    } else if (_amount < 18_000) {
      return 22;
    } else if (_amount < 20_000) {
      return 23;
    } else if (_amount < 22_000) {
      return 24;
    } else if (_amount < 24_000) {
      return 25;
    } else if (_amount < 26_000) {
      return 26;
    } else if (_amount < 28_000) {
      return 27;
    } else if (_amount < 30_000) {
      return 28;
    } else if (_amount < 40_000) {
      return 29;
    } else if (_amount < 50_000) {
      return 30;
    } else if (_amount < 60_000) {
      return 31;
    } else if (_amount < 70_000) {
      return 32;
    } else if (_amount < 80_000) {
      return 33;
    } else if (_amount < 90_000) {
      return 34;
    } else if (_amount < 100_000) {
      return 35;
    } else if (_amount < 200_000) {
      return 36;
    } else if (_amount < 300_000) {
      return 37;
    } else if (_amount < 400_000) {
      return 38;
    } else if (_amount < 500_000) {
      return 39;
    } else if (_amount < 600_000) {
      return 40;
    } else if (_amount < 700_000) {
      return 41;
    } else if (_amount < 800_000) {
      return 42;
    } else if (_amount < 900_000) {
      return 43;
    } else if (_amount < 1_000_000) {
      return 44;
    } else if (_amount < 2_000_000) {
      return 45;
    } else if (_amount < 3_000_000) {
      return 46;
    } else if (_amount < 4_000_000) {
      return 47;
    } else if (_amount < 5_000_000) {
      return 48;
    } else if (_amount < 6_000_000) {
      return 49;
    } else if (_amount < 7_000_000) {
      return 50;
    } else if (_amount < 8_000_000) {
      return 51;
    } else if (_amount < 9_000_000) {
      return 52;
    } else if (_amount < 10_000_000) {
      return 53;
    } else if (_amount < 20_000_000) {
      return 54;
    } else if (_amount < 40_000_000) {
      return 55;
    } else if (_amount < 60_000_000) {
      return 56;
    } else if (_amount < 100_000_000) {
      return 57;
    } else if (_amount < 600_000_000) {
      return 58;
    } else {
      return 59;
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
