// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@paulrberg/contracts/math/PRBMath.sol";
import "@paulrberg/contracts/math/PRBMathUD60x18.sol";

import "./helpers/TestBaseWorkflow.sol";

contract TestDistribute_Local is TestBaseWorkflow {
       JBController private _controller;
    JBETHPaymentTerminal private _terminal;
    JBTokenStore private _tokenStore;

    JBProjectMetadata private _projectMetadata;
    JBFundingCycleData private _data;
    JBFundingCycleMetadata private _metadata;
    // JBGroupedSplits[] private _groupedSplits; // Default empty
    JBFundAccessConstraints[] private _fundAccessConstraints; // Default empty
    IJBPaymentTerminal[] private _terminals; // Default empty

    uint256 private _projectId;
    address private _projectOwner;
    uint256 private _weight = 1000 * 10 ** 18;
    uint256 private _targetInWei = 10 * 10 ** 18;

    function setUp() public override {
        super.setUp();

        _controller = jbController();
        _tokenStore = jbTokenStore();

        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});

        _data = JBFundingCycleData({
            duration: 14,
            weight: _weight,
            discountRate: 450000000,
            ballot: IJBFundingCycleBallot(address(0))
        });

        _metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: 0,
            redemptionRate: 10000, //100%
            ballotRedemptionRate: 0,
            pausePay: false,
            pauseDistributions: false,
            pauseRedeem: false,
            pauseBurn: false,
            allowMinting: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: true,
            preferClaimedTokenOverride: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: false,
            useDataSourceForRedeem: false,
            dataSource: address(0),
            metadata: 0
        });

        _terminals.push(jbETHPaymentTerminal());
    }

    function testDistributeFundsOf_reverting_allocators() public {
        _projectOwner = multisig();

        uint256 n_reserved_split = 5;
        uint256 n_reverting_allocators = 2;
        uint256 _targetInWei = 10 ether;

        // Configure the grouped splits
        JBSplit[] memory _split = new JBSplit[](n_reserved_split);
        for (uint256 i = 0; i < n_reserved_split; i++) {
            if (i >= n_reverting_allocators ) {
               address _user = vm.addr(i + 1);
                _split[i] = JBSplit({
                    preferClaimed: false,
                    preferAddToBalance: false,
                    percent: JBConstants.SPLITS_TOTAL_PERCENT / n_reserved_split,
                    projectId: 0,
                    beneficiary: payable(_user),
                    lockedUntil: 0,
                    allocator: IJBSplitAllocator(address(0))
                }); 
            }else{
                _split[i] = JBSplit({
                    preferClaimed: false,
                    preferAddToBalance: false,
                    percent: JBConstants.SPLITS_TOTAL_PERCENT / n_reserved_split,
                    projectId: 0,
                    beneficiary: payable(address(0)),
                    lockedUntil: 0,
                    allocator: new MockRevertingAllocator()
                }); 
            }
        }

        JBGroupedSplits[] memory _groupedSplits = new JBGroupedSplits[](1);
        _groupedSplits[0] = JBGroupedSplits({group: JBSplitsGroups.ETH_PAYOUT, splits: _split});

        _fundAccessConstraints.push(
            JBFundAccessConstraints({
                terminal: jbETHPaymentTerminal(),
                token: jbLibraries().ETHToken(),
                distributionLimit: _targetInWei, // 10 ETH target
                overflowAllowance: 5 ether,
                distributionLimitCurrency: 1, // Currency = ETH
                overflowAllowanceCurrency: 1
            })
        );

        // Launch the project
        _projectId = _controller.launchProjectFor(
            _projectOwner,
            _projectMetadata,
            _data,
            _metadata,
            block.timestamp,
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );

        // Fund the project
        jbETHPaymentTerminal()
            .addToBalanceOf{value: _targetInWei}(
                _projectId,
                _targetInWei,
                JBTokens.ETH,
                '',
                bytes('')
            );
        
        // If the terminal/controller is v3_0 then this will revert the entire call
        if(isUsingJbController3_0()){
             vm.expectRevert("ALLOCATOR_REVERT");

             // Distribute the funds
            jbETHPaymentTerminal()
            .distributePayoutsOf(
                _projectId,
                _targetInWei,
                JBCurrencies.ETH,
                JBTokens.ETH,
                _targetInWei,
                ''
            );
        }else{
            // TODO: test the JB terminal 3_1
        }
    }
}

contract MockRevertingAllocator is IJBSplitAllocator {
    function allocate(JBSplitAllocationData calldata _data) external payable {
        revert("ALLOCATOR_REVERT");
    }

     function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return true; // This doesn't matter here
     }
}