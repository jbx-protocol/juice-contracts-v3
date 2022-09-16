import { expect } from 'chai';
import { ethers } from 'hardhat';

import { deployMockContract } from '@ethereum-waffle/mock-contract';

import { packFundingCycleMetadata } from '../../helpers/utils';

import jbController from '../../../artifacts/contracts/JBController.sol/JBController.json';
import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbETHPaymentTerminal from '../../../artifacts/contracts/JBETHPaymentTerminal.sol/JBETHPaymentTerminal.json';
import jbFundingCycleStore from '../../../artifacts/contracts/JBFundingCycleStore.sol/JBFundingCycleStore.json';
import jbOperatorStore from '../../../artifacts/contracts/JBOperatorStore.sol/JBOperatorStore.json';
import jbProjects from '../../../artifacts/contracts/JBProjects.sol/JBProjects.json';
import jbSplitsStore from '../../../artifacts/contracts/JBSplitsStore.sol/JBSplitsStore.json';
import jbToken from '../../../artifacts/contracts/JBToken.sol/JBToken.json';
import jbTokenStore from '../../../artifacts/contracts/JBTokenStore.sol/JBTokenStore.json';
import jbPrices from '../../../artifacts/contracts/JBPrices.sol/JBPrices.json';
import jbPaymentTerminalStore from '../../../artifacts/contracts/JBSingleTokenPaymentTerminalStore.sol/JBSingleTokenPaymentTerminalStore.json';

describe('DaiTreasuryDelegate::didPay(...)', () => {
    const TREASURY_PROJECT_ID = 1;
    const TREASURY_TOKEN_NAME = 'DaiTreasuryToken';
    const TREASURY_TOKEN_SYMBOL = 'DTT';

    const CLIENT_PROJECT_ID = 1;
    const CLIENT_TOKEN_NAME = 'DaiTreasuryToken';
    const CLIENT_TOKEN_SYMBOL = 'DTT';

    const MEMO = 'Test Memo';
    const CURRENCY_ETH = 1;
    const ETH_TO_PAY = ethers.utils.parseEther('1');
    const MIN_TOKEN_REQUESTED = 90;
    const METADATA = '0x69';
    const FUNDING_CYCLE_NUMBER = 0;
    const TOKEN_RECEIVED = 100;
    const ADJUSTED_MEMO = 'test test memo';
    let ethToken;

    async function setup() {
        let [deployer, ...accounts] = await ethers.getSigners();

        const blockNum = await ethers.provider.getBlockNumber();
        const block = await ethers.provider.getBlock(blockNum);
        const timestamp = block.timestamp;

        let [
            mockJbDirectory,
            mockJbFundingCycleStore,
            mockJbOperatorStore,
            mockJbProjects,
            mockJbSplitsStore,
            mockTreasuryToken,
            mockClientToken,
            mockJbTokenStore,
            mockJbPrices,
            mockJBPaymentTerminalStore,
            mockTreasuryPaymentTerminal,
            mockController
        ] = await Promise.all([
            deployMockContract(deployer, jbDirectory.abi),
            deployMockContract(deployer, jbFundingCycleStore.abi),
            deployMockContract(deployer, jbOperatorStore.abi),
            deployMockContract(deployer, jbProjects.abi),
            deployMockContract(deployer, jbSplitsStore.abi),
            deployMockContract(deployer, jbToken.abi),
            deployMockContract(deployer, jbToken.abi),
            deployMockContract(deployer, jbTokenStore.abi),
            deployMockContract(deployer, jbPrices.abi),
            deployMockContract(deployer, jbPaymentTerminalStore.abi),
            deployMockContract(deployer, jbETHPaymentTerminal.abi),
            deployMockContract(deployer, jbController.abi),
        ]);

        let jbEthTerminalFactory = await ethers.getContractFactory('JBETHPaymentTerminal', deployer);
        const daiTreasuryDelegateFactory = await ethers.getContractFactory('DaiTreasuryDelegate', deployer);

        // set up treasury project
        await mockJbTokenStore.mock.issueFor
            .withArgs(TREASURY_PROJECT_ID, TREASURY_TOKEN_NAME, TREASURY_TOKEN_SYMBOL)
            .returns(mockTreasuryToken.address);

        await mockJbDirectory.mock.controllerOf.withArgs(TREASURY_PROJECT_ID).returns(mockController.address);
        await mockJbProjects.mock.ownerOf.withArgs(TREASURY_PROJECT_ID).returns(deployer.address);
        await mockJbDirectory.mock.isTerminalOf.withArgs(TREASURY_PROJECT_ID, deployer.address).returns(true);

        const daiTreasuryDelegate = await daiTreasuryDelegateFactory.connect(deployer).deploy(mockController.address);

        const mockFundingCycle = {
            number: 1,
            configuration: timestamp,
            basedOn: timestamp,
            start: timestamp,
            duration: 0,
            weight: 0,
            discountRate: 0,
            ballot: ethers.constants.AddressZero,
            metadata: packFundingCycleMetadata()
        };

        await mockJbFundingCycleStore.mock.currentOf.withArgs(TREASURY_PROJECT_ID).returns(mockFundingCycle);
        await mockJBPaymentTerminalStore.mock.recordPaymentFrom.returns(mockFundingCycle, MIN_TOKEN_REQUESTED, [], MEMO);
        await mockJbOperatorStore.mock.hasPermission.returns(true); // TODO: should be more specific
        await mockJBPaymentTerminalStore.mock.recordUsedAllowanceOf.returns(mockFundingCycle, '1000000000000000000'); // TODO: should be more specific

        await mockTreasuryPaymentTerminal.mock.useAllowanceOf.returns('1000000000000000000');

        // set up client project
        let clientPaymentTerminal = await jbEthTerminalFactory
            .connect(deployer)
            .deploy(
                CURRENCY_ETH,
                mockJbOperatorStore.address,
                mockJbProjects.address,
                mockJbDirectory.address,
                mockJbSplitsStore.address,
                mockJbPrices.address,
                mockJBPaymentTerminalStore.address,
                deployer.address
            );

        await mockJbDirectory.mock.isTerminalOf
            .withArgs(CLIENT_PROJECT_ID, clientPaymentTerminal.address)
            .returns(true);

        await mockJbDirectory.mock.primaryTerminalOf
            .withArgs(CLIENT_PROJECT_ID, mockClientToken.address)
            .returns(clientPaymentTerminal.address);

        await mockJbTokenStore.mock.issueFor
            .withArgs(CLIENT_PROJECT_ID, CLIENT_TOKEN_NAME, CLIENT_TOKEN_SYMBOL)
            .returns(mockClientToken.address);

        const clientFundingCycle = {
            number: 0,
            configuration: 0,
            basedOn: 0,
            start: 0,
            duration: '1000000000',
            weight: '10000',
            discountRate: 0,
            ballot: ethers.constants.AddressZero,
            metadata: 0
        };
        await mockJBPaymentTerminalStore.mock.recordPaymentFrom.returns(clientFundingCycle, 0, [], MEMO);

        return {
            deployer,
            accounts,
            jbController,
            mockJbOperatorStore,
            mockJbDirectory,
            mockJbFundingCycleStore,
            mockJbTokenStore,
            mockTreasuryToken,
            timestamp,
            mockTreasuryPaymentTerminal,
            clientPaymentTerminal,
            ethToken,
            daiTreasuryDelegate
        };
    }

    it(`Should mint token if meeting contribution parameters`, async function () {
        const { accounts, daiTreasuryDelegate, clientPaymentTerminal, timestamp } = await setup();

        expect(
            await clientPaymentTerminal
                .connect(accounts[0])
                .pay(
                    CLIENT_PROJECT_ID,
                    0,
                    ethers.constants.AddressZero,
                    accounts[0].address,
                    0,
                    false,
                    MEMO,
                    METADATA,
                    { value: '1000000000000000000' }
                )
        )
            .to.emit(daiTreasuryDelegate, 'Pay')
            .withArgs(
                timestamp,
                FUNDING_CYCLE_NUMBER,
                TREASURY_PROJECT_ID,
                accounts[0].address,
                accounts[0].address,
                ETH_TO_PAY,
                TOKEN_RECEIVED,
                ADJUSTED_MEMO,
                METADATA,
                accounts[0].address
            );
    });

    it(`Test supportsInterface()`, async function () {
        const { daiTreasuryDelegate } = await setup();

        let match = await daiTreasuryDelegate.supportsInterface(1903168617); // IJBFundingCycleDataSource
        expect(match).to.equal(true);

        match = await daiTreasuryDelegate.supportsInterface(3667847351); // IJBPayDelegate
        expect(match).to.equal(true);

        match = await daiTreasuryDelegate.supportsInterface(722716047); // IJBRedemptionDelegate
        expect(match).to.equal(true);
    });
});
