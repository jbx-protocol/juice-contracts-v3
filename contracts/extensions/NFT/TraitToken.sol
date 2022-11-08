// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../../interfaces/IJBDirectory.sol';
import './components/BaseNFT.sol';

contract TraitToken is BaseNFT {
  bytes constant ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  /**
   * @notice NFT provenance hash reassignment prohibited.
   */
  error NOT_MINTED();

  error CID_REASSIGNMENT();

  mapping(uint256 => uint256) public tokenTraits;

  /**
   * @notice Stores truncated IPFS CIDs, missing first two bytes that are expected to be 1220 for IPFS v1 CIDs.
   */
  mapping(uint256 => bytes32) public tokenCIDs;

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  /**
   * @notice Creates the NFT contract.
   *
   * @param _name Token name.
   * @param _symbol Token symbol.
   * @param _baseUri Base URI, initially expected to point at generic, "unrevealed" metadata json.
   * @param _contractUri OpenSea-style contract metadata URI.
   * @param _jbxProjectId Juicebox project id that will be paid the proceeds of the sale.
   * @param _jbxDirectory Juicebox directory to determine payment destination.
   * @param _maxSupply Max NFT supply.
   * @param _unitPrice Price per token expressed in Ether.
   * @param _mintAllowance Per-user mint cap.
   * @param _mintPeriodStart Start of the minting period in seconds.
   * @param _mintPeriodEnd End of the minting period in seconds.
   */
  constructor(
    string memory _name,
    string memory _symbol,
    string memory _baseUri,
    string memory _contractUri,
    uint256 _jbxProjectId,
    IJBDirectory _jbxDirectory,
    uint256 _maxSupply,
    uint256 _unitPrice,
    uint256 _mintAllowance,
    uint128 _mintPeriodStart,
    uint128 _mintPeriodEnd
  ) {
    name = _name;
    symbol = _symbol;

    baseUri = _baseUri;
    contractUri = _contractUri;
    jbxDirectory = _jbxDirectory;
    jbxProjectId = _jbxProjectId;
    maxSupply = _maxSupply;
    unitPrice = _unitPrice;
    mintAllowance = _mintAllowance;
    mintPeriodStart = _mintPeriodStart;
    mintPeriodEnd = _mintPeriodEnd;

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(MINTER_ROLE, msg.sender);
    _grantRole(REVEALER_ROLE, msg.sender);
  }

  function setTokenAsset(uint256 _tokenId, bytes32 _truncatedCID) external {
    if (ownerOf(_tokenId) == address(0)) {
      revert NOT_MINTED();
    }

    if (tokenCIDs[_tokenId] != 0) {
      revert CID_REASSIGNMENT();
    }

    tokenCIDs[_tokenId] = _truncatedCID;
  }

  function tokenURI(uint256 _tokenId) public view virtual override returns (string memory uri) {
    bytes memory prefix = hex'1220';
    uri = string(
      abi.encodePacked('ipfs://', base58Encode(bytes.concat(prefix, tokenCIDs[_tokenId])))
    );
  }

  function generateTokenId(
    address,
    uint256,
    uint256
  ) internal virtual override returns (uint256 tokenId) {
    tokenId = totalSupply;
  }

  function base58Encode(bytes memory _data) private pure returns (string memory) {
    unchecked {
      uint256 size = _data.length;
      uint256 zeroCount;
      while (zeroCount < size && _data[zeroCount] == 0) {
        zeroCount++;
      }
      size = zeroCount + ((size - zeroCount) * 8351) / 6115 + 1;
      bytes memory slot = new bytes(size);
      uint32 carry;
      int256 m;
      int256 high = int256(size) - 1;
      for (uint256 i = 0; i < _data.length; i++) {
        m = int256(size - 1);
        for (carry = uint8(_data[i]); m > high || carry != 0; m--) {
          carry = carry + 256 * uint8(slot[uint256(m)]);
          slot[uint256(m)] = bytes1(uint8(carry % 58));
          carry /= 58;
        }
        high = m;
      }
      uint256 n;
      for (n = zeroCount; n < size && slot[n] == 0; n++) {}
      size = slot.length - (n - zeroCount);
      bytes memory out = new bytes(size);
      for (uint256 i = 0; i < size; i++) {
        uint256 j = i + n - zeroCount;
        out[i] = ALPHABET[uint8(slot[j])];
      }
      return string(out);
    }
  }
}
