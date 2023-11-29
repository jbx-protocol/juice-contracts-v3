// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

contract TestPayDelegates_Local is TestBaseWorkflow {
    uint8 private constant _WEIGHT_DECIMALS = 18;
    uint8 private constant _NATIVE_TOKEN_DECIMALS = 18;
    uint256 private constant _WEIGHT = 1000 * 10 ** _WEIGHT_DECIMALS;
    uint256 private constant _DATA_SOURCE_WEIGHT = 2000 * 10 ** _WEIGHT_DECIMALS;
    address private constant _DATA_SOURCE = address(bytes20(keccak256("datasource")));
    bytes private constant _PAYER_METADATA = bytes("Some payer metadata");

    IJBController3_1 private _controller;
    IJBPaymentTerminal private _terminal;
    address private _projectOwner;
    address private _beneficiary;
    address private _payer;

    uint256 _projectId;

    function setUp() public override {
        super.setUp();

        _controller = jbController();
        _projectOwner = multisig();
        _beneficiary = beneficiary();
        _payer = address(1_234_567);
        _terminal = jbPayoutRedemptionTerminal();

        JBFundingCycleData memory _data = JBFundingCycleData({
            duration: 0,
            weight: _WEIGHT,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        JBFundingCycleMetadata memory _metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: 0,
            redemptionRate: 0,
            baseCurrency: uint32(uint160(JBTokens.ETH)),
            pausePay: false,
            allowMinting: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: true,
            useDataSourceForRedeem: true,
            dataSource: _DATA_SOURCE,
            metadata: 0
        });

        // Package up cycle config.
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = new JBGroupedSplits[](0);
        _cycleConfig[0].fundAccessConstraints = new JBFundAccessConstraints[](0);

        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](1);
        _accountingContexts[0] =
            JBAccountingContextConfig({token: JBTokens.ETH, standard: JBTokenStandards.NATIVE});
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: _terminal, accountingContextConfigs: _accountingContexts});

        _projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 1}),
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });
    }

    function testPayDelegates(uint256 _numberOfAllocations, uint256 _ethPayAmount) public {
        // Bound the number of allocations to a reasonable amount.
        _numberOfAllocations = bound(_numberOfAllocations, 1, 20);
        // Make sure the amount of tokens generated fits in a register, and that each allocation can get some.
        _ethPayAmount =
            bound(_ethPayAmount, _numberOfAllocations, type(uint256).max / _DATA_SOURCE_WEIGHT);

        // epa * weight / epad < max*epad/weight

        // Keep a reference to the allocations.
        JBPayDelegateAllocation3_1_1[] memory _allocations =
            new JBPayDelegateAllocation3_1_1[](_numberOfAllocations);

        // Keep a refernce to the amounts that'll be allocated.
        uint256[] memory _payDelegateAmounts = new uint256[](_numberOfAllocations);

        // Keep a reference to the amount that'll be paid and allocated.
        uint256 _totalToAllocate = _ethPayAmount;

        // Spread the paid amount through all allocations, in various chunks, omitted the last entry.
        for (uint256 i; i < _numberOfAllocations - 1; i++) {
            _payDelegateAmounts[i] = _totalToAllocate / (_payDelegateAmounts.length * 2);
            _totalToAllocate -= _payDelegateAmounts[i];
        }

        // Send the rest to the last entry.
        _payDelegateAmounts[_payDelegateAmounts.length - 1] = _totalToAllocate;

        // Keep a reference to the current funding cycle.
        (JBFundingCycle memory _fundingCycle,) = _controller.currentFundingCycleOf(_projectId);

        // Iterate through each allocation.
        for (uint256 i = 0; i < _numberOfAllocations; i++) {
            // Make up an address for the delegate.
            address _delegateAddress =
                address(bytes20(keccak256(abi.encodePacked("PayDelegate", i))));

            // Send along some metadata to the pay delegate.
            bytes memory _dataSourceMetadata = bytes("Some data source metadata");

            // Package up the delegate allocation struct.
            _allocations[i] = JBPayDelegateAllocation3_1_1(
                IJBPayDelegate3_1_1(_delegateAddress), _payDelegateAmounts[i], _dataSourceMetadata
            );

            // Keep a reference to the data that'll be received by the delegate.
            JBDidPayData3_1_1 memory _didPayData = JBDidPayData3_1_1({
                payer: _payer,
                projectId: _projectId,
                currentFundingCycleConfiguration: _fundingCycle.configuration,
                amount: JBTokenAmount(
                    JBTokens.ETH,
                    _ethPayAmount,
                    _terminal.accountingContextForTokenOf(_projectId, JBTokens.ETH).decimals,
                    _terminal.accountingContextForTokenOf(_projectId, JBTokens.ETH).currency
                    ),
                forwardedAmount: JBTokenAmount(
                    JBTokens.ETH,
                    _payDelegateAmounts[i],
                    _terminal.accountingContextForTokenOf(_projectId, JBTokens.ETH).decimals,
                    _terminal.accountingContextForTokenOf(_projectId, JBTokens.ETH).currency
                    ),
                weight: _WEIGHT,
                projectTokenCount: PRBMath.mulDiv(
                    _ethPayAmount, _DATA_SOURCE_WEIGHT, 10 ** _NATIVE_TOKEN_DECIMALS
                    ),
                beneficiary: _beneficiary,
                dataSourceMetadata: _dataSourceMetadata,
                payerMetadata: _PAYER_METADATA
            });

            // Mock the delegate
            vm.mockCall(
                _delegateAddress,
                abi.encodeWithSelector(IJBPayDelegate3_1_1.didPay.selector),
                abi.encode(_didPayData)
            );

            // Assert that the delegate gets called with the expected value
            vm.expectCall(
                _delegateAddress,
                _payDelegateAmounts[i],
                abi.encodeWithSelector(IJBPayDelegate3_1_1.didPay.selector, _didPayData)
            );

            // Expect an event to be emitted for every delegate
            vm.expectEmit(true, true, true, true);
            emit DelegateDidPay(
                IJBPayDelegate3_1_1(_delegateAddress), _didPayData, _payDelegateAmounts[i], _payer
            );
        }

        vm.mockCall(
            _DATA_SOURCE,
            abi.encodeWithSelector(IJBFundingCycleDataSource3_1_1.payParams.selector),
            abi.encode(_DATA_SOURCE_WEIGHT, _allocations)
        );

        vm.deal(_payer, _ethPayAmount);
        vm.prank(_payer);

        // Pay the project such that the _beneficiary receives project tokens.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId,
            amount: _ethPayAmount,
            token: JBTokens.ETH,
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "Forge Test",
            metadata: _PAYER_METADATA
        });
    }

    event DelegateDidPay(
        IJBPayDelegate3_1_1 indexed delegate,
        JBDidPayData3_1_1 data,
        uint256 delegatedAmount,
        address caller
    );
}
