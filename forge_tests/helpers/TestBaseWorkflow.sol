// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import 'forge-std/Test.sol';

import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {IERC721Metadata} from '@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ERC165, IERC165} from '@openzeppelin/contracts/utils/introspection/ERC165.sol';
import {JBController3_1} from '@juicebox/JBController3_1.sol';
import {JBDirectory} from '@juicebox/JBDirectory.sol';
import {JBTerminalStore} from '@juicebox/JBTerminalStore.sol';
import {JBFundAccessConstraintsStore} from '@juicebox/JBFundAccessConstraintsStore.sol';
import {JBFundingCycleStore} from '@juicebox/JBFundingCycleStore.sol';
import {JBOperatorStore} from '@juicebox/JBOperatorStore.sol';
import {JBPrices} from '@juicebox/JBPrices.sol';
import {JBProjects} from '@juicebox/JBProjects.sol';
import {JBSplitsStore} from '@juicebox/JBSplitsStore.sol';
import {JBToken} from '@juicebox/JBToken.sol';
import {JBTokenStore} from '@juicebox/JBTokenStore.sol';
import {JBReconfigurationBufferBallot} from '@juicebox/JBReconfigurationBufferBallot.sol';
import {JBMultiTerminal} from '@juicebox/JBMultiTerminal.sol';
import {JBCurrencyAmount} from '@juicebox/structs/JBCurrencyAmount.sol';
import {JBAccountingContextConfig} from '@juicebox/structs/JBAccountingContextConfig.sol';
import {JBDidPayData3_1_1} from '@juicebox/structs/JBDidPayData3_1_1.sol';
import {JBDidRedeemData3_1_1} from '@juicebox/structs/JBDidRedeemData3_1_1.sol';
import {JBFee} from '@juicebox/structs/JBFee.sol';
import {JBFees} from '@juicebox/libraries/JBFees.sol';
import {JBFundAccessConstraints} from '@juicebox/structs/JBFundAccessConstraints.sol';
import {JBFundingCycle} from '@juicebox/structs/JBFundingCycle.sol';
import {JBFundingCycleData} from '@juicebox/structs/JBFundingCycleData.sol';
import {JBFundingCycleMetadata} from '@juicebox/structs/JBFundingCycleMetadata.sol';
import {JBFundingCycleConfig} from '@juicebox/structs/JBFundingCycleConfig.sol';
import {JBGroupedSplits} from '@juicebox/structs/JBGroupedSplits.sol';
import {JBOperatorData} from '@juicebox/structs/JBOperatorData.sol';
import {JBPayParamsData} from '@juicebox/structs/JBPayParamsData.sol';
import {JBProjectMetadata} from '@juicebox/structs/JBProjectMetadata.sol';
import {JBRedeemParamsData} from '@juicebox/structs/JBRedeemParamsData.sol';
import {JBSplit} from '@juicebox/structs/JBSplit.sol';
import {JBTerminalConfig} from '@juicebox/structs/JBTerminalConfig.sol';
import {JBProjectMetadata} from '@juicebox/structs/JBProjectMetadata.sol';
import {JBGlobalFundingCycleMetadata} from '@juicebox/structs/JBGlobalFundingCycleMetadata.sol';
import {JBPayDelegateAllocation3_1_1} from '@juicebox/structs/JBPayDelegateAllocation3_1_1.sol';
import {JBTokenAmount} from '@juicebox/structs/JBTokenAmount.sol';
import {JBSplitAllocationData} from '@juicebox/structs/JBSplitAllocationData.sol';
import {IJBPaymentTerminal} from '@juicebox/interfaces/IJBPaymentTerminal.sol';
import {IJBToken} from '@juicebox/interfaces/IJBToken.sol';
import {JBSingleAllowanceData} from '@juicebox/structs/JBSingleAllowanceData.sol';
import {IJBController3_1} from '@juicebox/interfaces/IJBController3_1.sol';
import {IJBMigratable} from '@juicebox/interfaces/IJBMigratable.sol';
import {IJBOperatorStore} from '@juicebox/interfaces/IJBOperatorStore.sol';
import {IJBTerminalStore} from '@juicebox/interfaces/IJBTerminalStore.sol';
import {IJBProjects} from '@juicebox/interfaces/IJBProjects.sol';
import {IJBFundingCycleBallot} from '@juicebox/interfaces/IJBFundingCycleBallot.sol';
import {IJBDirectory} from '@juicebox/interfaces/IJBDirectory.sol';
import {IJBFundingCycleStore} from '@juicebox/interfaces/IJBFundingCycleStore.sol';
import {IJBSplitsStore} from '@juicebox/interfaces/IJBSplitsStore.sol';
import {IJBTokenStore} from '@juicebox/interfaces/IJBTokenStore.sol';
import {IJBSplitAllocator} from '@juicebox/interfaces/IJBSplitAllocator.sol';
import {IJBPayDelegate3_1_1} from '@juicebox/interfaces/IJBPayDelegate3_1_1.sol';
import {IJBFundingCycleDataSource3_1_1} from '@juicebox/interfaces/IJBFundingCycleDataSource3_1_1.sol';
import {IJBMultiTerminal} from '@juicebox/interfaces/IJBMultiTerminal.sol';
import {IJBPriceFeed} from '@juicebox/interfaces/IJBPriceFeed.sol';
import {IJBProjectPayer} from '@juicebox/interfaces/IJBProjectPayer.sol';
import {IJBOperatable} from '@juicebox/interfaces/IJBOperatable.sol';
import {IJBFundingCycleBallot} from '@juicebox/interfaces/IJBFundingCycleBallot.sol';
import {IJBPrices} from '@juicebox/interfaces/IJBPrices.sol';
import {IJBSplitsPayer} from '@juicebox/interfaces/IJBSplitsPayer.sol';

import {JBTokens} from '@juicebox/libraries/JBTokens.sol';
import {JBCurrencies} from '@juicebox/libraries/JBCurrencies.sol';
import {JBTokenStandards} from '@juicebox/libraries/JBTokenStandards.sol';
import {JBFundingCycleMetadataResolver} from '@juicebox/libraries/JBFundingCycleMetadataResolver.sol';
import {JBConstants} from '@juicebox/libraries/JBConstants.sol';
import {JBSplitsGroups} from '@juicebox/libraries/JBSplitsGroups.sol';
import {JBOperations} from '@juicebox/libraries/JBOperations.sol';

import {IPermit2, IAllowanceTransfer} from '@permit2/src/src/interfaces/IPermit2.sol';
import {DeployPermit2} from '@permit2/src/test/utils/DeployPermit2.sol';

import {MockERC20} from './../mock/MockERC20.sol';
// import './AccessJBLib.sol';

import '@paulrberg/contracts/math/PRBMath.sol';
import '@paulrberg/contracts/math/PRBMathUD60x18.sol';

// Base contract for Juicebox system tests.
// Provides common functionality, such as deploying contracts on test setup.
contract TestBaseWorkflow is Test, DeployPermit2 {
  // Multisig address used for testing.
  address private _multisig = address(123);
  address private _beneficiary = address(69420);
  MockERC20 private _usdcToken;
  address private _permit2;
  JBOperatorStore private _jbOperatorStore;
  JBProjects private _jbProjects;
  JBPrices private _jbPrices;
  JBDirectory private _jbDirectory;
  JBFundingCycleStore private _jbFundingCycleStore;
  //   JBToken private _jbToken;
  JBTokenStore private _jbTokenStore;
  JBSplitsStore private _jbSplitsStore;
  JBController3_1 private _jbController;
  JBFundAccessConstraintsStore private _jbFundAccessConstraintsStore;
  JBTerminalStore private _jbTerminalStore;
  JBMultiTerminal private _jbMultiTerminal;

  function multisig() internal view returns (address) {
    return _multisig;
  }

  function beneficiary() internal view returns (address) {
    return _beneficiary;
  }

  function usdcToken() internal view returns (MockERC20) {
    return _usdcToken;
  }

  function permit2() internal view returns (IPermit2) {
    return IPermit2(_permit2);
  }

  function jbOperatorStore() internal view returns (JBOperatorStore) {
    return _jbOperatorStore;
  }

  function jbProjects() internal view returns (JBProjects) {
    return _jbProjects;
  }

  function jbPrices() internal view returns (JBPrices) {
    return _jbPrices;
  }

  function jbDirectory() internal view returns (JBDirectory) {
    return _jbDirectory;
  }

  function jbFundingCycleStore() internal view returns (JBFundingCycleStore) {
    return _jbFundingCycleStore;
  }

  function jbTokenStore() internal view returns (JBTokenStore) {
    return _jbTokenStore;
  }

  function jbSplitsStore() internal view returns (JBSplitsStore) {
    return _jbSplitsStore;
  }

  function jbController() internal view returns (JBController3_1) {
    return _jbController;
  }

  function jbAccessConstraintStore() internal view returns (JBFundAccessConstraintsStore) {
    return _jbFundAccessConstraintsStore;
  }

  function jbTerminalStore() internal view returns (JBTerminalStore) {
    return _jbTerminalStore;
  }

  function jbPayoutRedemptionTerminal() internal view returns (JBMultiTerminal) {
    return _jbMultiTerminal;
  }

  //*********************************************************************//
  // --------------------------- test setup ---------------------------- //
  //*********************************************************************//

  // Deploys and initializes contracts for testing.
  function setUp() public virtual {
    vm.label(_multisig, 'projectOwner');
    vm.label(_beneficiary, 'beneficiary');
    _jbOperatorStore = new JBOperatorStore();
    vm.label(address(_jbOperatorStore), 'JBOperatorStore');
    _usdcToken = new MockERC20('USDC', 'USDC');
    vm.label(address(_usdcToken), 'ERC20');
    _jbProjects = new JBProjects(_jbOperatorStore, _multisig);
    vm.label(address(_jbProjects), 'JBProjects');
    _jbPrices = new JBPrices(_jbOperatorStore, _jbProjects, _multisig);
    vm.label(address(_jbPrices), 'JBPrices');
    address contractAtNoncePlusOne = addressFrom(address(this), 6);
    _jbFundingCycleStore = new JBFundingCycleStore(IJBDirectory(contractAtNoncePlusOne));
    vm.label(address(_jbFundingCycleStore), 'JBFundingCycleStore');
    _jbDirectory = new JBDirectory(_jbOperatorStore, _jbProjects, _jbFundingCycleStore, _multisig);
    vm.label(address(_jbDirectory), 'JBDirectory');
    _jbTokenStore = new JBTokenStore(
      _jbOperatorStore,
      _jbProjects,
      _jbDirectory,
      _jbFundingCycleStore
    );
    vm.label(address(_jbTokenStore), 'JBTokenStore');
    _jbSplitsStore = new JBSplitsStore(_jbOperatorStore, _jbProjects, _jbDirectory);
    vm.label(address(_jbSplitsStore), 'JBSplitsStore');
    _jbFundAccessConstraintsStore = new JBFundAccessConstraintsStore(_jbDirectory);
    vm.label(address(_jbFundAccessConstraintsStore), 'JBFundAccessConstraintsStore');
    _jbController = new JBController3_1(
      _jbOperatorStore,
      _jbProjects,
      _jbDirectory,
      _jbFundingCycleStore,
      _jbTokenStore,
      _jbSplitsStore,
      _jbFundAccessConstraintsStore
    );
    vm.label(address(_jbController), 'JBController3_1');

    vm.prank(_multisig);
    _jbDirectory.setIsAllowedToSetFirstController(address(_jbController), true);

    _jbTerminalStore = new JBTerminalStore(_jbDirectory, _jbFundingCycleStore, _jbPrices);
    vm.label(address(_jbTerminalStore), 'JBSingleTokenPaymentTerminalStore3_1_1');

    vm.prank(_multisig);
    _permit2 = deployPermit2();

    _jbMultiTerminal = new JBMultiTerminal(
      _jbOperatorStore,
      _jbProjects,
      _jbDirectory,
      _jbSplitsStore,
      _jbTerminalStore,
      IPermit2(_permit2),
      _multisig
    );

    vm.label(address(_jbMultiTerminal), 'JBMultiTerminal');
  }

  //https://ethereum.stackexchange.com/questions/24248/how-to-calculate-an-ethereum-contracts-address-during-its-creation-using-the-so
  function addressFrom(address _origin, uint256 _nonce) internal pure returns (address _address) {
    bytes memory data;
    if (_nonce == 0x00) {
      data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80));
    } else if (_nonce <= 0x7f) {
      data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, uint8(_nonce));
    } else if (_nonce <= 0xff) {
      data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce));
    } else if (_nonce <= 0xffff) {
      data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce));
    } else if (_nonce <= 0xffffff) {
      data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce));
    } else {
      data = abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce));
    }
    bytes32 hash = keccak256(data);
    assembly {
      mstore(0, hash)
      _address := mload(0)
    }
  }

  function strEqual(string memory a, string memory b) internal pure returns (bool) {
    return keccak256(abi.encode(a)) == keccak256(abi.encode(b));
  }
}
