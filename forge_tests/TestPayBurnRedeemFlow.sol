// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

// Project can issue token, receive payments in exchange for tokens, burn some of the claimed tokens, allow holders to redeem rest of tokens.
contract TestPayBurnRedeemFlow_Local is TestBaseWorkflow {
    IJBController3_1 private _controller;
    IJBPayoutRedemptionPaymentTerminal3_1 private _terminal;
    JBTokenStore private _tokenStore;
    JBFundingCycleData private _data;
    JBFundingCycleMetadata _metadata;
    uint256 private _projectId;
    address private _projectOwner;
    address private _beneficiary;

    function setUp() public override {
        super.setUp();

        _projectOwner = multisig();
        _beneficiary = beneficiary();
        _controller = jbController();
        _terminal = jbETHPaymentTerminal();
        _tokenStore = jbTokenStore();
        _data = JBFundingCycleData({
            duration: 0,
            weight: 1000 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });
        _metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: 0,
            redemptionRate: jbLibraries().MAX_REDEMPTION_RATE(), //100%
            baseCurrency: 1,
            pausePay: false,
            pauseDistributions: false,
            pauseRedeem: false,
            pauseBurn: false,
            allowMinting: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            preferClaimedTokenOverride: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: false,
            useDataSourceForRedeem: false,
            dataSource: address(0),
            metadata: 0
        });

        IJBPaymentTerminal[] memory _terminals = new IJBPaymentTerminal[](1);
        _terminals[0] = (_terminal);

        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](1);
        JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);

        _distributionLimits[0] = JBCurrencyAmount({value: 0, currency: jbLibraries().ETH()});

        _overflowAllowances[0] = JBCurrencyAmount({value: 0, currency: jbLibraries().ETH()});

        _fundAccessConstraints[0] = JBFundAccessConstraints({
            terminal: _terminal,
            token: jbLibraries().ETHToken(),
            distributionLimits: _distributionLimits,
            overflowAllowances: _overflowAllowances
        });

        JBFundingCycleConfiguration[] memory _cycleConfig = new JBFundingCycleConfiguration[](1);

        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = new JBGroupedSplits[](0);
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Make a dummy project that'll receive fees.
        _controller.launchProjectFor({
            owner: address(420), // random
            projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 1}),
            configurations: new JBFundingCycleConfiguration[](0),
            terminals: new IJBPaymentTerminal[](0),
            memo: ""
        });

        _projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 1}),
            configurations: _cycleConfig,
            terminals: _terminals,
            memo: ""
        });
    }

    function testFuzzPayBurnRedeemFlow(
        bool _payPreferClaimed,
        bool _burnPreferClaimed,
        uint96 _ethPayAmount,
        uint256 _burnTokenAmount,
        uint256 _redeemTokenAmount
    ) external {
        // Issue an ERC-20 token for project.
        vm.prank(_projectOwner);
        _tokenStore.issueFor(_projectId, "TestName", "TestSymbol");

        // Make a payment.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId,
            amount: _ethPayAmount,
            token: address(0), //unused
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            preferClaimedTokens: _payPreferClaimed,
            memo: "Take my money!",
            metadata: new bytes(0)
        });

        // Make sure the beneficiary should have a balance of JBTokens.
        uint256 _beneficiaryTokenBalance = PRBMathUD60x18.mul(_ethPayAmount, _data.weight);
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Make sure the ETH balance in terminal is up to date.
        uint256 _terminalBalance = _ethPayAmount;
        assertEq(
            jbPaymentTerminalStore().balanceOf(
                IJBSingleTokenPaymentTerminal(address(_terminal)), _projectId
            ),
            _terminalBalance
        );

        // Burn tokens from beneficiary.
        if (_burnTokenAmount == 0) {
            vm.expectRevert(abi.encodeWithSignature("NO_BURNABLE_TOKENS()"));
        } else if (_burnTokenAmount > _beneficiaryTokenBalance) {
            vm.expectRevert(abi.encodeWithSignature("INSUFFICIENT_FUNDS()"));
        } else {
            _beneficiaryTokenBalance = _beneficiaryTokenBalance - _burnTokenAmount;
        }

        vm.prank(_beneficiary);
        _controller.burnTokensOf({
            holder: _beneficiary,
            projectId: _projectId,
            tokenCount: _burnTokenAmount,
            memo: "I hate tokens!",
            preferClaimedTokens: _burnPreferClaimed
        });

        // verify: beneficiary should have a new balance of JBTokens
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Redeem tokens.
        if (_redeemTokenAmount > _beneficiaryTokenBalance) {
            vm.expectRevert(abi.encodeWithSignature("INSUFFICIENT_TOKENS()"));
        } else {
            _beneficiaryTokenBalance = _beneficiaryTokenBalance - _redeemTokenAmount;
        }

        vm.prank(_beneficiary);
        uint256 _reclaimAmt = _terminal.redeemTokensOf({
            holder: _beneficiary,
            projectId: _projectId,
            tokenCount: _redeemTokenAmount,
            token: address(0), // unused
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary),
            memo: "Refund me now!",
            metadata: new bytes(0)
        });

        // Make sure the beneficiary has a new balance of JBTokens.
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Make sure the ETH balance in terminal is up to date.
        assertEq(
            jbPaymentTerminalStore().balanceOf(
                IJBSingleTokenPaymentTerminal(address(_terminal)), _projectId
            ),
            _terminalBalance - _reclaimAmt
        );
    }
}
