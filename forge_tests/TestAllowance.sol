// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

contract TestAllowance_Local is TestBaseWorkflow {
    IJBController3_1 private _controller;
    JBProjectMetadata private _projectMetadata;
    JBFundingCycleData private _data;
    JBFundingCycleMetadata private _metadata;
    IJBPaymentTerminal[] private _terminals;
    IJBTokenStore private _tokenStore;
    address private _projectOwner;
    address private _beneficiary;

    function setUp() public override {
        super.setUp();

        _projectOwner = multisig();
        _beneficiary = beneficiary();
        _tokenStore = jbTokenStore();
        _controller = jbController();
        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});
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
            reservedRate: 5000, //50%
            redemptionRate: 5000, //50%
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

        _terminals.push(jbETHPaymentTerminal());
    }
    
    // Tests that basic distribution limit and overflow allowance constraints work as intended.
    function testETHAllowance() public {
        // Get a reference to the ETH currency.
        uint256 ETH_CURRENCY = jbLibraries().ETH();

        // Get a reference to an ETH terminal.
        IJBPayoutRedemptionPaymentTerminal3_1 terminal = jbETHPaymentTerminal();

        // Specify a distribution limit.
        JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](1);
        uint256 _ethDistributionLimit = 10 ether;
        _distributionLimits[0] = JBCurrencyAmount({
            value: _ethDistributionLimit,
            currency: ETH_CURRENCY
        });  

        // Specify an overflow allowance.
        JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);
        uint256 _ethOverflowAllowance = 5 ether;
        _overflowAllowances[0] = JBCurrencyAmount({
            value: _ethOverflowAllowance,
            currency: ETH_CURRENCY
        });

        // Package up the constraints for the given terminal.
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        _fundAccessConstraints[0] =
            JBFundAccessConstraints({
                terminal: terminal,
                token: IJBSingleTokenPaymentTerminal(address(terminal)).token(),
                distributionLimits: _distributionLimits,
                overflowAllowances: _overflowAllowances
            });

        // Package up the configuration info.
        JBFundingCycleConfiguration[] memory _cycleConfig = new JBFundingCycleConfiguration[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = new JBGroupedSplits[](0);
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Dummy first project for fee collection
        _controller.launchProjectFor({
            owner: address(420), // random
            projectMetadata: JBProjectMetadata({content: "whatever", domain: 0}),
            configurations: new JBFundingCycleConfiguration[](0),
            terminals: _terminals, // set terminals where fees will be received
            memo: ""
        });

        // Create the project to test.
        uint256 projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: _projectMetadata,
            configurations: _cycleConfig,
            terminals: _terminals,
            memo: ""
        });

        // Get a reference to the amount being paid, such that the distribution limit is met with two times the overflow than is allowed to be withdrawn.
        uint256 _ethPayAmount = _ethDistributionLimit + (2 * _ethOverflowAllowance);
        
        // Pay the project such that the _beneficiary receives project tokens.
        terminal.pay{value: _ethPayAmount}({
            projectId: projectId, 
            amount: _ethPayAmount, 
            token: address(0), // unused 
            beneficiary: _beneficiary, 
            minReturnedTokens: 0, 
            preferClaimedTokens: false, 
            memo: "Forge test", 
            metadata: new bytes(0)
        }); 

        // Make sure the beneficiary got the expected number of tokens.
        uint256 _beneficiaryTokenBalance = PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** 18) * _metadata.reservedRate / jbLibraries().MAX_RESERVED_RATE();
        assertEq(_tokenStore.balanceOf(_beneficiary, projectId), _beneficiaryTokenBalance);

        // Make sure the terminal holds the full ETH balance.
        assertEq(jbPaymentTerminalStore().balanceOf(IJBSingleTokenPaymentTerminal(address(terminal)), projectId), _ethPayAmount);

        // Use the full discretionary allowance of overflow.
        vm.prank(_projectOwner);
        terminal.useAllowanceOf({
            projectId: projectId,
            amount: _ethOverflowAllowance,
            currency: ETH_CURRENCY,
            token: address(0), // unused
            minReturnedTokens: 0, 
            beneficiary: payable(_beneficiary),
            memo: "MEMO",
            metadata: bytes('')
        });
        
        // Make sure the beneficiary received the funds and that they are no longer in the terminal.
        uint256 _beneficiaryBalance = PRBMath.mulDiv(_ethOverflowAllowance, jbLibraries().MAX_FEE(), jbLibraries().MAX_FEE() + terminal.fee());
        assertEq((_beneficiary).balance, _beneficiaryBalance);
        assertEq(jbPaymentTerminalStore().balanceOf(IJBSingleTokenPaymentTerminal(address(terminal)), projectId), _ethPayAmount - _beneficiaryBalance);

        // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
        terminal.distributePayoutsOf({
            projectId: projectId,
            amount: _ethDistributionLimit,
            currency: ETH_CURRENCY,
            token: address(0), // unused.
            minReturnedTokens: 0,
            metadata: bytes('')
        });

        // Make sure the project owner received the full amount.
        assertEq(
            _projectOwner.balance, (_ethDistributionLimit * jbLibraries().MAX_FEE()) / (terminal.fee() + jbLibraries().MAX_FEE())
        );

        // Redeem ETH from the overflow using all of the _beneficiary's tokens.
        vm.prank(_beneficiary);
        terminal.redeemTokensOf({
            holder: _beneficiary,
            projectId: projectId,
            tokenCount: _beneficiaryTokenBalance,
            token: address(0), // unused
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary),
            memo: "gimme my money back",
            metadata: new bytes(0)
        });

        // Make sure the beneficiary doesn't have tokens left.
        assertEq(_tokenStore.balanceOf(_beneficiary, projectId), 0);
    }

    function testFuzzETHAllowance(uint232 _ethOverflowAllowance, uint232 _ethDistributionLimit, uint256 _ethPayAmount) public {
        // Make sure the amount of eth to pay is bounded. 
        _ethPayAmount = bound(_ethPayAmount, 0, 1000000 ether);

        // Make sure the values don't overflow the registry.
        unchecked {
            vm.assume(_ethOverflowAllowance + _ethDistributionLimit >= _ethOverflowAllowance && _ethOverflowAllowance + _ethDistributionLimit >= _ethDistributionLimit);
        }

        // Get a reference to the ETH currency.
        uint256 ETH_CURRENCY = jbLibraries().ETH();

        // Get a reference to an ETH terminal.
        IJBPayoutRedemptionPaymentTerminal3_1 terminal = jbETHPaymentTerminal();

        // Specify a distribution limit.
        JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](1);
         _distributionLimits[0] = JBCurrencyAmount({
            value: _ethDistributionLimit,
            currency: ETH_CURRENCY
        });  

        // Specify an overflow allowance.
        JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);
        _overflowAllowances[0] = JBCurrencyAmount({
            value: _ethOverflowAllowance,
            currency: ETH_CURRENCY
        });

        // Package up the constraints for the given terminal.
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        _fundAccessConstraints[0] =
            JBFundAccessConstraints({
                terminal: terminal,
                token: IJBSingleTokenPaymentTerminal(address(terminal)).token(),
                distributionLimits: _distributionLimits,
                overflowAllowances: _overflowAllowances
            });

        // Package up the configuration info.
        JBFundingCycleConfiguration[] memory _cycleConfig = new JBFundingCycleConfiguration[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = new JBGroupedSplits[](0);
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Create the project to test.
        uint256 projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: _projectMetadata,
            configurations: _cycleConfig,
            terminals: _terminals,
            memo: ""
        });

        // Make a payment to the project to give it a starting balance. Send the tokens to the _beneficiary.
        terminal.pay{value: _ethPayAmount}({
            projectId: projectId, 
            amount: _ethPayAmount, 
            token: address(0), //unused 
            beneficiary: _beneficiary, 
            minReturnedTokens: 0, 
            preferClaimedTokens: false, 
            memo: "Forge test", 
            metadata: new bytes(0)
        });

        // Make sure the beneficiary got the expected number of tokens.
        uint256 _beneficiaryTokenBalance = PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** 18) * _metadata.reservedRate / jbLibraries().MAX_RESERVED_RATE();
        if (_ethPayAmount != 0) assertEq(_tokenStore.balanceOf(_beneficiary, projectId), _beneficiaryTokenBalance);

        // Make sure the terminal holds the full ETH balance.
        assertEq(jbPaymentTerminalStore().balanceOf(IJBSingleTokenPaymentTerminal(address(terminal)), projectId), _ethPayAmount);

        // Keep a reference to a flag indiciating an expected revert.
        bool willRevert;

        // Revert if there's no allowance.
        if (_ethOverflowAllowance == 0) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
            willRevert = true;
        // Revert if there's no overflow, or if too much is being withdrawn.
        } else if (_ethDistributionLimit >= _ethPayAmount || _ethOverflowAllowance > (_ethPayAmount - _ethDistributionLimit)) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));
            willRevert = true;
        }

        // Use the full discretionary allowance of overflow.
        vm.prank(_projectOwner);
        terminal.useAllowanceOf({
            projectId: projectId,
            amount: _ethOverflowAllowance,
            currency: ETH_CURRENCY,
            token: address(0), // unused
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary), // Beneficiary
            memo: "MEMO",
            metadata: bytes('')
        });

        // Check the collected balance if one is expected.
        if (!willRevert && _ethPayAmount != 0 ) {
            // Make sure the beneficiary received the funds and that they are no longer in the terminal.
            uint256 _beneficiaryBalance = PRBMath.mulDiv(_ethOverflowAllowance, jbLibraries().MAX_FEE(), jbLibraries().MAX_FEE() + terminal.fee());
            assertEq((_beneficiary).balance, _beneficiaryBalance);
            assertEq(jbPaymentTerminalStore().balanceOf(IJBSingleTokenPaymentTerminal(address(terminal)), projectId), _ethPayAmount - _beneficiaryBalance);
        }

        // Revert if the distribution limit is greater than the balance.
        if (_ethDistributionLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));
        }
        // Revert if there's no distribution limit.
        else if (_ethDistributionLimit == 0) {
            vm.expectRevert(abi.encodeWithSignature("DISTRIBUTION_AMOUNT_LIMIT_REACHED()"));
        }

        // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
        terminal.distributePayoutsOf({
            projectId: projectId,
            amount: _ethDistributionLimit,
            currency: ETH_CURRENCY,
            token: address(0), // unused.
            minReturnedTokens: 0,
            metadata: bytes('')
        });

        // Check the collected distribution if one is expected.
        if (_ethDistributionLimit <= _ethPayAmount && _ethDistributionLimit > 1) {
            // Avoid rounding error
            assertEq(
                _projectOwner.balance, (_ethDistributionLimit * jbLibraries().MAX_FEE()) / (terminal.fee() + jbLibraries().MAX_FEE())
            );
        }
    }
}
