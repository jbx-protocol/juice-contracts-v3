// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import '../../abstract/JBOperatable.sol';
import '../../libraries/JBOperations.sol';
import '../../interfaces/IJBDirectory.sol';
import '../../interfaces/IJBProjects.sol';
import '../../interfaces/IJBOperatorStore.sol';
import '../PlatformDiscountManager.sol';
import './Factories/NFTokenFactory.sol';

/**
 * @notice
 */
/// @custom:oz-upgrades-unsafe-allow external-library-linking
contract Deployer_v001 is JBOperatable, OwnableUpgradeable, UUPSUpgradeable {
  event Deployment(string contractType, address contractAddress);

  error INVALID_PAYMENT(uint256 price);
  error INVALID_ADDRESS();
  error INVALID_AMOUNT(uint256 amount);

  IJBDirectory internal jbxDirectory;
  IJBProjects internal jbxProjects;

  PlatformDiscountManager public platformDiscountManager;

  mapping(bytes32 => uint256) public prices;

  bytes32 internal constant deployNFTokenKey = keccak256(abi.encodePacked('deployNFToken'));

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address _jbxDirectory,
    address _jbxProjects,
    address _jbxOperatorStore
  ) public virtual initializer {
    __Ownable_init();
    __UUPSUpgradeable_init();

    operatorStore = IJBOperatorStore(_jbxOperatorStore);
    jbxDirectory = IJBDirectory(_jbxDirectory);
    jbxProjects = IJBProjects(_jbxProjects);

    prices[deployNFTokenKey] = 1000000000000000; // 0.001 eth
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}

  /**
   * @dev This creates a token that can be minted immediately, to discourage this, unitPrice can be set high, then mint period can be defined before setting price to a "reasonable" value.
   */
  function deployNFToken(
    address payable _owner,
    string memory _name,
    string memory _symbol,
    string memory _baseUri,
    string memory _contractUri,
    uint256 _maxSupply,
    uint256 _unitPrice,
    uint256 _mintAllowance,
    bool _reveal
  ) external payable returns (address token) {
    validatePayment(deployNFTokenKey);

    token = NFTokenFactory.createNFToken(
      _owner,
      _name,
      _symbol,
      _baseUri,
      _contractUri,
      _maxSupply,
      _unitPrice,
      _mintAllowance,
      _reveal
    );
    emit Deployment('NFToken', token);
  }

  function validatePayment(bytes32 _priceKey) internal virtual {
    uint256 price = getPrice(_priceKey, msg.sender);

    if (msg.value != price) {
      revert INVALID_PAYMENT(price);
    }
  }

  /**
   * @notice Returns the price of a given deployer action. To generate the price key, get the hash of the packed function name, for example price key of `deployNFToken` action would be `keccak256(abi.encodePacked('deployNFToken'))`.
   *
   * @param _priceKey keccak256 hash of a packed action key.
   * @param _actor Account attempting the operation.
   */
  function getPrice(bytes32 _priceKey, address _actor) public view virtual returns (uint256 price) {
    price = prices[_priceKey];

    if (price == 0) {
      return 0;
    }

    if (address(platformDiscountManager) != address(0)) {
      price = platformDiscountManager.getPrice(_actor, price);
    }
  }

  function updatePrice(
    bytes32 _priceKey,
    uint256 _price
  )
    external
    virtual
    requirePermissionAllowingOverride(
      jbxProjects.ownerOf(1),
      1,
      JBOperations.PROCESS_FEES,
      (msg.sender == address(jbxDirectory.controllerOf(1)))
    )
  {
    prices[_priceKey] = _price;
  }

  function transferBalance(
    address payable _destination,
    uint256 _amount
  )
    external
    requirePermissionAllowingOverride(
      jbxProjects.ownerOf(1),
      1,
      JBOperations.PROCESS_FEES,
      (msg.sender == address(jbxDirectory.controllerOf(1)))
    )
  {
    if (_amount > (payable(address(this))).balance) {
      revert INVALID_AMOUNT((payable(address(this))).balance);
    }

    _destination.transfer(_amount);
  }

  function setPlatformDiscountManager(
    PlatformDiscountManager _platformDiscountManager
  )
    external
    requirePermissionAllowingOverride(
      jbxProjects.ownerOf(1),
      1,
      JBOperations.PROCESS_FEES,
      (msg.sender == address(jbxDirectory.controllerOf(1)))
    )
  {
    platformDiscountManager = _platformDiscountManager;
  }
}
