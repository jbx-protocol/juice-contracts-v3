import { expect } from 'chai';
import { ethers } from 'hardhat';
import jbChainlinkPriceFeed from '../../artifacts/contracts/JBChainlinkV3PriceFeed.sol/JBChainlinkV3PriceFeed.json';
import jbProjects from '../../artifacts/contracts/interfaces/IJBProjects.sol/IJBProjects.json';
import jbOperatorStore from '../../artifacts/contracts/interfaces/IJBOperatorStore.sol/IJBOperatorStore.json';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import errors from '../helpers/errors.json';

describe('JBPrices::addFeed(...)', function () {
  async function setup() {
    const [deployer, addr] = await ethers.getSigners();

    const mockJbProjects = await deployMockContract(deployer, jbProjects.abi);
    const mockJbOperatorStore = await deployMockContract(deployer, jbOperatorStore.abi);
    let jbPricesFactory = await ethers.getContractFactory('JBPrices');
    let priceFeed = await deployMockContract(deployer, jbChainlinkPriceFeed.abi);
    let jbPrices = await jbPricesFactory.deploy(mockJbOperatorStore.address, mockJbProjects.address, deployer.address);

    return {
      deployer,
      addr,
      mockJbProjects,
      mockJbOperatorStore,
      priceFeed,
      jbPrices
    };
  }

  it('Add feed from owner succeeds, but fails if added again', async function () {
    const { deployer, mockJbProjects, priceFeed, jbPrices } = await setup();

    const projectId = 1;

    await mockJbProjects.mock.ownerOf.withArgs(projectId).returns(deployer.address);

    let currency = 1;
    let base = 2;

    // Add a feed for an arbitrary currency.
    let tx = await jbPrices.connect(deployer).addFeedFor(projectId, currency, base, priceFeed.address);

    // Expect an event to have been emitted.
    await expect(tx).to.emit(jbPrices, 'AddFeed').withArgs(projectId, currency, base, priceFeed.address);

    // Get the stored feed.
    const storedFeed = await jbPrices.feedFor(projectId, currency, base);

    // Expect the stored feed values to match.
    expect(storedFeed).to.equal(priceFeed.address);

    // Try to add the same feed again. It should fail with an error indicating that it already
    // exists.
    await expect(
      jbPrices.connect(deployer).addFeedFor(projectId, currency, base, priceFeed.address),
    ).to.be.revertedWith(errors.PRICE_FEED_ALREADY_EXISTS);
  });

  it('Add feed from address other than owner fails', async function () {
    const { deployer, addr, mockJbProjects, mockJbOperatorStore, jbPrices, priceFeed } = await setup();
    const projectId = 1;
    await mockJbProjects.mock.ownerOf.withArgs(projectId).returns(deployer.address);
    await mockJbOperatorStore.mock.hasPermission
      .withArgs(
        addr.address,
        deployer.address,
        projectId,
        19
      )
      .returns(false);
    await mockJbOperatorStore.mock.hasPermission
      .withArgs(
        addr.address,
        deployer.address,
        0,
        19
      )
      .returns(false);
    await expect(
      jbPrices
        .connect(addr) // Arbitrary address.
        .addFeedFor(projectId, /*currency=*/ 1, /*base=*/ 2, priceFeed.address),
    ).to.be.revertedWith('UNAUTHORIZED()');;
  });
});
