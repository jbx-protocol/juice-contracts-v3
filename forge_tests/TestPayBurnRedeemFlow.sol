// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

// Project can issue token, receive payments in exchange for tokens, burn some of the claimed tokens, allow holders to redeem rest of tokens.
contract TestPayBurnRedeemFlow_Local is TestBaseWorkflow {
    IJBController3_1 private _controller;
    IJBPaymentTerminal private _terminal;
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
        _terminal = jbPayoutRedemptionTerminal();
        _tokenStore = jbTokenStore();
        _data = JBFundingCycleData({
            duration: 0,
            weight: 1000 * 10 ** 18,
            discountRate: 0,
            ballot: JBReconfigurationBufferBallot(address(0))
        });
        _metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: 0,
            redemptionRate: JBConstants.MAX_REDEMPTION_RATE,
            baseCurrency: uint32(uint160(JBTokens.ETH)),
            pausePay: false,
            allowMinting: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: false,
            useDataSourceForRedeem: false,
            dataSource: address(0),
            metadata: 0
        });

        IJBPaymentTerminal[] memory _terminals = new IJBPaymentTerminal[](1);
        _terminals[0] = (_terminal);

        // Package up cycle config.
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = new JBGroupedSplits[](0);
        _cycleConfig[0].fundAccessConstraints = new JBFundAccessConstraints[](0);

        // Package up terminal config.
        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](1);
        _accountingContexts[0] =
            JBAccountingContextConfig({token: JBTokens.ETH, standard: JBTokenStandards.NATIVE});
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: _terminal, accountingContextConfigs: _accountingContexts});

        // dummy project that will receive fees
        _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 1}),
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        _projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 1}),
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
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
            token: JBTokens.ETH, //unused
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: new bytes(0)
        });

        // Make sure the beneficiary should have a balance of JBTokens.
        uint256 _beneficiaryTokenBalance = PRBMathUD60x18.mul(_ethPayAmount, _data.weight);
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Make sure the ETH balance in terminal is up to date.
        uint256 _terminalBalance = _ethPayAmount;
        assertEq(
            jbTerminalStore().balanceOf(
                IJBPaymentTerminal(address(_terminal)), _projectId, JBTokens.ETH
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
            memo: "I hate tokens!"
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
            token: JBTokens.ETH, // unused
            count: _redeemTokenAmount,
            minReclaimed: 0,
            beneficiary: payable(_beneficiary),
            metadata: new bytes(0)
        });

        // Make sure the beneficiary has a new balance of JBTokens.
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Make sure the ETH balance in terminal is up to date.
        assertEq(
            jbTerminalStore().balanceOf(
                IJBPaymentTerminal(address(_terminal)), _projectId, JBTokens.ETH
            ),
            _terminalBalance - _reclaimAmt
        );
    }
}
