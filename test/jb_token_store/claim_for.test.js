import { expect } from 'chai';
import { ethers } from 'hardhat';

import { deployMockContract } from '@ethereum-waffle/mock-contract';

import jbDirectory from '../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbFundingCycleStore from '../../artifacts/contracts/JBFundingCycleStore.sol/JBFundingCycleStore.json';
import jbOperatoreStore from '../../artifacts/contracts/JBOperatorStore.sol/JBOperatorStore.json';
import jbProjects from '../../artifacts/contracts/JBProjects.sol/JBProjects.json';
import errors from '../helpers/errors.json';

describe('JBTokenStore::claimFor(...)', function () {
  const PROJECT_ID = 2;
  const TOKEN_NAME = 'TestTokenDAO';
  const TOKEN_SYMBOL = 'TEST';

  async function setup() {
    const [deployer, controller, newHolder, beneficiary, projectOwner] = await ethers.getSigners();

    const mockJbDirectory = await deployMockContract(deployer, jbDirectory.abi);
    const mockJbFundingCycleStore = await deployMockContract(deployer, jbFundingCycleStore.abi);
    const mockJbOperatorStore = await deployMockContract(deployer, jbOperatoreStore.abi);
    const mockJbProjects = await deployMockContract(deployer, jbProjects.abi);
    const jbOperationsFactory = await ethers.getContractFactory('JBOperations');
    const jbOperations = await jbOperationsFactory.deploy();

    const CLAIM_INDEX = await jbOperations.CLAIM();

    const jbTokenStoreFactory = await ethers.getContractFactory('JBTokenStore');
    const jbTokenStore = await jbTokenStoreFactory.deploy(
      mockJbOperatorStore.address,
      mockJbProjects.address,
      mockJbDirectory.address,
      mockJbFundingCycleStore.address,
    );

    await mockJbProjects.mock.ownerOf.withArgs(PROJECT_ID).returns(projectOwner.address);

    return {
      controller,
      newHolder,
      beneficiary,
      projectOwner,
      mockJbDirectory,
      mockJbProjects,
      mockJbOperatorStore,
      jbTokenStore,
      CLAIM_INDEX,
    };
  }

  it('Should claim tokens and emit event', async function () {
    const {
      controller,
      newHolder,
      projectOwner,
      mockJbDirectory,
      mockJbOperatorStore,
      mockJbProjects,
      jbTokenStore,
      CLAIM_INDEX,
    } = await setup();

    // Mint access:
    await mockJbDirectory.mock.controllerOf.withArgs(PROJECT_ID).returns(controller.address);

    // Issue access:
    await mockJbProjects.mock.ownerOf.withArgs(PROJECT_ID).returns(controller.address);

    await jbTokenStore.connect(controller).issueFor(PROJECT_ID, TOKEN_NAME, TOKEN_SYMBOL);
    await mockJbOperatorStore.mock.hasPermission
      .withArgs(controller.address, newHolder.address, PROJECT_ID, CLAIM_INDEX)
      .returns(true);

    // Mint more unclaimed tokens
    const numTokens = 20;
    await jbTokenStore
      .connect(controller)
      .mintFor(newHolder.address, PROJECT_ID, numTokens, /* preferClaimedTokens= */ false);

    const amountToClaim = numTokens - 1;

    // Claim the unclaimed tokens
    const claimForTx = await jbTokenStore
      .connect(controller)
      .claimFor(newHolder.address, PROJECT_ID, amountToClaim, newHolder.address);

    expect(await jbTokenStore.unclaimedBalanceOf(newHolder.address, PROJECT_ID)).to.equal(
      numTokens - amountToClaim,
    );
    expect(await jbTokenStore.balanceOf(newHolder.address, PROJECT_ID)).to.equal(numTokens);
    expect(await jbTokenStore.totalSupplyOf(PROJECT_ID)).to.equal(numTokens);

    await expect(claimForTx)
      .to.emit(jbTokenStore, 'Claim')
      .withArgs(newHolder.address, PROJECT_ID, numTokens, amountToClaim, newHolder.address, controller.address);
  });
  it('Should claim tokens to a different beneficiary and emit event', async function () {
    const {
      controller,
      newHolder,
      projectOwner,
      mockJbDirectory,
      mockJbOperatorStore,
      mockJbProjects,
      jbTokenStore,
      beneficiary,
      CLAIM_INDEX,
      addrs
    } = await setup();

    // Mint access:
    await mockJbDirectory.mock.controllerOf.withArgs(PROJECT_ID).returns(controller.address);

    // Issue access:
    await mockJbProjects.mock.ownerOf.withArgs(PROJECT_ID).returns(controller.address);

    await jbTokenStore.connect(controller).issueFor(PROJECT_ID, TOKEN_NAME, TOKEN_SYMBOL);
    await mockJbOperatorStore.mock.hasPermission
      .withArgs(controller.address, newHolder.address, PROJECT_ID, CLAIM_INDEX)
      .returns(true);

    // Mint more unclaimed tokens
    const numTokens = 20;
    await jbTokenStore
      .connect(controller)
      .mintFor(newHolder.address, PROJECT_ID, numTokens, /* preferClaimedTokens= */ false);

    const amountToClaim = numTokens - 1;

    // Claim the unclaimed tokens
    const claimForTx = await jbTokenStore
      .connect(controller)
      .claimFor(newHolder.address, PROJECT_ID, amountToClaim, beneficiary.address);

    expect(await jbTokenStore.unclaimedBalanceOf(newHolder.address, PROJECT_ID)).to.equal(
      numTokens - amountToClaim,
    );
    expect(await jbTokenStore.unclaimedBalanceOf(beneficiary.address, PROJECT_ID)).to.equal(0);
    expect(await jbTokenStore.balanceOf(newHolder.address, PROJECT_ID)).to.equal(numTokens - amountToClaim);
    expect(await jbTokenStore.balanceOf(beneficiary.address, PROJECT_ID)).to.equal(amountToClaim);
    expect(await jbTokenStore.totalSupplyOf(PROJECT_ID)).to.equal(numTokens);

    await expect(claimForTx)
      .to.emit(jbTokenStore, 'Claim')
      .withArgs(newHolder.address, PROJECT_ID, numTokens, amountToClaim, beneficiary.address, controller.address);
  });
  it(`Can't claim tokens if projectId isn't found`, async function () {
    const { newHolder, jbTokenStore } = await setup();
    const numTokens = 1;

    await expect(
      jbTokenStore.connect(newHolder).claimFor(newHolder.address, PROJECT_ID, numTokens, newHolder.address),
    ).to.be.revertedWith(errors.TOKEN_NOT_FOUND);
  });

  it(`Can't claim more tokens than the current _unclaimedBalance`, async function () {
    const { controller, newHolder, mockJbDirectory, mockJbProjects, jbTokenStore, CLAIM_INDEX } =
      await setup();

    await mockJbDirectory.mock.controllerOf.withArgs(PROJECT_ID).returns(controller.address);
    await mockJbProjects.mock.ownerOf.withArgs(PROJECT_ID).returns(controller.address);

    await jbTokenStore.connect(controller).issueFor(PROJECT_ID, TOKEN_NAME, TOKEN_SYMBOL);

    // Mint more unclaimed tokens
    const numTokens = 10000;
    await jbTokenStore
      .connect(controller)
      .mintFor(newHolder.address, PROJECT_ID, numTokens, /* preferClaimedTokens= */ false);

    await expect(
      jbTokenStore.connect(newHolder).claimFor(newHolder.address, PROJECT_ID, numTokens + 1, newHolder.address),
    ).to.be.revertedWith(errors.INSUFFICIENT_UNCLAIMED_TOKENS);
  });
  it(`Can't claim unclaimed tokens if caller lacks permission`, async function () {
    const { controller, newHolder, jbTokenStore } = await setup();

    await expect(
      jbTokenStore
        .connect(controller)
        .claimFor(/* holder */ newHolder.address, PROJECT_ID, /* amount= */ 1, newHolder.address),
    ).to.be.reverted;
  });
});
