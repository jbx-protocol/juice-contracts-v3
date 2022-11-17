import { expect } from 'chai';
import { ethers } from 'hardhat';

describe('TieredTokenUriResolver Tests', () => {
    let deployer;
    let uriResolver: any;

    const baseUri = 'ipfs://base_uri/';
    const invalidTiers = [2000, 1000, 2500, 2550];
    const tiers = [1000, 2000, 2500, 2550,];

    before(async () => {
        [deployer,] = await ethers.getSigners();
    });

    it('constructor(): fail due to unsorted tiers', async () => {
        const resolverFactory = await ethers.getContractFactory('TieredTokenUriResolver');
        await expect(resolverFactory.connect(deployer).deploy(baseUri, invalidTiers)).to.be.revertedWith('INVALID_ID_SORT_ORDER(1)');
    });

    it('constructor(): success', async () => {
        const resolverFactory = await ethers.getContractFactory('TieredTokenUriResolver');
        uriResolver = await resolverFactory.connect(deployer).deploy(baseUri, tiers);
        await uriResolver.deployed();
    });

    it('tokenURI(): fail, id out of range', async () => {
        const tokenId = tiers[tiers.length - 1] + 1;

        await expect(uriResolver.tokenURI(tokenId)).to.be.revertedWithCustomError(uriResolver, 'ID_OUT_OF_RANGE');
    });

    it('tokenURI(): valid tiers', async () => {
        let tierIndex = 0
        let tokenId = tiers[tierIndex] - 1;
        let tokenUri = await uriResolver.tokenURI(tokenId) as String;

        expect(tokenUri).to.equal(`${baseUri}${tierIndex + 1}`);

        tierIndex = tiers.length - 1;
        tokenId = tiers[tierIndex] - 1;
        tokenUri = await uriResolver.tokenURI(tokenId) as String;

        expect(tokenUri).to.equal(`${baseUri}${tierIndex + 1}`);
    });
});
