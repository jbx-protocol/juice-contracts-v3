// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';

import './interfaces/IJBGasTokenERC20SplitsPayerDeployer.sol';
import './structs/JBSplit.sol';
import './structs/JBGroupedSplits.sol';
import './JBGasTokenERC20SplitsPayer.sol';

/** 
  @notice 
  Deploys splits payer contracts.

  @dev
  Adheres to -
  IJBGasTokenERC20SplitsPayerDeployer:  General interface for the methods in this contract that interact with the blockchain's state according to the protocol's rules.
*/
contract JBGasTokenERC20SplitsPayerDeployer is IJBGasTokenERC20SplitsPayerDeployer {
  address immutable implementation;

  IJBSplitsStore immutable splitsStore;

  constructor(IJBSplitsStore _splitsStore) {
    implementation = address(new JBGasTokenERC20SplitsPayer(_splitsStore));
    splitsStore = _splitsStore;
  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /** 
    @notice 
    Allows anyone to deploy a new splits payer contract.

    @dev
    This contract must have Operator permissions over the SET_SPLITS permission of the specified `_defaultSplitsProjectId`.

    @param _defaultSplitsProjectId The ID of project for which the default splits are stored.
    @param _defaultSplits The splits to payout when this contract receives direct payments.
    @param _splitsStore A contract that stores splits for each project.
    @param _defaultProjectId The ID of the project whose treasury should be forwarded the splits payer contract's received payment leftovers after distributing to the default splits group.
    @param _defaultBeneficiary The address that'll receive the project's tokens when the splits payer receives payments. 
    @param _defaultPreferClaimedTokens A flag indicating whether issued tokens from the splits payer's received payments should be automatically claimed into the beneficiary's wallet. 
    @param _defaultMemo The memo that'll be forwarded with the splits payer's received payments. 
    @param _defaultMetadata The metadata that'll be forwarded with the splits payer's received payments. 
    @param _defaultPreferAddToBalance A flag indicating if received payments should call the `pay` function or the `addToBalance` function of a project.
    @param _owner The address that will own the splits payer.

    @return splitsPayer The splits payer contract.
  */
  function deploySplitsPayerWithSplits(
    uint256 _defaultSplitsProjectId,
    JBSplit[] memory _defaultSplits,
    IJBSplitsStore _splitsStore,
    uint256 _defaultProjectId,
    address payable _defaultBeneficiary,
    bool _defaultPreferClaimedTokens,
    string memory _defaultMemo,
    bytes memory _defaultMetadata,
    bool _defaultPreferAddToBalance,
    address _owner
  ) external override returns (IJBSplitsPayer splitsPayer) {
    // Use this contract's address as the domain.
    uint256 _domain = uint256(uint160(address(this)));

    // Create the random hash using data unique to this instance that'll be used as the storage domain.
    uint256 _group = uint256(keccak256(abi.encodePacked(msg.sender, block.number)));

    // Set the splits in the store.
    JBGroupedSplits[] memory _groupedSplits;
    _groupedSplits = new JBGroupedSplits[](1);
    _groupedSplits[0] = JBGroupedSplits(_group, _defaultSplits);
    _splitsStore.set(_defaultSplitsProjectId, _domain, _groupedSplits);

    return
      deploySplitsPayer(
        _defaultSplitsProjectId,
        _domain,
        _group,
        _defaultProjectId,
        _defaultBeneficiary,
        _defaultPreferClaimedTokens,
        _defaultMemo,
        _defaultMetadata,
        _defaultPreferAddToBalance,
        _owner
      );
  }

  //*********************************************************************//
  // ---------------------- public transactions ---------------------- //
  //*********************************************************************//

  /** 
    @notice 
    Allows anyone to deploy a new splits payer contract.

    @param _defaultSplitsProjectId The ID of project for which the default splits are stored.
    @param _defaultSplitsDomain The splits domain to payout when this contract receives direct payments.
    @param _defaultSplitsGroup The splits group to payout when this contract receives direct payments.
    @param _defaultProjectId The ID of the project whose treasury should be forwarded the splits payer contract's received payment leftovers after distributing to the default splits group.
    @param _defaultBeneficiary The address that'll receive the project's tokens when the splits payer receives payments. 
    @param _defaultPreferClaimedTokens A flag indicating whether issued tokens from the splits payer's received payments should be automatically claimed into the beneficiary's wallet. 
    @param _defaultMemo The memo that'll be forwarded with the splits payer's received payments. 
    @param _defaultMetadata The metadata that'll be forwarded with the splits payer's received payments. 
    @param _defaultPreferAddToBalance A flag indicating if received payments should call the `pay` function or the `addToBalance` function of a project.
    @param _owner The address that will own the splits payer.

    @return splitsPayer The splits payer contract.
  */
  function deploySplitsPayer(
    uint256 _defaultSplitsProjectId,
    uint256 _defaultSplitsDomain,
    uint256 _defaultSplitsGroup,
    uint256 _defaultProjectId,
    address payable _defaultBeneficiary,
    bool _defaultPreferClaimedTokens,
    string memory _defaultMemo,
    bytes memory _defaultMetadata,
    bool _defaultPreferAddToBalance,
    address _owner
  ) public override returns (IJBSplitsPayer splitsPayer) {
    // Deploy the splits payer.
    splitsPayer = IJBSplitsPayer(payable(Clones.clone(implementation)));

    splitsPayer.initialize(
      _defaultSplitsProjectId,
      _defaultSplitsDomain,
      _defaultSplitsGroup,
      _defaultProjectId,
      _defaultBeneficiary,
      _defaultPreferClaimedTokens,
      _defaultMemo,
      _defaultMetadata,
      _defaultPreferAddToBalance,
      _owner
    );

    emit DeploySplitsPayer(
      splitsPayer,
      _defaultSplitsProjectId,
      _defaultSplitsDomain,
      _defaultSplitsGroup,
      splitsStore,
      _defaultProjectId,
      _defaultBeneficiary,
      _defaultPreferClaimedTokens,
      _defaultMemo,
      _defaultMetadata,
      _defaultPreferAddToBalance,
      _owner,
      msg.sender
    );
  }
}
