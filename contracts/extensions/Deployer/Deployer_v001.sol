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
  error INVALID_AMOUNT();

  // IJBDirectory public jbxDirectory
  // IJBProjects public jbxProjects;

  PlatformDiscountManager public platformDiscountManager;

  mapping(bytes32 => uint256) public prices;

  bytes32 internal constant deployNFTokenKey = keccak256(abi.encodePacked('deployNFToken'));

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize()
    public
    virtual
    // IJBDirectory _jbxDirectory,
    // IJBProjects _jbxProjects,
    // IJBOperatorStore _jbxOperatorStore
    initializer
  {
    __Ownable_init();
    __UUPSUpgradeable_init();

    // operatorStore = _jbxOperatorStore;
    // jbxDirectory = _jbxDirectory;
    // jbxProjects = _jbxProjects;

    prices[deployNFTokenKey] = 1000000000000000; // 0.001 eth
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}

  function deployNFToken(
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
  ) external payable returns (address) {
    validatePayment(deployNFTokenKey);

    address t = NFTokenFactory.createNFToken(
      _owner,
      _name,
      _symbol,
      _baseUri,
      _contractUri,
      _jbxProjectId,
      _jbxDirectory,
      _maxSupply,
      _unitPrice,
      _mintAllowance,
      _mintPeriodStart,
      _mintPeriodEnd
    );

    emit Deployment('NFToken', t);

    return t;
  }

  function validatePayment(bytes32 _priceKey) internal virtual {
    uint256 price = prices[_priceKey];

    if (price == 0) {
      return;
    }

    if (address(platformDiscountManager) != address(0)) {
      price = platformDiscountManager.getPrice(msg.sender, price);
    }

    if (msg.value != price) {
      revert INVALID_PAYMENT(price);
    }
  }

  function updatePrice(bytes32 _priceKey, uint256 _price) external virtual {
    // TODO: permissions
    prices[_priceKey] = _price;
  }

  //   function transferBalance(
  //     address payable _destination,
  //     uint256 _amount
  //   )
  //     external
  //     nonReentrant
  //     requirePermissionAllowingOverride(
  //       jbxProjects.ownerOf(jbxProjectId),
  //       jbxProjectId,
  //       JBOperations.MANAGE_PAYMENTS,
  //       (msg.sender == address(jbxDirectory.controllerOf(jbxProjectId)))
  //     )
  //   {
  //     // TODO: permissions
  //     if (_destination == address(0)) {
  //       revert INVALID_ADDRESS();
  //     }

  //     if (_amount == 0 || _amount > (payable(address(this))).balance) {
  //       revert INVALID_AMOUNT();
  //     }

  //     _destination.transfer(_amount);
  //   }

  function setPlatformDiscountManager(PlatformDiscountManager _platformDiscountManager) external {
    // TODO: permissions
    // platformDiscountManager = _platformDiscountManager;
  }
}
