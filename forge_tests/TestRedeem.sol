// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

// Projects can issue a token, be paid to receieve claimed tokens,  burn some of the claimed tokens, redeem rest of tokens
contract TestRedeem_Local is TestBaseWorkflow {
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
            ballot: IJBFundingCycleBallot(address(0))
        });
        _metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: 0,
            redemptionRate: JBConstants.MAX_REDEMPTION_RATE / 2,
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

        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = new JBGroupedSplits[](0);
        _cycleConfig[0].fundAccessConstraints = new JBFundAccessConstraints[](0);

        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
            JBAccountingContextConfig[] memory _accountingContextConfigs =
                new JBAccountingContextConfig[](1);
            _accountingContextConfigs[0] =
                JBAccountingContextConfig({token: JBTokens.ETH, standard: JBTokenStandards.NATIVE});
            _terminalConfigurations[0] = JBTerminalConfig({
                terminal: _terminal,
                accountingContextConfigs: _accountingContextConfigs
            });

        // First project for fee collection
        _controller.launchProjectFor({
            owner: address(420), // random
            projectMetadata: JBProjectMetadata({content: "whatever", domain: 0}),
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations, // set terminals where fees will be received
            memo: ""
        });

        // Create the project to test.
        _projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 1}),
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });
    }

    function testRedeem(uint256 _tokenAmountToRedeem) external {
        bool _payPreferClaimed = true;
        uint96 _ethPayAmount = 10 ether;

        // Issue the project's tokens.
        vm.prank(_projectOwner);
        IJBToken _token = _tokenStore.issueFor(_projectId, "TestName", "TestSymbol");

        // Pay the project.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId,
            amount: _ethPayAmount,
            token: JBTokens.ETH,
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: new bytes(0)
        });

        // Make sure the beneficiary has a balance of tokens.
        uint256 _beneficiaryTokenBalance = PRBMathUD60x18.mul(_ethPayAmount, _data.weight);
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Make sure the ETH balance in terminal is up to date.
        uint256 _ethTerminalBalance = _ethPayAmount;
        assertEq(
            jbTerminalStore().balanceOf(
                IJBPaymentTerminal(address(_terminal)), _projectId, JBTokens.ETH
            ),
            _ethTerminalBalance
        );

        // Fuzz 1 to full balance redemption.
        _tokenAmountToRedeem = bound(_tokenAmountToRedeem, 1, _beneficiaryTokenBalance);

        // Test: redeem
        vm.prank(_beneficiary);
        uint256 _ethReclaimAmt = _terminal.redeemTokensOf({
            holder: _beneficiary,
            projectId: _projectId,
            token: JBTokens.ETH,
            count: _tokenAmountToRedeem,
            minReclaimed: 0,
            beneficiary: payable(_beneficiary),
            metadata: new bytes(0)
        });

        // Keep a reference to the expected amount redeemed.
        uint256 _grossRedeemed = PRBMath.mulDiv(
            PRBMath.mulDiv(_ethTerminalBalance, _tokenAmountToRedeem, _beneficiaryTokenBalance),
            _metadata.redemptionRate
                + PRBMath.mulDiv(
                    _tokenAmountToRedeem,
                    JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                    _beneficiaryTokenBalance
                ),
            JBConstants.MAX_REDEMPTION_RATE
        );

        // Compute the fee taken.
        uint256 _fee = _grossRedeemed
            - PRBMath.mulDiv(_grossRedeemed, 1_000_000_000, 25_000_000 + 1_000_000_000); // 2.5% fee

        // Compute the net amount received, still in $project
        uint256 _netReceived = _grossRedeemed - _fee;

        // Make sure the correct amount was returned (2 wei precision)
        assertApproxEqAbs(_ethReclaimAmt, _netReceived, 2, "incorrect amount returned");

        // Make sure the beneficiary received correct amount of ETH.
        assertEq(payable(_beneficiary).balance, _ethReclaimAmt);

        // Make sure the beneficiary has correct amount of tokens.
        assertEq(
            _tokenStore.balanceOf(_beneficiary, _projectId),
            _beneficiaryTokenBalance - _tokenAmountToRedeem,
            "incorrect beneficiary balance"
        );

        // Make sure the ETH balance in terminal should be up to date (with 1 wei precision).
        assertApproxEqAbs(
            jbTerminalStore().balanceOf(
                IJBPaymentTerminal(address(_terminal)), _projectId, JBTokens.ETH
            ),
            _ethTerminalBalance - _ethReclaimAmt - (_ethReclaimAmt * 25 / 1000),
            1
        );
    }
}
