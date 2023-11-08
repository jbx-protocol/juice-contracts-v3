// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

// Payments can be forwarded to any number of pay delegates.
contract TestPayDelegates_Local is TestBaseWorkflow {
    event DelegateDidPay(IJBPayDelegate3_1_1 indexed delegate, JBDidPayData3_1_1 data, uint256 delegatedAmount, address caller);

    JBController3_1 private _controller;
    JBProjectMetadata private _projectMetadata;
    JBFundingCycleData private _data;
    JBFundingCycleMetadata private _metadata;
    JBGroupedSplits[] private _groupedSplits;
    JBFundAccessConstraints[] private _fundAccessConstraints;
    IJBPaymentTerminal[] private _terminals;
    JBTokenStore private _tokenStore;
    address private _projectOwner;
    address private _beneficiary;
    address private _dataSource = address(bytes20(keccak256("datasource")));
    uint256 private _projectId;

    function setUp() public override {
        super.setUp();

        _projectOwner = multisig();
        _beneficiary = beneficiary();
        _tokenStore = jbTokenStore();
        _controller = jbController();
        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});
        _data = JBFundingCycleData({
            duration: 0,
            weight: 0,
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
            redemptionRate: 0,
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
            useDataSourceForPay: true,
            useDataSourceForRedeem: true,
            dataSource: _dataSource,
            metadata: 0
        });

        JBFundingCycleConfiguration[] memory _cycleConfig = new JBFundingCycleConfiguration[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        _terminals.push(jbETHPaymentTerminal());
        _projectId = _controller.launchProjectFor(
            _projectOwner,
            _projectMetadata,
            _cycleConfig,
            _terminals,
            ""
        );
    }

    function testPayDelegates(uint256 _numberOfAllocations, uint256 _ethPayAmount) public {
        // Bound the number of allocations to a reasonable number.
        _numberOfAllocations = bound(_numberOfAllocations, 1, 100);

        // Make sure there's enough ETH paid to allocate for each delegate.
        _ethPayAmount = bound(_ethPayAmount, _numberOfAllocations, type(uint256).max - 1);

        // Package up the allocations.
        JBPayDelegateAllocation3_1_1[] memory _allocations = new JBPayDelegateAllocation3_1_1[](_numberOfAllocations);
        uint256[] memory _payDelegateAmounts = new uint256[](_numberOfAllocations);

        {
            // Keep a reference to the decrementing amount to allocate to the delegates.
            uint256 _ethToAllocate = _ethPayAmount;

            // Allocate small amounts to each delegate except the last one.
            for (uint256 i ; i < _payDelegateAmounts.length - 1; i++) {
                uint256 _amount = _ethToAllocate / (_payDelegateAmounts.length * 2);
                _payDelegateAmounts[i] = _amount;
                _ethToAllocate -= _amount;
            }

            // Allocate the larger chunk to the last delegate.
            _payDelegateAmounts[_payDelegateAmounts.length - 1] = _ethToAllocate;
        }

        // Keep a reference to the current funding cycle.
        (JBFundingCycle memory _fundingCycle, ) =
            _controller.currentFundingCycleOf(_projectId);

        // Make some data to pass along to the delegate. 
        bytes memory _somePayerMetadata = bytes("Some payer metadata");

        // Iterate through each delegate expected to be called.
        for (uint256 i = 0; i < _payDelegateAmounts.length; i++) {
            // Create a delegate address.
            address _delegateAddress = address(bytes20(keccak256(abi.encodePacked("PayDelegate", i))));

            // Make some data to pass along to the delegate from the data source. 
            bytes memory _someData = new bytes(1);
            _someData[0] = keccak256(abi.encodePacked(i))[0];

            // Specify a call to the delegate, forwarding the specified amount.
            _allocations[i] = JBPayDelegateAllocation3_1_1(IJBPayDelegate3_1_1(_delegateAddress), _payDelegateAmounts[i], _someData);

            // Keep a reference to the data expected to be sent to the delegate being iterated on.
            JBDidPayData3_1_1 memory _didPayData = JBDidPayData3_1_1({
                payer: _beneficiary,
                projectId: _projectId,
                currentFundingCycleConfiguration: _fundingCycle.configuration,
                amount: JBTokenAmount(
                    JBTokens.ETH,
                    _ethPayAmount,
                    JBSingleTokenPaymentTerminal(address(_terminals[0])).decimals(),
                    JBSingleTokenPaymentTerminal(address(_terminals[0])).currency()
                ),
                forwardedAmount: JBTokenAmount(
                    JBTokens.ETH,
                    _payDelegateAmounts[i],
                    JBSingleTokenPaymentTerminal(address(_terminals[0])).decimals(),
                    JBSingleTokenPaymentTerminal(address(_terminals[0])).currency()
                ),
                weight: _fundingCycle.weight,
                projectTokenCount: 0,
                beneficiary: _beneficiary,
                preferClaimedTokens: false,
                memo: "",
                dataSourceMetadata: _someData, // empty metadata
                payerMetadata: _somePayerMetadata // empty metadata
            });

            // Mock the delegate's didPay.
            vm.mockCall(_delegateAddress, abi.encodeWithSelector(IJBPayDelegate3_1_1.didPay.selector), "");

            // Make sure the delegate gets called with the expected value.
            vm.expectCall(
                _delegateAddress, _payDelegateAmounts[i], abi.encodeWithSelector(IJBPayDelegate3_1_1.didPay.selector, _didPayData)
            );

            // Expect an event to be emitted for every delegate
            vm.expectEmit(true, true, true, true);
            emit DelegateDidPay({
                delegate: IJBPayDelegate3_1_1(_delegateAddress), 
                data: _didPayData, 
                delegatedAmount: _payDelegateAmounts[i], 
                caller: _beneficiary
            });
        }

        // Mock the dataSource's payParams to return the allocations.
        vm.mockCall(
            _dataSource,
            abi.encodeWithSelector(IJBFundingCycleDataSource3_1_1.payParams.selector),
            abi.encode(
                0, // weight
                "", // memo
                _allocations // allocations
            )
        );

        // Make the payment. 
        vm.deal(_beneficiary, _ethPayAmount);
        vm.prank(_beneficiary);
        _terminals[0].pay{value: _ethPayAmount}(
            _projectId, _ethPayAmount, address(0), _beneficiary, 0, false, "Forge test", _somePayerMetadata
        );
    }
}