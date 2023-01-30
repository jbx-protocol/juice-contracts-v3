import { expect } from 'chai';
import { ethers } from 'hardhat';
import { smock } from '@defi-wonderland/smock';

import jbDirectory from '../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbOperatorStore from '../../artifacts/contracts/JBOperatorStore.sol/JBOperatorStore.json';
import jbProjects from '../../artifacts/contracts/JBProjects.sol/JBProjects.json';

enum TokenType {
    ERC20,
    ERC721,
    ERC1155
}

const JBOperations_MIGRATE_CONTROLLER = 3;

describe('PlatformDiscountManager Tests', () => {
    let deployer;
    let accounts;
    let mock20Token;
    let mock721Token;
    let mock1155Token;
    let discountManager;

    let mockJbDirectory: any;
    let mockJbOperatorStore: any;
    let mockJbProjects: any

    before('Initialize accounts', async () => {
        [deployer, ...accounts] = await ethers.getSigners();
    });

    before('Setup JBX components', async () => {
        mockJbDirectory = await smock.fake(jbDirectory.abi);
        mockJbOperatorStore = await smock.fake(jbOperatorStore.abi);
        mockJbProjects = await smock.fake(jbProjects.abi);

        // platform project
        mockJbOperatorStore.hasPermission.whenCalledWith(deployer.address, deployer.address, 1, JBOperations_MIGRATE_CONTROLLER).returns(true);

        mockJbDirectory.controllerOf.whenCalledWith(1).returns(deployer.address);

        mockJbProjects.ownerOf.whenCalledWith(1).returns(deployer.address);
    });

    before('Initialize contracts', async () => {
        const platformDiscountManagerFactory = await ethers.getContractFactory('PlatformDiscountManager');
        discountManager = await platformDiscountManagerFactory.connect(deployer).deploy(mockJbDirectory.address, mockJbProjects.address, mockJbOperatorStore.address);
        await discountManager.deployed();

        mock20Token = await smock.fake('MockERC20');
        mock20Token.balanceOf.whenCalledWith(accounts[0].address).returns('1000000000000000000000');
        mock20Token.balanceOf.whenCalledWith(accounts[1].address).returns('500000000000000000000');
        mock20Token.balanceOf.whenCalledWith(accounts[2].address).returns(0);
    });

    it('registerDiscount: invalid discount', async () => {
        await expect(discountManager.connect(deployer).registerDiscount(mock20Token.address, TokenType.ERC20, 0, 1_000, 10_001))
            .to.be.revertedWithCustomError(discountManager, 'INVALID_DISCOUNT');
    });

    it('removeDiscount: invalid discount', async () => {
        await expect(discountManager.connect(deployer).removeDiscount(mock20Token.address, TokenType.ERC20, 0, 5_000))
            .to.be.revertedWithCustomError(discountManager, 'INVALID_DISCOUNT');
    });

    it('registerDiscount: discount', async () => {
        await expect(discountManager.connect(deployer).registerDiscount(mock20Token.address, TokenType.ERC20, 0, 1_000, 1_000))
            .not.to.be.reverted;

        await expect(discountManager.connect(deployer).registerDiscount(mock20Token.address, TokenType.ERC20, 0, 10_000, 1_500))
            .not.to.be.reverted;

        await expect(discountManager.connect(deployer).registerDiscount(mock20Token.address, TokenType.ERC20, 0, 100_000, 2_000))
            .not.to.be.reverted;
    });

    it('getDiscountInfo', async () => {
        const info = await discountManager.getDiscountInfo(0);

        expect(info['token']).to.equal(mock20Token.address);
        expect(info['tokenType']).to.equal(TokenType.ERC20);
        expect(info['tokenIndex']).to.equal(0);
        expect(info['tokenBalance']).to.equal(1000);
        expect(info['discount']).to.equal(1000);
    });

    it('removeDiscount: invalid discount', async () => {
        await expect(discountManager.connect(deployer).removeDiscount(mock20Token.address, TokenType.ERC20, 0, 500))
            .to.be.revertedWithCustomError(discountManager, 'INVALID_DISCOUNT');
    });

    it('removeDiscount', async () => {
        await expect(discountManager.connect(deployer).removeDiscount(mock20Token.address, TokenType.ERC20, 0, 10_000))
            .not.to.be.reverted;
    });

    it('getPrice: full price', async () => {
        expect(await discountManager.getPrice(accounts[1].address, ethers.utils.parseEther('1')))
            .to.equal(ethers.utils.parseEther('1'));
    });

    it('getPrice: discounted price', async () => {
        expect(await discountManager.getPrice(accounts[0].address, ethers.utils.parseEther('1')))
            .to.equal(ethers.utils.parseEther('0.9'));
    });
});

