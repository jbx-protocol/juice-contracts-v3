import { expect } from 'chai';
import { companionNetworks, ethers } from 'hardhat';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import { impersonateAccount } from '../helpers/utils';
import errors from '../helpers/errors.json';

import jbController3_1 from '../../artifacts/contracts/JBController3_1.sol/JBController3_1.json';
import jbDirectory from '../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbTerminal from '../../artifacts/contracts/JBETHPaymentTerminal.sol/JBETHPaymentTerminal.json';

function makeFundingAccessConstraints({
  terminals,
  token = ethers.Wallet.createRandom().address,
  distributionLimit = 200,
  distributionLimitCurrency = 1,
  overflowAllowance = 100,
  overflowAllowanceCurrency = 2,
} = {}) {
  let constraints = [];
  for (let terminal of terminals) {
    constraints.push({
      terminal,
      token,
      distributionLimit,
      distributionLimitCurrency,
      overflowAllowance,
      overflowAllowanceCurrency,
    });
  }
  return constraints;
}

describe.only('JBFundAccessConstraintsStore::setFor(...)', function () {
  const PROJECT_ID = 1;
  const DISTRIBUTION_LIMIT = ethers.BigNumber.from('12345');
  const DISTRIBUTION_LIMIT_CURRENCY = ethers.BigNumber.from('1');
  const OVERFLOW_ALLOWANCE = ethers.BigNumber.from('696969');
  const OVERFLOW_ALLOWANCE_CURRENCY = ethers.BigNumber.from('2');

  const DISTRIBUTION_LIMIT2 = ethers.BigNumber.from('12345');
  const DISTRIBUTION_LIMIT_CURRENCY2 = ethers.BigNumber.from('1');
  const OVERFLOW_ALLOWANCE2 = ethers.BigNumber.from('696969');
  const OVERFLOW_ALLOWANCE_CURRENCY2 = ethers.BigNumber.from('2');

  async function setup() {
    let [deployer, projectOwner, caller, ...addrs] = await ethers.getSigners();

    const blockNum = await ethers.provider.getBlockNumber();
    const block = await ethers.provider.getBlock(blockNum);
    const timestamp = block.timestamp;

    let [mockJbDirectory, mockJbControllerAbi, mockJbTerminal, mockJbTerminal2] = await Promise.all(
      [
        deployMockContract(deployer, jbDirectory.abi),
        deployMockContract(deployer, jbController3_1.abi),
        deployMockContract(deployer, jbTerminal.abi),
        deployMockContract(deployer, jbTerminal.abi),
      ],
    );

    const mockJbController = await impersonateAccount(mockJbControllerAbi.address);

    let jbConstraintsStoreFactory = await ethers.getContractFactory(
      'contracts/JBFundAccessConstraintsStore.sol:JBFundAccessConstraintsStore',
    );
    let jbConstraintsStore = await jbConstraintsStoreFactory.deploy(mockJbDirectory.address);

    await Promise.all([
      mockJbDirectory.mock.controllerOf.withArgs(PROJECT_ID).returns(mockJbController.address),
    ]);

    return {
      projectOwner,
      caller,
      addrs,
      jbConstraintsStore,
      mockJbController,
      mockJbTerminal,
      mockJbTerminal2,
      timestamp,
    };
  }

  it(`Should set overflow allowance and distribution limit, and emit event`, async function () {
    const { jbConstraintsStore, mockJbController, mockJbTerminal, mockJbTerminal2, timestamp } =
      await setup();

    const fundConstraints = makeFundingAccessConstraints({
      terminals: [mockJbTerminal.address, mockJbTerminal2.address],
      token: ethers.Wallet.createRandom().address,
      distributionLimit: DISTRIBUTION_LIMIT,
      distributionLimitCurrency: DISTRIBUTION_LIMIT_CURRENCY,
      overflowAllowance: OVERFLOW_ALLOWANCE,
      overflowAllowanceCurrency: OVERFLOW_ALLOWANCE_CURRENCY,
    });

    fundConstraints[1].distributionLimit = DISTRIBUTION_LIMIT2;
    fundConstraints[1].distributionLimitCurrency = DISTRIBUTION_LIMIT_CURRENCY2;
    fundConstraints[1].overflowAllowance = OVERFLOW_ALLOWANCE2;
    fundConstraints[1].overflowAllowanceCurrency = OVERFLOW_ALLOWANCE_CURRENCY2;

    await expect(
      jbConstraintsStore.connect(mockJbController).setFor(PROJECT_ID, timestamp, fundConstraints),
    )
      .to.emit(jbConstraintsStore, 'SetFundAccessConstraints')
      .withArgs(
        timestamp,
        PROJECT_ID,
        [
          mockJbTerminal.address,
          fundConstraints[0].token,
          DISTRIBUTION_LIMIT,
          DISTRIBUTION_LIMIT_CURRENCY,
          OVERFLOW_ALLOWANCE,
          OVERFLOW_ALLOWANCE_CURRENCY,
        ],
        mockJbController.address,
      )
      .and.to.emit(jbConstraintsStore, 'SetFundAccessConstraints')
      .withArgs(
        timestamp,
        PROJECT_ID,
        [
          mockJbTerminal2.address,
          fundConstraints[1].token,
          DISTRIBUTION_LIMIT2,
          DISTRIBUTION_LIMIT_CURRENCY2,
          OVERFLOW_ALLOWANCE2,
          OVERFLOW_ALLOWANCE_CURRENCY2,
        ],
        mockJbController.address,
      );

    expect(
      await jbConstraintsStore.distributionLimitOf(
        PROJECT_ID,
        timestamp,
        mockJbTerminal.address,
        fundConstraints[0].token,
      ),
    ).to.eql([DISTRIBUTION_LIMIT, DISTRIBUTION_LIMIT_CURRENCY]);

    expect(
      await jbConstraintsStore.distributionLimitOf(
        PROJECT_ID,
        timestamp,
        mockJbTerminal2.address,
        fundConstraints[1].token,
      ),
    ).to.eql([DISTRIBUTION_LIMIT2, DISTRIBUTION_LIMIT_CURRENCY2]);

    expect(
      await jbConstraintsStore.overflowAllowanceOf(
        PROJECT_ID,
        timestamp,
        mockJbTerminal.address,
        fundConstraints[0].token,
      ),
    ).to.eql([OVERFLOW_ALLOWANCE, OVERFLOW_ALLOWANCE_CURRENCY]);

    expect(
      await jbConstraintsStore.overflowAllowanceOf(
        PROJECT_ID,
        timestamp,
        mockJbTerminal2.address,
        fundConstraints[1].token,
      ),
    ).to.eql([OVERFLOW_ALLOWANCE2, OVERFLOW_ALLOWANCE_CURRENCY2]);
  });

  it(`Can't set a distribution limit larger than uint232`, async function () {
    const { jbConstraintsStore, mockJbController, mockJbTerminal, timestamp } = await setup();

    const fundConstraints = makeFundingAccessConstraints({
      terminals: [mockJbTerminal.address],
      distributionLimit: ethers.constants.MaxUint256,
    });

    let tx = jbConstraintsStore
      .connect(mockJbController)
      .setFor(PROJECT_ID, timestamp, fundConstraints);

    await expect(tx).to.be.revertedWith(errors.INVALID_DISTRIBUTION_LIMIT);
  });

  it(`Can't launch a project with distribution limit currency larger than uint24`, async function () {
    const { jbConstraintsStore, mockJbController, mockJbTerminal, timestamp } = await setup();

    const fundConstraints = makeFundingAccessConstraints({
      terminals: [mockJbTerminal.address],
      distributionLimitCurrency: ethers.constants.MaxUint256,
    });

    let tx = jbConstraintsStore
      .connect(mockJbController)
      .setFor(PROJECT_ID, timestamp, fundConstraints);

    await expect(tx).to.be.revertedWith(errors.INVALID_DISTRIBUTION_LIMIT_CURRENCY);
  });

  it(`Can't launch a project with overflow allowance larger than uint232`, async function () {
    const { jbConstraintsStore, mockJbController, mockJbTerminal, timestamp } = await setup();

    const fundConstraints = makeFundingAccessConstraints({
      terminals: [mockJbTerminal.address],
      overflowAllowance: ethers.constants.MaxUint256, // Should be too large
    });

    let tx = jbConstraintsStore
      .connect(mockJbController)
      .setFor(PROJECT_ID, timestamp, fundConstraints);

    await expect(tx).to.be.revertedWith(errors.INVALID_OVERFLOW_ALLOWANCE);
  });

  it(`Can't launch a project with overflow allowance currency larger than uint24`, async function () {
    const { jbConstraintsStore, mockJbController, mockJbTerminal, timestamp } = await setup();

    const fundConstraints = makeFundingAccessConstraints({
      terminals: [mockJbTerminal.address],
      overflowAllowanceCurrency: ethers.constants.MaxUint256, // Should be too large
    });

    let tx = jbConstraintsStore
      .connect(mockJbController)
      .setFor(PROJECT_ID, timestamp, fundConstraints);

    await expect(tx).to.be.revertedWith(errors.INVALID_OVERFLOW_ALLOWANCE_CURRENCY);
  });

  // revert if caller is not controller
  it(`Can't launch a project with overflow allowance currency larger than uint24`, async function () {
    const { jbConstraintsStore, caller, mockJbTerminal, timestamp } = await setup();

    const fundConstraints = makeFundingAccessConstraints({
      terminals: [mockJbTerminal.address],
    });

    let tx = jbConstraintsStore.connect(caller).setFor(PROJECT_ID, timestamp, fundConstraints);

    await expect(tx).to.be.revertedWith(errors.CONTROLLER_UNAUTHORIZED);
  });
});
