// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/utils/Strings.sol';

import '../../interfaces/IJBDirectory.sol';
import './components/BaseNFT.sol';

/**
 * @notice This is a pseudo ERC1155 contract presented as an ERC721.
 */
contract NFUEdition is BaseNFT {
  using Strings for uint256;

  event RegisterEdition(uint256 supply, uint256 price);

  error INVALID_OPERATION();

  /**
   * @dev Lists edition (array-index) supply caps (value).
   */
  uint256[] public editions;

  /**
   * @dev Lists edition (array-index) prices in wei (value).
   */
  uint256[] public editionPrices;

  /**
   * @dev Tracks last minted edition (array-index) token id (value).
   */
  uint256[] public mintedEditions;

  //*********************************************************************//
  // -------------------------- initializer ---------------------------- //
  //*********************************************************************//

  /**
   * @dev This contract is meant to be deployed via the `Deployer` which makes `Clone`s. The `Deployer` itself has a reference to a known-good copy. When the platform admin is deploying the `Deployer` and the source `NFUEdition` the constructor will lock that contract to the platform admin. When the deployer is making copies of it the source storage isn't taken so the Deployer will call `initialize` to set the admin to the correct account.
   */
  constructor() {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(MINTER_ROLE, msg.sender);
    _grantRole(REVEALER_ROLE, msg.sender);
  }

  /**
   * @notice Initializes token state. Used by the Deployer contract to set NFT parameters and contract ownership.
   *
   * @param _owner Token admin.
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
  function initialize(
    address _owner,
    string memory _name,
    string memory _symbol,
    string memory _baseUri,
    string memory _contractUri,
    uint256 _jbxProjectId,
    IJBDirectory _jbxDirectory,
    uint256 _maxSupply,
    uint256 _unitPrice,
    uint256 _mintAllowance,
    uint256 _mintPeriodStart,
    uint256 _mintPeriodEnd
  ) public {
    if (bytes(name).length != 0) {
      revert INVALID_OPERATION();
    }

    if (getRoleMemberCount(DEFAULT_ADMIN_ROLE) != 0) {
      if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
        revert INVALID_OPERATION();
      }
    } else {
      _grantRole(DEFAULT_ADMIN_ROLE, _owner);
      _grantRole(MINTER_ROLE, _owner);
      _grantRole(REVEALER_ROLE, _owner);
    }

    name = _name;
    symbol = _symbol;

    baseUri = _baseUri;
    contractUri = _contractUri;
    jbxDirectory = _jbxDirectory;
    jbxProjectId = _jbxProjectId;
    maxSupply = _maxSupply;
    unitPrice = _unitPrice;
    mintAllowance = _mintAllowance;
    mintPeriod = (_mintPeriodStart << 128) | _mintPeriodEnd;

    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(MINTER_ROLE, _owner);
    _grantRole(REVEALER_ROLE, _owner);
  }

  //*********************************************************************//
  // ------------------------- mint operations ------------------------- //
  //*********************************************************************//

  /**
   * @notice Mints a token for a given edition provided that price validation logic is satisfied. Subject to maxSupply constraints set in the `initialize` function and edition limits set with `registerEdition`.
   *
   * @param _edition Edition index.
   */
  function mint(
    uint256 _edition
  )
    external
    payable
    virtual
    nonReentrant
    onlyDuringMintPeriod
    callerNotBlocked(msg.sender)
    supplyAvailable(_edition)
    returns (uint256 tokenId)
  {
    if (isPaused) {
      revert MINTING_PAUSED();
    }

    processPayment('', '', editionPrices[_edition]); // validates price

    unchecked {
      ++totalSupply;
      ++mintedEditions[_edition];
    }
    tokenId = generateTokenId(msg.sender, msg.value, _edition);
    _mint(msg.sender, tokenId);
  }

  /**
   * @notice Mints a token for a given edition index after validating payment. Subject to maxSupply constraints set in the `initialize` function and edition limits set with `registerEdition`.
   *
   * @param _edition Edition index.
   * @param _memo Juicebox payment memo param.
   * @param _metadata Juicebox payment metadata param.
   */
  function mint(
    uint256 _edition,
    string calldata _memo,
    bytes calldata _metadata
  )
    external
    payable
    virtual
    nonReentrant
    onlyDuringMintPeriod
    callerNotBlocked(msg.sender)
    supplyAvailable(_edition)
    returns (uint256 tokenId)
  {
    if (isPaused) {
      revert MINTING_PAUSED();
    }

    processPayment(_memo, _metadata, editionPrices[_edition]); // validates price

    unchecked {
      ++totalSupply;
      ++mintedEditions[_edition];
    }
    tokenId = generateTokenId(msg.sender, msg.value, _edition);
    _mint(msg.sender, tokenId);
  }

  //*********************************************************************//
  // -------------------- priviledged transactions --------------------- //
  //*********************************************************************//

  /**
   * @notice Priviledged operation to mint an edition to an address. Does not accept payment, ignores paused flag, mint period and block list.
   */
  function mintEditionFor(
    uint256 _edition,
    address _account
  ) external virtual onlyRole(MINTER_ROLE) supplyAvailable(_edition) returns (uint256 tokenId) {
    unchecked {
      ++totalSupply;
      ++mintedEditions[_edition];
    }
    tokenId = generateTokenId(_account, 0, _edition);
    _mint(_account, tokenId);
  }

  /**
   * @notice Appends an edition to the current list. Editions must be in acending order price-wise and this operation will fail if the edition being added is priced below the last one.
   */
  function registerEdition(
    uint256 _maxSupply,
    uint256 _price
  ) external virtual onlyRole(MINTER_ROLE) returns (uint256 editionId) {
    if (editions.length != 0) {
      if (editionPrices[editions.length - 1] > _price) {
        revert INVALID_OPERATION();
      }
    }

    editions.push(_maxSupply);
    editionPrices.push(_price);
    mintedEditions.push(0);
    emit RegisterEdition(_maxSupply, _price);
  }

  //*********************************************************************//
  // ------------------------ parent overrides ------------------------- //
  //*********************************************************************//
  /**
   * @notice Provides a token URI based on edition index encoded in the bottom 16 bits of the token id.
   */
  function tokenURI(uint256 _tokenId) public view virtual override returns (string memory uri) {
    if (ownerOf(_tokenId) == address(0)) {
      uri = '';
    } else {
      uri = !isRevealed
        ? baseUri
        : string(abi.encodePacked(baseUri, uint256(uint16(_tokenId)).toString()));
    }
  }

  /**
   * @dev Prevent mint without edition param.
   */
  function mint() external payable override returns (uint256) {
    revert INVALID_OPERATION();
  }

  /**
   * @dev Prevent mint without edition param.
   */
  function mint(string calldata, bytes calldata) external payable override returns (uint256) {
    revert INVALID_OPERATION();
  }

  /**
   * @dev Prevent mint without edition param.
   */
  function mintFor(address) external override returns (uint256) {
    revert INVALID_OPERATION();
  }

  /**
   * @dev Prevent mint without edition param.
   */
  function generateTokenId(
    address _account,
    uint256 _amount
  ) internal virtual override returns (uint256 tokenId) {
    revert INVALID_OPERATION();
  }

  /**
   * @notice Returns a token id for the given parameters, edition is encoded in the bottom (right) 16 bits.
   *
   * @dev If randomizedMint is set token id will be based on account value, current price of eth for the amount provided (via Uniswap), current block number. Collisions are resolved via increment.
   *
   * @param _account Account which will recieve the token.
   * @param _amount Price being paid for this token, in wei.
   * @param _edition Edition index.
   */
  function generateTokenId(
    address _account,
    uint256 _amount,
    uint256 _edition
  ) internal virtual returns (uint256 tokenId) {
    if (!randomizedMint) {
      tokenId = _edition | (uint240(mintedEditions[_edition] + 1) << 16);
    } else {
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

      uint256 editionSupply = editions[_edition] + 1; // +1 because we consider 0 to be an invalid token id
      uint256 tokenIdRoot = uint256(keccak256(abi.encodePacked(_account, block.number, ethPrice))) %
        editionSupply;

      tokenId = _edition | (uint240(tokenIdRoot) << 16);

      // resolve token id collisions
      while (tokenId == 0 || _ownerOf[tokenId] != address(0)) {
        tokenId = _edition | (uint240(++tokenIdRoot % editionSupply) << 16);
      }
    }
  }

  modifier supplyAvailable(uint256 _edition) {
    if (editions.length == 0 || editions.length < _edition) {
      revert INVALID_OPERATION();
    }

    if (totalSupply == maxSupply) {
      revert SUPPLY_EXHAUSTED();
    }

    if (mintedEditions[_edition] == editions[_edition]) {
      revert SUPPLY_EXHAUSTED();
    }

    _;
  }
}
