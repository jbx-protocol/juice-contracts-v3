// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

import {JBETHPaymentTerminal3_1_2} from "../contracts/JBETHPaymentTerminal3_1_2.sol";
import {IJBFeeGauge3_1, JBFeeType} from "../contracts/interfaces/IJBFeeGauge3_1.sol";
import {JBCurrencyAmount} from "../contracts/structs/JBCurrencyAmount.sol";
import {JBCurrencies} from "../contracts/libraries/JBCurrencies.sol";

contract TestTerminal312HeldFee_Local is TestBaseWorkflow {
    JBController3_1 private _controller;
    JBETHPaymentTerminal3_1_2 private _terminal;
    JBTokenStore private _tokenStore;

    JBProjectMetadata private _projectMetadata;
    JBFundingCycleData private _data;
    JBFundingCycleMetadata _metadata;
    JBGroupedSplits[] private _groupedSplits; // Default empty
    IJBPaymentTerminal[] private _terminals; // Default empty
    address private _multisig;

    uint256 private _projectId;
    address private _projectOwner;
    uint256 private _weight = 1000 * 10 ** 18;
    uint256 private _targetInWei = 10 * 10 ** 18;

    function setUp() public override {
        super.setUp();

        _controller = jbController();
        _multisig = multisig();
        _terminal = new JBETHPaymentTerminal3_1_2(
            jbOperatorStore(),
            jbProjects(),
            jbDirectory(),
            jbSplitsStore(),
            jbPrices(),
            address(jbPaymentTerminalStore()),
            multisig()
        );

        _tokenStore = jbTokenStore();

        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});

        _data = JBFundingCycleData({
            duration: 14,
            weight: _weight,
            discountRate: 450_000_000,
            ballot: IJBFundingCycleBallot(address(0))
        });

        _metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: 0,
            redemptionRate: 10_000, //100%
            baseCurrency: 1,
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

        _terminals.push(_terminal);

        JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](1);
        _distributionLimits[0] = JBCurrencyAmount({value: _targetInWei, currency: JBCurrencies.ETH});

        JBCurrencyAmount[] memory _overflowAllowance = new JBCurrencyAmount[](1);
        _overflowAllowance[0] = JBCurrencyAmount({value: 5 ether, currency: JBCurrencies.ETH});

        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        _fundAccessConstraints[0] = JBFundAccessConstraints({
            terminal: _terminal,
            token: jbLibraries().ETHToken(),
            distributionLimits: _distributionLimits,
            overflowAllowances: _overflowAllowance
        });

        _projectOwner = multisig();

        JBFundingCycleConfiguration[] memory _cycleConfig = new JBFundingCycleConfiguration[](1);

        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        _projectId = _controller.launchProjectFor(
            _projectOwner, _projectMetadata, _cycleConfig, _terminals, ""
        );
    }

    function testHeldFeeReimburse_simple(uint256 payAmountInWei, uint256 fee) external {
        // Assuming we don't revert when distributing too much and avoid rounding errors
        payAmountInWei = bound(payAmountInWei, 10, _targetInWei);
        fee = bound(fee, 1, 50_000_000);

        address _userWallet = makeAddr("userWallet");

        vm.prank(multisig());
        _terminal.setFee(fee);

        // -- pay --
        _terminal.pay{value: payAmountInWei}(
            _projectId,
            payAmountInWei,
            address(0),
            /* _beneficiary */
            _userWallet,
            /* _minReturnedTokens */
            0,
            /* _preferClaimedTokens */
            false,
            /* _memo */
            "Take my money!",
            /* _delegateMetadata */
            new bytes(0)
        );

        // verify: beneficiary should have a balance of JBTokens
        uint256 _userTokenBalance = PRBMathUD60x18.mul(payAmountInWei, _weight);
        assertEq(_tokenStore.balanceOf(_userWallet, _projectId), _userTokenBalance);

        // verify: ETH balance in terminal should be up to date
        uint256 _terminalBalanceInWei = payAmountInWei;
        assertEq(jbPaymentTerminalStore().balanceOf(_terminal, _projectId), _terminalBalanceInWei);

        // -- distribute --
        IJBPayoutRedemptionPaymentTerminal3_1(address(_terminal)).distributePayoutsOf(
            _projectId,
            payAmountInWei,
            jbLibraries().ETH(),
            address(0), //token (unused)
            /*min out*/
            0,
            ""
        );

        uint256 _ethDistributed = _terminalBalanceInWei - address(_terminal).balance;
        assertEq(_multisig.balance, _ethDistributed, "Wrong ETH distributed");

        // verify: should have held the fee, if there is one
        if (fee > 0) {
            assertEq(_terminal.heldFeesOf(_projectId)[0].fee, _terminal.fee(), "Wrong fee");
            assertEq(
                _terminal.heldFeesOf(_projectId)[0].amount,
                payAmountInWei,
                "Wrong payout amount in held fee"
            );
        } else {
            assertEq(_terminal.heldFeesOf(_projectId).length, 0, "Extranumerous held fees");
        }

        // -- add to balance --
        // Will get the fee reimbursed:
        uint256 heldFee = payAmountInWei * fee / jbLibraries().MAX_FEE();
        uint256 balanceBefore = jbPaymentTerminalStore().balanceOf(_terminal, _projectId);

        IJBFeeHoldingTerminal(address(_terminal)).addToBalanceOf{value: _ethDistributed}(
            _projectId,
            _ethDistributed,
            address(0),
            /* _shouldRefundHeldFees */
            true,
            "thanks for all the fish",
            /* _delegateMetadata */
            new bytes(0)
        );

        // Check: held fee should be gone
        assertEq(_terminal.heldFeesOf(_projectId).length, 0, "Extranumerous held fees");

        // Check: balance made whole again
        assertEq(
            jbPaymentTerminalStore().balanceOf(_terminal, _projectId),
            balanceBefore + payAmountInWei,
            "Wrong project end balance"
        );
    }
}
