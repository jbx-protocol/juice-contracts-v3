// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "forge-std/Test.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {JBController} from "@juicebox/JBController.sol";
import {JBDirectory} from "@juicebox/JBDirectory.sol";
import {JBTerminalStore} from "@juicebox/JBTerminalStore.sol";
import {JBFundAccessConstraintsStore} from "@juicebox/JBFundAccessConstraintsStore.sol";
import {JBRulesets} from "@juicebox/JBRulesets.sol";
import {JBOperatorStore} from "@juicebox/JBOperatorStore.sol";
import {JBPrices} from "@juicebox/JBPrices.sol";
import {JBProjects} from "@juicebox/JBProjects.sol";
import {JBSplitsStore} from "@juicebox/JBSplitsStore.sol";
import {JBERC20Token} from "@juicebox/JBERC20Token.sol";
import {JBTokens} from "@juicebox/JBTokens.sol";
import {JBDeadline} from "@juicebox/JBDeadline.sol";
import {JBMultiTerminal} from "@juicebox/JBMultiTerminal.sol";
import {JBCurrencyAmount} from "@juicebox/structs/JBCurrencyAmount.sol";
import {JBAccountingContextConfig} from "@juicebox/structs/JBAccountingContextConfig.sol";
import {JBDidPayData} from "@juicebox/structs/JBDidPayData.sol";
import {JBDidRedeemData} from "@juicebox/structs/JBDidRedeemData.sol";
import {JBFee} from "@juicebox/structs/JBFee.sol";
import {JBFees} from "@juicebox/libraries/JBFees.sol";
import {JBFundAccessConstraints} from "@juicebox/structs/JBFundAccessConstraints.sol";
import {JBRuleset} from "@juicebox/structs/JBRuleset.sol";
import {JBRulesetData} from "@juicebox/structs/JBRulesetData.sol";
import {JBRulesetMetadata} from "@juicebox/structs/JBRulesetMetadata.sol";
import {JBRulesetConfig} from "@juicebox/structs/JBRulesetConfig.sol";
import {JBGroupedSplits} from "@juicebox/structs/JBGroupedSplits.sol";
import {JBOperatorData} from "@juicebox/structs/JBOperatorData.sol";
import {JBPayParamsData} from "@juicebox/structs/JBPayParamsData.sol";
import {JBProjectMetadata} from "@juicebox/structs/JBProjectMetadata.sol";
import {JBRedeemParamsData} from "@juicebox/structs/JBRedeemParamsData.sol";
import {JBSplit} from "@juicebox/structs/JBSplit.sol";
import {JBTerminalConfig} from "@juicebox/structs/JBTerminalConfig.sol";
import {JBProjectMetadata} from "@juicebox/structs/JBProjectMetadata.sol";
import {JBGlobalRulesetMetadata} from "@juicebox/structs/JBGlobalRulesetMetadata.sol";
import {JBPayDelegateAllocation} from "@juicebox/structs/JBPayDelegateAllocation.sol";
import {JBTokenAmount} from "@juicebox/structs/JBTokenAmount.sol";
import {JBSplitAllocationData} from "@juicebox/structs/JBSplitAllocationData.sol";
import {IJBPaymentTerminal} from "@juicebox/interfaces/IJBPaymentTerminal.sol";
import {IJBToken} from "@juicebox/interfaces/IJBToken.sol";
import {JBSingleAllowanceData} from "@juicebox/structs/JBSingleAllowanceData.sol";
import {IJBController} from "@juicebox/interfaces/IJBController.sol";
import {IJBMigratable} from "@juicebox/interfaces/IJBMigratable.sol";
import {IJBOperatorStore} from "@juicebox/interfaces/IJBOperatorStore.sol";
import {IJBTerminalStore} from "@juicebox/interfaces/IJBTerminalStore.sol";
import {IJBProjects} from "@juicebox/interfaces/IJBProjects.sol";
import {IJBRulesetApprovalHook} from "@juicebox/interfaces/IJBRulesetApprovalHook.sol";
import {IJBDirectory} from "@juicebox/interfaces/IJBDirectory.sol";
import {IJBRulesets} from "@juicebox/interfaces/IJBRulesets.sol";
import {IJBSplitsStore} from "@juicebox/interfaces/IJBSplitsStore.sol";
import {IJBTokens} from "@juicebox/interfaces/IJBTokens.sol";
import {IJBSplitAllocator} from "@juicebox/interfaces/IJBSplitAllocator.sol";
import {IJBPayDelegate} from "@juicebox/interfaces/IJBPayDelegate.sol";
import {IJBRulesetDataSource} from "@juicebox/interfaces/IJBRulesetDataSource.sol";
import {IJBMultiTerminal} from "@juicebox/interfaces/IJBMultiTerminal.sol";
import {IJBPriceFeed} from "@juicebox/interfaces/IJBPriceFeed.sol";
import {IJBOperatable} from "@juicebox/interfaces/IJBOperatable.sol";
import {IJBRulesetApprovalHook} from "@juicebox/interfaces/IJBRulesetApprovalHook.sol";
import {IJBPrices} from "@juicebox/interfaces/IJBPrices.sol";

import {JBTokenList} from "@juicebox/libraries/JBTokenList.sol";
import {JBCurrencies} from "@juicebox/libraries/JBCurrencies.sol";
import {JBTokenStandards} from "@juicebox/libraries/JBTokenStandards.sol";
import {JBRulesetMetadataResolver} from "@juicebox/libraries/JBRulesetMetadataResolver.sol";
import {JBConstants} from "@juicebox/libraries/JBConstants.sol";
import {JBSplitsGroups} from "@juicebox/libraries/JBSplitsGroups.sol";
import {JBOperations} from "@juicebox/libraries/JBOperations.sol";

import {IPermit2, IAllowanceTransfer} from "@permit2/src/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "@permit2/src/test/utils/DeployPermit2.sol";

import {MockERC20} from "./../mock/MockERC20.sol";
// import './AccessJBLib.sol';

import "@paulrberg/contracts/math/PRBMath.sol";
import "@paulrberg/contracts/math/PRBMathUD60x18.sol";

// Base contract for Juicebox system tests.
// Provides common functionality, such as deploying contracts on test setup.
contract TestBaseWorkflow is Test, DeployPermit2 {
    // Multisig address used for testing.
    address private _multisig = address(123);
    address private _beneficiary = address(69_420);
    MockERC20 private _usdcToken;
    address private _permit2;
    JBOperatorStore private _jbOperatorStore;
    JBProjects private _jbProjects;
    JBPrices private _jbPrices;
    JBDirectory private _jbDirectory;
    JBRulesets private _jbRulesetStore;
    //   JBERC20Token private _jbToken;
    JBTokens private _jbTokens;
    JBSplitsStore private _jbSplitsStore;
    JBController private _jbController;
    JBFundAccessConstraintsStore private _jbFundAccessConstraintsStore;
    JBTerminalStore private _jbTerminalStore;
    JBMultiTerminal private _jbMultiTerminal;
    JBMultiTerminal private _jbMultiTerminal2;

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

    function jbRulesetStore() internal view returns (JBRulesets) {
        return _jbRulesetStore;
    }

    function jbTokens() internal view returns (JBTokens) {
        return _jbTokens;
    }

    function jbSplitsStore() internal view returns (JBSplitsStore) {
        return _jbSplitsStore;
    }

    function jbController() internal view returns (JBController) {
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

    function jbPayoutRedemptionTerminal2() internal view returns (JBMultiTerminal) {
        return _jbMultiTerminal2;
    }

    //*********************************************************************//
    // --------------------------- test setup ---------------------------- //
    //*********************************************************************//

    // Deploys and initializes contracts for testing.
    function setUp() public virtual {
        vm.label(_multisig, "projectOwner");
        vm.label(_beneficiary, "beneficiary");
        _jbOperatorStore = new JBOperatorStore();
        vm.label(address(_jbOperatorStore), "JBOperatorStore");
        _usdcToken = new MockERC20("USDC", "USDC");
        vm.label(address(_usdcToken), "ERC20");
        _jbProjects = new JBProjects(_jbOperatorStore, _multisig);
        vm.label(address(_jbProjects), "JBProjects");
        _jbPrices = new JBPrices(_jbOperatorStore, _jbProjects, _multisig);
        vm.label(address(_jbPrices), "JBPrices");
        address contractAtNoncePlusOne = addressFrom(address(this), 6);
        _jbRulesetStore = new JBRulesets(
            IJBDirectory(contractAtNoncePlusOne)
        );
        vm.label(address(_jbRulesetStore), "JBRulesets");
        _jbDirectory = new JBDirectory(
            _jbOperatorStore,
            _jbProjects,
            _jbRulesetStore,
            _multisig
        );
        vm.label(address(_jbDirectory), "JBDirectory");
        _jbTokens = new JBTokens(
            _jbOperatorStore,
            _jbProjects,
            _jbDirectory,
            _jbRulesetStore
        );
        vm.label(address(_jbTokens), "JBTokens");
        _jbSplitsStore = new JBSplitsStore(
            _jbOperatorStore,
            _jbProjects,
            _jbDirectory
        );
        vm.label(address(_jbSplitsStore), "JBSplitsStore");
        _jbFundAccessConstraintsStore = new JBFundAccessConstraintsStore(
            _jbDirectory
        );
        vm.label(address(_jbFundAccessConstraintsStore), "JBFundAccessConstraintsStore");
        _jbController = new JBController(
            _jbOperatorStore,
            _jbProjects,
            _jbDirectory,
            _jbRulesetStore,
            _jbTokens,
            _jbSplitsStore,
            _jbFundAccessConstraintsStore
        );
        vm.label(address(_jbController), "JBController");

        vm.prank(_multisig);
        _jbDirectory.setIsAllowedToSetFirstController(address(_jbController), true);

        _jbTerminalStore = new JBTerminalStore(
            _jbDirectory,
            _jbRulesetStore,
            _jbPrices
        );
        vm.label(address(_jbTerminalStore), "JBSingleTokenPaymentTerminalStore");

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
        vm.label(address(_jbMultiTerminal), "JBMultiTerminal");
        _jbMultiTerminal2 = new JBMultiTerminal(
        _jbOperatorStore,
        _jbProjects,
        _jbDirectory,
        _jbSplitsStore,
        _jbTerminalStore,
        IPermit2(_permit2),
        _multisig
        );
        vm.label(address(_jbMultiTerminal2), "JBMultiTerminal2");
    }

    //https://ethereum.stackexchange.com/questions/24248/how-to-calculate-an-ethereum-contracts-address-during-its-creation-using-the-so
    function addressFrom(address _origin, uint256 _nonce)
        internal
        pure
        returns (address _address)
    {
        bytes memory data;
        if (_nonce == 0x00) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80));
        } else if (_nonce <= 0x7f) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, uint8(_nonce));
        } else if (_nonce <= 0xff) {
            data =
                abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce));
        } else if (_nonce <= 0xffff) {
            data =
                abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce));
        } else if (_nonce <= 0xffffff) {
            data =
                abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce));
        } else {
            data =
                abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce));
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
