// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PermitSignature} from "@permit2/src/test/utils/PermitSignature.sol";
import {MockPriceFeed} from "./mock/MockPriceFeed.sol";

contract TestPermit2Terminal_Local is TestBaseWorkflow, PermitSignature {
    uint256 private constant _WEIGHT = 1000 * 10 ** 18;

    IJBController3_1 private _controller;
    IJBPaymentTerminal private _terminal;
    IJBPrices private _prices;
    IJBTokenStore private _tokenStore;
    IERC20 private _usdc;
    MetadataResolverHelper private _helper;
    address private _projectOwner;

    uint256 _projectId;

    // Permit2 params
    bytes32 DOMAIN_SEPARATOR;
    address from;
    uint256 fromPrivateKey;

    // Price
    uint256 _ethPricePerUsd = 0.0005 * 10 ** 18; // 1/2000

    function setUp() public override {
        super.setUp();

        _controller = jbController();
        _projectOwner = multisig();
        _terminal = jbPayoutRedemptionTerminal();
        _prices = jbPrices();
        _tokenStore = jbTokenStore();
        _helper = metadataHelper();
        _usdc = usdcToken();

        fromPrivateKey = 0x12341234;
        from = vm.addr(fromPrivateKey);
        DOMAIN_SEPARATOR = permit2().DOMAIN_SEPARATOR();

        JBFundingCycleData memory _data = JBFundingCycleData({
            duration: 0,
            weight: _WEIGHT,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        JBFundingCycleMetadata memory _metadata = JBFundingCycleMetadata({
            reservedRate: 0,
            redemptionRate: JBConstants.MAX_REDEMPTION_RATE,
            baseCurrency: uint32(uint160(JBTokens.ETH)),
            pausePay: false,
            pauseTokenCreditTransfers: false,
            allowMinting: true,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowControllerMigration: false,
            allowSetController: false,
            holdFees: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: false,
            useDataSourceForRedeem: false,
            dataSource: address(0),
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
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](2);
        _accountingContexts[0] =
            JBAccountingContextConfig({token: JBTokens.ETH, standard: JBTokenStandards.NATIVE});
        _accountingContexts[1] =
            JBAccountingContextConfig({token: address(_usdc), standard: JBTokenStandards.ERC20});
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: _terminal, accountingContextConfigs: _accountingContexts});

        // First project for fee collection
        _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: "myIPFSHash",
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        _projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: "myIPFSHash",
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        vm.startPrank(_projectOwner);
        MockPriceFeed _priceFeedEthUsd = new MockPriceFeed(_ethPricePerUsd, 18);
        vm.label(address(_priceFeedEthUsd), "MockPrice Feed ETH-USD");

        _prices.addFeedFor({
            projectId: _projectId,
            currency: uint32(uint160(JBTokens.ETH)),
            base: uint32(uint160(address(usdcToken()))),
            priceFeed: _priceFeedEthUsd
        });

        vm.stopPrank();
    }

    function testFuzzPayPermit2(uint256 _coins, uint256 _expiration, uint256 _deadline) public {
        // Setup: set fuzz boundaries
        _coins = bound(_coins, 0, type(uint160).max);
        _expiration = bound(_expiration, block.timestamp + 1, type(uint48).max - 1);
        _deadline = bound(_deadline, block.timestamp + 1, type(uint256).max - 1);

        // Setup: prepare permit details for signing
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer.PermitDetails({
            token: address(_usdc),
            amount: uint160(_coins),
            expiration: uint48(_expiration),
            nonce: 0
        });

        IAllowanceTransfer.PermitSingle memory permit = IAllowanceTransfer.PermitSingle({
            details: details,
            spender: address(_terminal),
            sigDeadline: _deadline
        });

        // Setup: Sign permit details
        bytes memory sig = getPermitSignature(permit, fromPrivateKey, DOMAIN_SEPARATOR);

        JBSingleAllowanceData memory permitData = JBSingleAllowanceData({
            sigDeadline: _deadline,
            amount: uint160(_coins),
            expiration: uint48(_expiration),
            nonce: uint48(0),
            signature: sig
        });

        // Setup: prepare data for metadata helper
        bytes4[] memory _ids = new bytes4[](1);
        bytes[] memory _datas = new bytes[](1);
        _datas[0] = abi.encode(permitData);
        _ids[0] = bytes4(uint32(uint160(address(_terminal))));

        // Setup: Use jb metadata library to encode
        bytes memory _packedData = _helper.createMetadata(_ids, _datas);

        // Setup: Give coins and approve permit2 contract
        deal(address(_usdc), from, _coins);
        vm.prank(from);
        IERC20(address(_usdc)).approve(address(permit2()), _coins);

        vm.prank(from);
        uint256 _minted = _terminal.pay({
            projectId: _projectId,
            amount: _coins,
            token: address(_usdc),
            beneficiary: from,
            minReturnedTokens: 0,
            memo: "Take my permitted money!",
            metadata: _packedData
        });

        emit log_uint(_minted);

        // Check: that tokens were transfered
        assertEq(_usdc.balanceOf(address(_terminal)), _coins);

        // Check: that payer receives project token/balance
        assertEq(_tokenStore.balanceOf(from, _projectId), _minted);
    }

    function testFuzzAddToBalancePermit2(uint256 _coins, uint256 _expiration, uint256 _deadline)
        public
    {
        // Setup: set fuzz boundaries
        _coins = bound(_coins, 0, type(uint160).max);
        _expiration = bound(_expiration, block.timestamp + 1, type(uint48).max - 1);
        _deadline = bound(_deadline, block.timestamp + 1, type(uint256).max - 1);

        // Setup: prepare permit details for signing
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer.PermitDetails({
            token: address(_usdc),
            amount: uint160(_coins),
            expiration: uint48(_expiration),
            nonce: 0
        });

        IAllowanceTransfer.PermitSingle memory permit = IAllowanceTransfer.PermitSingle({
            details: details,
            spender: address(_terminal),
            sigDeadline: _deadline
        });

        // Setup: Sign permit details
        bytes memory sig = getPermitSignature(permit, fromPrivateKey, DOMAIN_SEPARATOR);

        JBSingleAllowanceData memory permitData = JBSingleAllowanceData({
            sigDeadline: _deadline,
            amount: uint160(_coins),
            expiration: uint48(_expiration),
            nonce: uint48(0),
            signature: sig
        });

        // Setup: prepare data for metadata helper
        bytes4[] memory _ids = new bytes4[](1);
        bytes[] memory _datas = new bytes[](1);
        _datas[0] = abi.encode(permitData);
        _ids[0] = bytes4(uint32(uint160(address(_terminal))));

        // Setup: Use jb metadata library to encode
        bytes memory _packedData = _helper.createMetadata(_ids, _datas);

        // Setup: Give coins and approve permit2 contract
        deal(address(_usdc), from, _coins);
        vm.prank(from);
        IERC20(address(_usdc)).approve(address(permit2()), _coins);

        // Test: Add to balance using permit2 data, which should transfer tokens
        vm.prank(from);
        _terminal.addToBalanceOf(
            _projectId, address(_usdc), _coins, false, "testing permit2", _packedData
        );

        // Check: that tokens were transfered
        assertEq(_usdc.balanceOf(address(_terminal)), _coins);
    }
}
