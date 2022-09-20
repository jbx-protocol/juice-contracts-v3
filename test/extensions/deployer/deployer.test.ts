import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { BigNumber } from 'ethers';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import * as helpers from '@nomicfoundation/hardhat-network-helpers';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbTerminal from '../../../artifacts/contracts/abstract/JBPayoutRedemptionPaymentTerminal.sol/JBPayoutRedemptionPaymentTerminal.json';

describe('Deployer tests', () => {
    const jbxJbTokensEth = '0x000000000000000000000000000000000000EEEe';
    const provider = ethers.provider;

    let deployer: SignerWithAddress;
    let accounts: SignerWithAddress[];

    let jbxDirectory: any;

    let deployerProxy: any;
    let nfToken: any;
    let mixedPaymentSplitter: any;
    let dutchAuctionHouse: any;

    before('Initialize contracts', async () => {
        [deployer, ...accounts] = await ethers.getSigners();
    });

    before('Setup JBX components', async () => {
        jbxDirectory = await deployMockContract(deployer, jbDirectory.abi);
    });

    it('Deploy Deployer_v001', async () => {
        const nfTokenFactoryFactory = await ethers.getContractFactory('NFTokenFactory', deployer);
        const nfTokenFactoryLibrary = await nfTokenFactoryFactory.connect(deployer).deploy();

        const deployerFactory = await ethers.getContractFactory('Deployer_v001', {
            libraries: { NFTokenFactory: nfTokenFactoryLibrary.address },
            signer: deployer
        });
        deployerProxy = await upgrades.deployProxy(deployerFactory, { kind: 'uups', initializer: 'initialize' });
    });

    it('Deploy NFToken via Deployer', async () => {
        // const tx = await deployerProxy.connect(deployer).deployNFToken(
        //
        // );
        // const receipt = await tx.wait();
    });

    it('Fail to upgrade Deployer_v001', async () => {
        const nfTokenFactoryFactory = await ethers.getContractFactory('NFTokenFactory', deployer);
        const nfTokenFactoryLibrary = await nfTokenFactoryFactory.connect(deployer).deploy();

        const mixedPaymentSplitterFactoryFactory = await ethers.getContractFactory('MixedPaymentSplitterFactory', deployer);
        const mixedPaymentSplitterFactoryLibrary = await mixedPaymentSplitterFactoryFactory.connect(deployer).deploy();

        const deployerFactory = await ethers.getContractFactory('Deployer_v002', {
            libraries: {
                NFTokenFactory: nfTokenFactoryLibrary.address,
                MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryLibrary.address
            },
            signer: accounts[0]
        });

        await expect(upgrades.upgradeProxy(deployerProxy, deployerFactory, { kind: 'uups' })).to.be.reverted;
    });

    it('Deploy Deployer_v002 as upgrade to v001', async () => {
        const nfTokenFactoryFactory = await ethers.getContractFactory('NFTokenFactory', deployer);
        const nfTokenFactoryLibrary = await nfTokenFactoryFactory.connect(deployer).deploy();

        const mixedPaymentSplitterFactoryFactory = await ethers.getContractFactory('MixedPaymentSplitterFactory', deployer);
        const mixedPaymentSplitterFactoryLibrary = await mixedPaymentSplitterFactoryFactory.connect(deployer).deploy();

        const deployerFactory = await ethers.getContractFactory('Deployer_v002', {
            libraries: {
                NFTokenFactory: nfTokenFactoryLibrary.address,
                MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryLibrary.address
            },
            signer: deployer
        });

        deployerProxy = await upgrades.upgradeProxy(deployerProxy, deployerFactory, { kind: 'uups', call: { fn: 'initialize' } });
    });

    it('Deploy MixedPaymentSplitter via Deployer', async () => {
        const tx = await deployerProxy.connect(deployer).deployMixedPaymentSplitter(
            'Test MixedPaymentSplitter',
            [deployer.address, accounts[0].address],
            [],
            [100_000, 100_000],
            jbxDirectory.address,
            deployer.address
        );
        const receipt = await tx.wait();

        const [contractType, contractAddress] = receipt.events.filter(e => e.event === 'Deployment')[0].args;

        const mixedPaymentSplitterFactory = await ethers.getContractFactory('MixedPaymentSplitter', deployer);
        mixedPaymentSplitter = await mixedPaymentSplitterFactory.attach(contractAddress);
    });

    it('Pay into MixedPaymentSplitter', async () => {
        await expect(accounts[0].sendTransaction({ to: mixedPaymentSplitter.address, value: ethers.utils.parseEther('1.0') }))
            .to.emit(mixedPaymentSplitter, 'PaymentReceived');
    });

    it('Distribute Ether payment from MixedPaymentSplitter', async () => {
        const share = ethers.utils.parseEther('1.0').mul(100_000).div(1_000_000);
        const initialBalance = (await provider.getBalance(accounts[0].address)) as BigNumber;

        expect(await mixedPaymentSplitter['pending(address)'](accounts[0].address)).to.equal(share.toString());
        await expect(mixedPaymentSplitter['distribute(address)'](accounts[0].address))
            .to.emit(mixedPaymentSplitter, 'PaymentReleased').withArgs(accounts[0].address, share);

        expect(await provider.getBalance(accounts[0].address)).to.equal(initialBalance.add(share));
    });

    it('Deploy Deployer_v003 as upgrade to v002', async () => {
        const nfTokenFactoryFactory = await ethers.getContractFactory('NFTokenFactory', deployer);
        const nfTokenFactoryLibrary = await nfTokenFactoryFactory.connect(deployer).deploy();

        const mixedPaymentSplitterFactoryFactory = await ethers.getContractFactory('MixedPaymentSplitterFactory', deployer);
        const mixedPaymentSplitterFactoryLibrary = await mixedPaymentSplitterFactoryFactory.connect(deployer).deploy();

        const auctionsFactoryFactory = await ethers.getContractFactory('AuctionsFactory', deployer);
        const auctionsFactoryFactoryLibrary = await auctionsFactoryFactory.connect(deployer).deploy();

        const deployerFactory = await ethers.getContractFactory('Deployer_v003', {
            libraries: {
                NFTokenFactory: nfTokenFactoryLibrary.address,
                MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryLibrary.address,
                AuctionsFactory: auctionsFactoryFactoryLibrary.address
            },
            signer: deployer
        });

        const dutchAuctionHouseFactory = await ethers.getContractFactory('DutchAuctionHouse', { signer: deployer });
        const sourceDutchAuctionHouse = await dutchAuctionHouseFactory.connect(deployer).deploy();
        await sourceDutchAuctionHouse.deployed();

        const englishAuctionHouseFactory = await ethers.getContractFactory('EnglishAuctionHouse', { signer: deployer });
        const sourceEnglishAuctionHouse = await englishAuctionHouseFactory.connect(deployer).deploy();
        await sourceEnglishAuctionHouse.deployed();

        deployerProxy = await upgrades.upgradeProxy(deployerProxy, deployerFactory, { kind: 'uups', call: { fn: 'initialize(address,address)', args: [sourceDutchAuctionHouse.address, sourceEnglishAuctionHouse.address] } });
    });

    it('Deploy DutchAuctionHouse via Deployer', async () => {
        const projectId = 1;
        const feeRate = 5_000_000; // 0.5%
        const periodDuration = 5 * 60; // seconds
        const allowPublicAuctions = true;

        const tx = await deployerProxy.connect(deployer).deployDutchAuction(
            projectId,
            ethers.constants.AddressZero, // IJBPaymentTerminal
            feeRate,
            allowPublicAuctions,
            periodDuration,
            deployer.address,
            jbxDirectory.address
        );
        const receipt = await tx.wait();

        const [contractType, contractAddress] = receipt.events.filter(e => e.event === 'Deployment')[0].args;
        const dutchAuctionHouseFactory = await ethers.getContractFactory('DutchAuctionHouse', { signer: deployer });
        dutchAuctionHouse = await dutchAuctionHouseFactory.attach(contractAddress);
    });

    it('Create an auction (Dutch)', async () => {
        // const startPrice = ethers.utils.parseEther('2');
        // const endPrice = ethers.utils.parseEther('1');
        // const tokenId = 1;
        // const auctionDuration = 60 * 60;
        // const feeDenominator = 1_000_000_000;
    });
});
