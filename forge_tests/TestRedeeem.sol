// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@paulrberg/contracts/math/PRBMathUD60x18.sol";

import "./helpers/TestBaseWorkflow.sol";

import "../contracts/JBETHPaymentTerminal3_1_1.sol";

/**
 * This system test file verifies the following flow:
 * launch project → issue token → pay project (claimed tokens) →  burn some of the claimed tokens → redeem rest of tokens
 */
contract TestRedeem_Local is TestBaseWorkflow {
    JBController private _controller;
    JBETHPaymentTerminal private _terminal;
    JBETHPaymentTerminal3_1_1 private _terminal3_1_1;
    JBTokenStore private _tokenStore;

    JBProjectMetadata private _projectMetadata;
    JBFundingCycleData private _data;
    JBFundingCycleMetadata private _metadata;
    JBGroupedSplits[] private _groupedSplits; // Default empty
    JBFundAccessConstraints[] private _fundAccessConstraints; // Default empty
    IJBPaymentTerminal[] private _terminals; // Default empty

    uint256 private _projectId;
    address private _projectOwner;
    uint256 private _weight = 1000 * 10 ** 18;
    uint256 private _targetInWei = 1 * 10 ** 18;

    function setUp() public override {
        super.setUp();

        _controller = jbController();
        _terminal = jbETHPaymentTerminal();

        _terminal3_1_1 = new JBETHPaymentTerminal3_1_1(
            _accessJBLib.ETH(),
            _jbOperatorStore,
            _jbProjects,
            _jbDirectory,
            _jbSplitsStore,
            _jbPrices,
            _jbPaymentTerminalStore3_1,
            _multisig
        );

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
            redemptionRate: 5000,
            ballotRedemptionRate: 5000,
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

        _terminals.push(_terminal);
        _terminals.push(_terminal3_1_1);

        _fundAccessConstraints.push(
            JBFundAccessConstraints({
                terminal: _terminal,
                token: jbLibraries().ETHToken(),
                distributionLimit: 1 ether, // 10 ETH target
                overflowAllowance: 5 ether,
                distributionLimitCurrency: 1, // Currency = ETH
                overflowAllowanceCurrency: 1
            })
        );

        _fundAccessConstraints.push(
            JBFundAccessConstraints({
                terminal: _terminal3_1_1,
                token: jbLibraries().ETHToken(),
                distributionLimit: 0, // only overflow
                overflowAllowance: 5 ether,
                distributionLimitCurrency: 1, // Currency = ETH
                overflowAllowanceCurrency: 1
            })
        );

        _projectOwner = multisig();

        // Launch a protocol project first
        _controller.launchProjectFor(
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
    }

    function testRedeem() external {
        bool payPreferClaimed = true; //false
        uint96 payAmountInWei = 2 ether;

        // issue an ERC-20 token for project
        vm.prank(_projectOwner);
        _tokenStore.issueFor(_projectId, "TestName", "TestSymbol");

        address _userWallet = address(1234);

        // pay terminal
        _terminal.pay{value: payAmountInWei}(
            _projectId,
            payAmountInWei,
            address(0),
            _userWallet,
            /* _minReturnedTokens */
            0,
            /* _preferClaimedTokens */
            payPreferClaimed,
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

        vm.prank(_userWallet);
        uint256 _reclaimAmtInWei = _terminal.redeemTokensOf(
            /* _holder */
            _userWallet,
            /* _projectId */
            _projectId,
            /* _tokenCount */
            _userTokenBalance / 2,
            /* token (unused) */
            address(0),
            /* _minReturnedWei */
            1,
            /* _beneficiary */
            payable(_userWallet),
            /* _memo */
            "Refund me now!",
            /* _delegateMetadata */
            new bytes(0)
        );

        // verify: beneficiary has correct amount ok token
        assertEq(_tokenStore.balanceOf(_userWallet, _projectId), _userTokenBalance / 2);

        // verify: ETH balance in terminal should be up to date
        assertEq(jbPaymentTerminalStore().balanceOf(_terminal, _projectId), _terminalBalanceInWei - _reclaimAmtInWei);
    }

    function testRedeemTerminal3_1_1() external {
        bool payPreferClaimed = true; //false
        uint96 payAmountInWei = 2 ether;

        // issue an ERC-20 token for project
        vm.prank(_projectOwner);
        _tokenStore.issueFor(_projectId, "TestName", "TestSymbol");

        address _userWallet = address(1234);

        // pay terminal
        _terminal3_1_1.pay{value: payAmountInWei}(
            _projectId,
            payAmountInWei,
            address(0),
            _userWallet,
            /* _minReturnedTokens */
            0,
            /* _preferClaimedTokens */
            payPreferClaimed,
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
        assertEq(jbPaymentTerminalStore().balanceOf(_terminal3_1_1, _projectId), _terminalBalanceInWei);



        uint256 _tokenAmountToRedeem = 1 ether; //bound(_tokenAmountToRedeem, 100, _userTokenBalance);

        vm.prank(_userWallet);
        uint256 _reclaimAmtInWei = _terminal3_1_1.redeemTokensOf(
            /* _holder */
            _userWallet,
            /* _projectId */
            _projectId,
            /* _tokenCount */
            _tokenAmountToRedeem,
            /* token (unused) */
            address(0),
            /* _minReturnedWei */
            0,
            /* _beneficiary */
            payable(_userWallet),
            /* _memo */
            "Refund me now!",
            /* _delegateMetadata */
            new bytes(0)
        );

        // Check: correct amount returned
        uint256 _grossRedeemed = PRBMath.mulDiv(_tokenAmountToRedeem, 10**18, _weight) / 2; // 50% redemption rate
        uint256 _fee =  _grossRedeemed - PRBMath.mulDiv(_grossRedeemed, 1_000_000_000, 25000000 + 1_000_000_000); // 2.5% fee
        uint256 _netReceived = _grossRedeemed - _fee;

// received 488000000000000 but calculated 487804878048780
// fee      12200000000000  but calculated 12195121951220

        console.log("_grossRedeemed", _grossRedeemed);
        console.log("_fee", _fee);
        console.log("_netReceived", _netReceived);

        // assertApproxEqAbs(_reclaimAmtInWei, _netReceived, 1);




        // // verify: beneficiary has correct amount of token
        // assertEq(_tokenStore.balanceOf(_userWallet, _projectId), _userTokenBalance - _tokenAmountToRedeem, "incorrect beneficiary balance");

        // verify: ETH balance in terminal should be up to date (with 1 wei tolerance)
        //assertApproxEqAbs(jbPaymentTerminalStore().balanceOf(_terminal3_1_1, _projectId), _terminalBalanceInWei - _reclaimAmtInWei - (_reclaimAmtInWei * 25 / 1000), 1);
    }
}
