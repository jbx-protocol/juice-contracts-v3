import { expect } from 'chai';
import { ethers } from 'hardhat';

import { deployMockContract } from '@ethereum-waffle/mock-contract';

import errors from '../helpers/errors.json';
import { packFundingCycleMetadata, impersonateAccount } from '../helpers/utils';

import jbController from '../../artifacts/contracts/interfaces/IJBController3_1.sol/IJBController3_1.json';
import jbDirectory from '../../artifacts/contracts/interfaces/IJBDirectory.sol/IJBDirectory.json';
import jBFundingCycleStore from '../../artifacts/contracts/interfaces/IJBFundingCycleStore.sol/IJBFundingCycleStore.json';
import jbFundAccessConstraintsStore from '../../artifacts/contracts/interfaces/IJBFundAccessConstraintsStore.sol/IJBFundAccessConstraintsStore.json';
import jbPrices from '../../artifacts/contracts/interfaces/IJBPrices.sol/IJBPrices.json';
import jbProjects from '../../artifacts/contracts/interfaces/IJBProjects.sol/IJBProjects.json';
import jbTerminal from '../../artifacts/contracts/abstract/JBPayoutRedemptionPaymentTerminal3_1_2.sol/JBPayoutRedemptionPaymentTerminal3_1_2.json';
import jbTokenStore from '../../artifacts/contracts/interfaces/IJBTokenStore.sol/IJBTokenStore.json';

describe('JBSingleTokenPaymentTerminalStore3_1_1::recordDistributionFor(...)', function () {
  const FUNDING_CYCLE_NUM = 1;
  const PROJECT_ID = 2;
  const AMOUNT = ethers.FixedNumber.fromString('4398541.345');
  const WEIGHT = ethers.FixedNumber.fromString('900000000.23411');
  const CURRENCY = 1;
  const _FIXED_POINT_MAX_FIDELITY = 18;

  async function setup() {
    const [deployer, addr] = await ethers.getSigners();

    const mockJbPrices = await deployMockContract(deployer, jbPrices.abi);
    const mockJbProjects = await deployMockContract(deployer, jbProjects.abi);
    const mockJbDirectory = await deployMockContract(deployer, jbDirectory.abi);
    const mockJbFundingCycleStore = await deployMockContract(deployer, jBFundingCycleStore.abi);
    const mockJbTerminal = await deployMockContract(deployer, jbTerminal.abi);
    const mockJbTokenStore = await deployMockContract(deployer, jbTokenStore.abi);
    const mockJbController = await deployMockContract(deployer, jbController.abi);
    const mockJbFundAccessConstraintsStore = await deployMockContract(deployer, jbFundAccessConstraintsStore.abi);

    const jbCurrenciesFactory = await ethers.getContractFactory('JBCurrencies');
    const jbCurrencies = await jbCurrenciesFactory.deploy();
    const CURRENCY_ETH = await jbCurrencies.ETH();
    const CURRENCY_USD = await jbCurrencies.USD();

    const JBPaymentTerminalStoreFactory = await ethers.getContractFactory(
      'contracts/JBSingleTokenPaymentTerminalStore3_1_1.sol:JBSingleTokenPaymentTerminalStore3_1_1',
    );
    const JBSingleTokenPaymentTerminalStore = await JBPaymentTerminalStoreFactory.deploy(
      mockJbDirectory.address,
      mockJbFundingCycleStore.address,
      mockJbPrices.address,
    );

    const blockNum = await ethers.provider.getBlockNumber();
    const block = await ethers.provider.getBlock(blockNum);
    const timestamp = block.timestamp;

    /* Common mocks */

    await mockJbTerminal.mock.currency.returns(CURRENCY);

    // Set controller address
    await mockJbDirectory.mock.controllerOf.withArgs(PROJECT_ID).returns(mockJbController.address);

    const mockJbTerminalSigner = await impersonateAccount(mockJbTerminal.address);

    const token = ethers.Wallet.createRandom().address;

    await mockJbTerminal.mock.token.returns(token);

    return {
      mockJbTerminal,
      mockJbTerminalSigner,
      addr,
      mockJbController,
      mockJbFundAccessConstraintsStore,
      mockJbFundingCycleStore,
      mockJbPrices,
      JBSingleTokenPaymentTerminalStore,
      timestamp,
      token,
      CURRENCY_ETH,
      CURRENCY_USD,
    };
  }

  it('Should record distribution with mockJbTerminal access, if the amount in expressed in terminal currency', async function () {
    const {
      mockJbTerminal,
      mockJbTerminalSigner,
      mockJbController,
      mockJbFundingCycleStore,
      mockJbFundAccessConstraintsStore,
      mockJbPrices,
      JBSingleTokenPaymentTerminalStore,
      timestamp,
      token,
      CURRENCY_USD,
    } = await setup();

    await mockJbFundingCycleStore.mock.currentOf.withArgs(PROJECT_ID).returns({
      // mock JBFundingCycle obj
      number: FUNDING_CYCLE_NUM,
      configuration: timestamp,
      basedOn: timestamp,
      start: timestamp,
      duration: 0,
      weight: WEIGHT,
      discountRate: 0,
      ballot: ethers.constants.AddressZero,
      metadata: packFundingCycleMetadata({ pauseDistributions: 0 }),
    });

    // Add to balance beforehand
    await JBSingleTokenPaymentTerminalStore.connect(mockJbTerminalSigner).recordAddedBalanceFor(
      PROJECT_ID,
      AMOUNT,
    );

    await mockJbFundAccessConstraintsStore.mock.distributionLimitOf
      .withArgs(PROJECT_ID, timestamp, mockJbTerminal.address, token, CURRENCY_USD)
      .returns(AMOUNT);

    await mockJbController.mock.fundAccessConstraintsStore
      .withArgs()
      .returns(mockJbFundAccessConstraintsStore.address);

    await mockJbTerminal.mock.currency.returns(CURRENCY_USD);

    // Pre-checks
    expect(
      await JBSingleTokenPaymentTerminalStore.usedDistributionLimitOf(
        mockJbTerminalSigner.address,
        PROJECT_ID,
        FUNDING_CYCLE_NUM,
        CURRENCY_USD
      ),
    ).to.equal(0);
    expect(
      await JBSingleTokenPaymentTerminalStore.balanceOf(mockJbTerminalSigner.address, PROJECT_ID),
    ).to.equal(AMOUNT);

    // Record the distributions
    await JBSingleTokenPaymentTerminalStore.connect(mockJbTerminalSigner).recordDistributionFor(
      PROJECT_ID,
      AMOUNT,
      CURRENCY_USD,
    );

    // Post-checks
    expect(
      await JBSingleTokenPaymentTerminalStore.usedDistributionLimitOf(
        mockJbTerminalSigner.address,
        PROJECT_ID,
        FUNDING_CYCLE_NUM,
        CURRENCY_USD
      ),
    ).to.equal(AMOUNT);
    expect(
      await JBSingleTokenPaymentTerminalStore.balanceOf(mockJbTerminalSigner.address, PROJECT_ID),
    ).to.equal(0);
  });

  it('Should record distribution with mockJbTerminal access, if the amount in another currency', async function () {
    const {
      mockJbTerminal,
      mockJbTerminalSigner,
      mockJbController,
      mockJbFundingCycleStore,
      mockJbPrices,
      mockJbFundAccessConstraintsStore,
      JBSingleTokenPaymentTerminalStore,
      timestamp,
      token,
      CURRENCY_ETH,
      CURRENCY_USD,
    } = await setup();

    await mockJbFundingCycleStore.mock.currentOf.withArgs(PROJECT_ID).returns({
      // mock JBFundingCycle obj
      number: FUNDING_CYCLE_NUM,
      configuration: timestamp,
      basedOn: timestamp,
      start: timestamp,
      duration: 0,
      weight: WEIGHT,
      discountRate: 0,
      ballot: ethers.constants.AddressZero,
      metadata: packFundingCycleMetadata({ pauseDistributions: 0 }),
    });

    const usdToEthPrice = ethers.FixedNumber.from(10000);
    const amountInWei = AMOUNT.divUnsafe(usdToEthPrice);

    // Add to balance beforehand
    await JBSingleTokenPaymentTerminalStore.connect(mockJbTerminalSigner).recordAddedBalanceFor(
      PROJECT_ID,
      amountInWei,
    );

    await mockJbFundAccessConstraintsStore.mock.distributionLimitOf
      .withArgs(PROJECT_ID, timestamp, mockJbTerminal.address, token, CURRENCY_USD)
      .returns(AMOUNT);

    await mockJbController.mock.fundAccessConstraintsStore
      .withArgs()
      .returns(mockJbFundAccessConstraintsStore.address);

    await mockJbPrices.mock.priceFor
      .withArgs(PROJECT_ID, CURRENCY_USD, CURRENCY_ETH, _FIXED_POINT_MAX_FIDELITY)
      .returns(usdToEthPrice);

    await mockJbTerminal.mock.currency.returns(CURRENCY_ETH);

    // Pre-checks
    expect(
      await JBSingleTokenPaymentTerminalStore.usedDistributionLimitOf(
        mockJbTerminalSigner.address,
        PROJECT_ID,
        FUNDING_CYCLE_NUM,
        CURRENCY_USD
      ),
    ).to.equal(0);
    expect(
      await JBSingleTokenPaymentTerminalStore.balanceOf(mockJbTerminalSigner.address, PROJECT_ID),
    ).to.equal(amountInWei);

    // Record the distributions
    await JBSingleTokenPaymentTerminalStore.connect(mockJbTerminalSigner).recordDistributionFor(
      PROJECT_ID,
      AMOUNT,
      CURRENCY_USD,
    );

    // Post-checks
    expect(
      await JBSingleTokenPaymentTerminalStore.usedDistributionLimitOf(
        mockJbTerminalSigner.address,
        PROJECT_ID,
        FUNDING_CYCLE_NUM,
        CURRENCY_USD
      ),
    ).to.equal(AMOUNT);
    expect(
      await JBSingleTokenPaymentTerminalStore.balanceOf(mockJbTerminalSigner.address, PROJECT_ID),
    ).to.equal(0);
  });

  /* Sad path tests */

  it(`Can't record distribution if distributions are paused`, async function () {
    const {
      mockJbTerminal,
      mockJbTerminalSigner,
      mockJbFundingCycleStore,
      JBSingleTokenPaymentTerminalStore,
      timestamp,
      CURRENCY_ETH,
    } = await setup();

    await mockJbFundingCycleStore.mock.currentOf.withArgs(PROJECT_ID).returns({
      // mock JBFundingCycle obj
      number: FUNDING_CYCLE_NUM,
      configuration: timestamp,
      basedOn: timestamp,
      start: timestamp,
      duration: 0,
      weight: WEIGHT,
      discountRate: 0,
      ballot: ethers.constants.AddressZero,
      metadata: packFundingCycleMetadata({ pauseDistributions: 1 }),
    });

    await mockJbTerminal.mock.currency.returns(CURRENCY_ETH);

    // Record the distributions
    await expect(
      JBSingleTokenPaymentTerminalStore.connect(mockJbTerminalSigner).recordDistributionFor(
        PROJECT_ID,
        AMOUNT,
        CURRENCY_ETH,
      ),
    ).to.be.revertedWith(errors.FUNDING_CYCLE_DISTRIBUTION_PAUSED);
  });

  it(`Can't record distribution if distributionLimit is exceeded`, async function () {
    const {
      mockJbTerminal,
      mockJbTerminalSigner,
      mockJbController,
      mockJbFundingCycleStore,
      mockJbFundAccessConstraintsStore,
      mockJbPrices,
      JBSingleTokenPaymentTerminalStore,
      timestamp,
      token,
      CURRENCY_ETH,
    } = await setup();

    await mockJbFundingCycleStore.mock.currentOf.withArgs(PROJECT_ID).returns({
      // mock JBFundingCycle obj
      number: FUNDING_CYCLE_NUM,
      configuration: timestamp,
      basedOn: timestamp,
      start: timestamp,
      duration: 0,
      weight: WEIGHT,
      discountRate: 0,
      ballot: ethers.constants.AddressZero,
      metadata: packFundingCycleMetadata({ pauseDistributions: 0 }),
    });

    // Add to balance beforehand
    await JBSingleTokenPaymentTerminalStore.connect(mockJbTerminalSigner).recordAddedBalanceFor(
      PROJECT_ID,
      AMOUNT,
    );

    const smallDistributionLimit = AMOUNT.subUnsafe(ethers.FixedNumber.from(1));
    await mockJbFundAccessConstraintsStore.mock.distributionLimitOf
      .withArgs(PROJECT_ID, timestamp, mockJbTerminal.address, token, CURRENCY_ETH)
      .returns(smallDistributionLimit); // Set intentionally small distribution limit

    await mockJbController.mock.fundAccessConstraintsStore
      .withArgs()
      .returns(mockJbFundAccessConstraintsStore.address);

    await mockJbTerminal.mock.currency.returns(CURRENCY_ETH);

    // Record the distributions
    await expect(
      JBSingleTokenPaymentTerminalStore.connect(mockJbTerminalSigner).recordDistributionFor(
        PROJECT_ID,
        AMOUNT,
        CURRENCY_ETH,
      ),
    ).to.be.revertedWith(errors.DISTRIBUTION_AMOUNT_LIMIT_REACHED);
  });

  it(`Can't record distribution if distributionLimit is 0`, async function () {
    const {
      mockJbTerminal,
      mockJbTerminalSigner,
      mockJbController,
      mockJbFundingCycleStore,
      mockJbFundAccessConstraintsStore,
      mockJbPrices,
      JBSingleTokenPaymentTerminalStore,
      timestamp,
      token,
      CURRENCY_ETH,
    } = await setup();

    await mockJbFundingCycleStore.mock.currentOf.withArgs(PROJECT_ID).returns({
      // mock JBFundingCycle obj
      number: FUNDING_CYCLE_NUM,
      configuration: timestamp,
      basedOn: timestamp,
      start: timestamp,
      duration: 0,
      weight: WEIGHT,
      discountRate: 0,
      ballot: ethers.constants.AddressZero,
      metadata: packFundingCycleMetadata({ pauseDistributions: 0 }),
    });

    // Add to balance beforehand
    await JBSingleTokenPaymentTerminalStore.connect(mockJbTerminalSigner).recordAddedBalanceFor(
      PROJECT_ID,
      AMOUNT,
    );

    await mockJbFundAccessConstraintsStore.mock.distributionLimitOf
      .withArgs(PROJECT_ID, timestamp, mockJbTerminal.address, token, CURRENCY_ETH)
      .returns(0);

    await mockJbController.mock.fundAccessConstraintsStore
      .withArgs()
      .returns(mockJbFundAccessConstraintsStore.address);

    await mockJbTerminal.mock.currency.returns(CURRENCY_ETH);

    // Record the distributions
    await expect(
      JBSingleTokenPaymentTerminalStore.connect(mockJbTerminalSigner).recordDistributionFor(
        PROJECT_ID,
        0,
        CURRENCY_ETH,
      ),
    ).to.be.revertedWith(errors.DISTRIBUTION_AMOUNT_LIMIT_REACHED);
  });

  it(`Can't record distribution if distributedAmount > project's total balance`, async function () {
    const {
      mockJbTerminal,
      mockJbTerminalSigner,
      mockJbController,
      mockJbFundAccessConstraintsStore,
      mockJbFundingCycleStore,
      mockJbPrices,
      JBSingleTokenPaymentTerminalStore,
      timestamp,
      token,
      CURRENCY_ETH,
    } = await setup();

    await mockJbFundingCycleStore.mock.currentOf.withArgs(PROJECT_ID).returns({
      // mock JBFundingCycle obj
      number: FUNDING_CYCLE_NUM,
      configuration: timestamp,
      basedOn: timestamp,
      start: timestamp,
      duration: 0,
      weight: WEIGHT,
      discountRate: 0,
      ballot: ethers.constants.AddressZero,
      metadata: packFundingCycleMetadata({ pauseDistributions: 0 }),
    });

    // Add intentionally small balance
    const smallBalance = AMOUNT.subUnsafe(ethers.FixedNumber.from(1));
    await JBSingleTokenPaymentTerminalStore.connect(mockJbTerminalSigner).recordAddedBalanceFor(
      PROJECT_ID,
      smallBalance,
    );

    await mockJbFundAccessConstraintsStore.mock.distributionLimitOf
      .withArgs(PROJECT_ID, timestamp, mockJbTerminal.address, token, CURRENCY_ETH)
      .returns(AMOUNT);

    await mockJbController.mock.fundAccessConstraintsStore
      .withArgs()
      .returns(mockJbFundAccessConstraintsStore.address);

    await mockJbTerminal.mock.currency.returns(CURRENCY_ETH);

    // Record the distributions
    await expect(
      JBSingleTokenPaymentTerminalStore.connect(mockJbTerminalSigner).recordDistributionFor(
        PROJECT_ID,
        AMOUNT,
        CURRENCY_ETH,
      ),
    ).to.be.revertedWith(errors.INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE);
  });
});
