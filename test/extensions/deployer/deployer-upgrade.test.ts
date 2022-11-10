import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { BigNumber } from 'ethers';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import * as helpers from '@nomicfoundation/hardhat-network-helpers';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbTerminal from '../../../artifacts/contracts/abstract/JBPayoutRedemptionPaymentTerminal.sol/JBPayoutRedemptionPaymentTerminal.json';

describe('Deployer upgrade tests', () => {
    const jbxJbTokensEth = '0x000000000000000000000000000000000000EEEe';
    const provider = ethers.provider;

    let deployer: SignerWithAddress;
    let accounts: SignerWithAddress[];

    let jbxDirectory: any;

    let deployerProxy: any;
    let nfTokenFactoryLibrary: any;
    let mixedPaymentSplitterFactoryLibrary: any;
    let auctionsFactoryFactoryLibrary: any;
    let nfuTokenFactoryLibrary: any;
    let paymentProcessorFactoryLibrary: any;
    let nftRewardDataSourceFactoryLibrary: any;
    let auctionMachineFactoryLibrary: any;
    let traitTokenFactoryLibrary: any;

    let sourceDutchAuctionHouse: any;
    let sourceEnglishAuctionHouse: any;
    let nfuToken: any;
    let tokenLiquidator: any;
    let dutchAuctionMachineSource: any;
    let englishAuctionMachineSource: any;
    let traitTokenSource: any;

    let nfToken: any;
    let mixedPaymentSplitter: any;
    let dutchAuctionHouse: any;
    let englishAuctionHouse: any;

    before('Initialize accounts', async () => {
        [deployer, ...accounts] = await ethers.getSigners();
    });

    before('Setup JBX components', async () => {
        jbxDirectory = await deployMockContract(deployer, jbDirectory.abi);
    });

    it('Deploy Deployer_v001', async () => {
        const nfTokenFactoryFactory = await ethers.getContractFactory('NFTokenFactory', deployer);
        nfTokenFactoryLibrary = await nfTokenFactoryFactory.connect(deployer).deploy();

        const deployerFactory = await ethers.getContractFactory('Deployer_v001', {
            libraries: { NFTokenFactory: nfTokenFactoryLibrary.address },
            signer: deployer
        });
        deployerProxy = await upgrades.deployProxy(deployerFactory, { kind: 'uups', initializer: 'initialize' });
    });

    it('Deploy NFToken via Deployer', async () => {
        const tx = await deployerProxy.connect(deployer).deployNFToken(
            deployer.address,
            'Picture Token',
            'NFT',
            'ipfs://token/metadata',
            'ipfs://contract/metadata',
            2,
            jbxDirectory.address,
            1000,
            ethers.utils.parseEther('0.0001'),
            10,
            0,
            0
        );
        const receipt = await tx.wait();

        const [contractType, contractAddress] = receipt.events.filter(e => e.event === 'Deployment')[0].args;

        const mixedPaymentSplitterFactory = await ethers.getContractFactory('NFToken', deployer);
        mixedPaymentSplitter = await mixedPaymentSplitterFactory.attach(contractAddress);
    });

    it('Fail to upgrade Deployer_v001', async () => {
        const mixedPaymentSplitterFactoryFactory = await ethers.getContractFactory('MixedPaymentSplitterFactory', deployer);
        mixedPaymentSplitterFactoryLibrary = await mixedPaymentSplitterFactoryFactory.connect(deployer).deploy();

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
        const auctionsFactoryFactory = await ethers.getContractFactory('AuctionsFactory', deployer);
        auctionsFactoryFactoryLibrary = await auctionsFactoryFactory.connect(deployer).deploy();

        const deployerFactory = await ethers.getContractFactory('Deployer_v003', {
            libraries: {
                NFTokenFactory: nfTokenFactoryLibrary.address,
                MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryLibrary.address,
                AuctionsFactory: auctionsFactoryFactoryLibrary.address
            },
            signer: deployer
        });

        const dutchAuctionHouseFactory = await ethers.getContractFactory('DutchAuctionHouse', { signer: deployer });
        sourceDutchAuctionHouse = await dutchAuctionHouseFactory.connect(deployer).deploy();
        await sourceDutchAuctionHouse.deployed();

        const englishAuctionHouseFactory = await ethers.getContractFactory('EnglishAuctionHouse', { signer: deployer });
        sourceEnglishAuctionHouse = await englishAuctionHouseFactory.connect(deployer).deploy();
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

    it('Deploy DutchAuctionHouse via Deployer', async () => {
        const projectId = 1;
        const feeRate = 5_000_000; // 0.5%
        const allowPublicAuctions = true;

        const tx = await deployerProxy.connect(deployer).deployEnglishAuction(
            projectId,
            ethers.constants.AddressZero, // IJBPaymentTerminal
            feeRate,
            allowPublicAuctions,
            deployer.address,
            jbxDirectory.address
        );
        const receipt = await tx.wait();

        const [contractType, contractAddress] = receipt.events.filter(e => e.event === 'Deployment')[0].args;
        const dutchAuctionHouseFactory = await ethers.getContractFactory('EnglishAuctionHouse', { signer: deployer });
        englishAuctionHouse = await dutchAuctionHouseFactory.attach(contractAddress);
    });

    it('Deploy Deployer_v004 as upgrade to v003', async () => {
        const nfuTokenFactoryFactory = await ethers.getContractFactory('NFUTokenFactory', deployer);
        nfuTokenFactoryLibrary = await nfuTokenFactoryFactory.connect(deployer).deploy();

        const deployerFactory = await ethers.getContractFactory('Deployer_v004', {
            libraries: {
                NFTokenFactory: nfTokenFactoryLibrary.address,
                MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryLibrary.address,
                AuctionsFactory: auctionsFactoryFactoryLibrary.address,
                NFUTokenFactory: nfuTokenFactoryLibrary.address
            },
            signer: deployer
        });

        const nfuTokenFactory = await ethers.getContractFactory('NFUToken', { signer: deployer });
        nfuToken = await nfuTokenFactory.connect(deployer).deploy();
        await nfuToken.deployed();

        deployerProxy = await upgrades.upgradeProxy(deployerProxy, deployerFactory, { kind: 'uups', call: { fn: 'initialize(address,address,address)', args: [sourceDutchAuctionHouse.address, sourceEnglishAuctionHouse.address, nfuToken.address] } });
    });

    it('Create cloned NFTs', async () => {
        const now = await helpers.time.latest();
        const nfuTokenFactory = await ethers.getContractFactory('NFUToken', { signer: deployer });

        const name = 'Test NFT'
        const symbol = 'NFT';
        const baseUri = 'ipfs://hidden';
        const contractUri = 'ipfs://metadata';
        const projectId = 99;
        const unitPrice = ethers.utils.parseEther('0.001');
        const maxSupply = 20;
        const mintAllowance = 2;
        const mintPeriodStart = Math.floor(now + 60 * 60);
        const mintPeriodEnd = Math.floor(now + 24 * 60 * 60);

        const targetAdminAddressA = accounts[0].address;
        const targetAdminAddressB = accounts[1].address;

        let tx = await deployerProxy.connect(deployer).deployNFUToken(targetAdminAddressA, name + ' A', symbol + 'A', baseUri, contractUri, projectId, jbxDirectory.address, maxSupply, unitPrice, mintAllowance);
        let receipt = await tx.wait();

        let [contractType, contractAddress] = receipt.events.filter(e => e.event === 'Deployment')[0].args;
        const tokenA = await nfuTokenFactory.attach(contractAddress);
        tokenA.connect(targetAdminAddressA).updateMintPeriod(mintPeriodStart, mintPeriodEnd);
        await expect(tokenA.connect(deployer).updateMintPeriod(mintPeriodStart, mintPeriodEnd)).to.be.reverted;

        tx = await deployerProxy.connect(deployer).deployNFUToken(targetAdminAddressB, name + ' B', symbol + 'B', baseUri, contractUri, projectId, jbxDirectory.address, maxSupply, unitPrice, mintAllowance);
        receipt = await tx.wait();

        [contractType, contractAddress] = receipt.events.filter(e => e.event === 'Deployment')[0].args;
        const tokenB = await nfuTokenFactory.attach(contractAddress);
        tokenB.connect(targetAdminAddressB).updateMintPeriod(mintPeriodStart, mintPeriodEnd);

        expect(await tokenA.symbol()).to.equal(symbol + 'A');
        expect(await tokenB.symbol()).to.equal(symbol + 'B');
    });

    it('Deploy Deployer_v005 as upgrade to v004', async () => {
        const paymentProcessorFactory = await ethers.getContractFactory('PaymentProcessorFactory', deployer);
        paymentProcessorFactoryLibrary = await paymentProcessorFactory.connect(deployer).deploy();

        const deployerFactory = await ethers.getContractFactory('Deployer_v005', {
            libraries: {
                NFTokenFactory: nfTokenFactoryLibrary.address,
                MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryLibrary.address,
                AuctionsFactory: auctionsFactoryFactoryLibrary.address,
                NFUTokenFactory: nfuTokenFactoryLibrary.address,
                PaymentProcessorFactory: paymentProcessorFactoryLibrary.address
            },
            signer: deployer
        });

        const feeBps = 250;
        const uniswapPoolFee = 3000;
        const tokenLiquidatorFactory = await ethers.getContractFactory('TokenLiquidator', { signer: deployer });
        tokenLiquidator = await tokenLiquidatorFactory.connect(deployer)
            .deploy(ethers.constants.AddressZero, ethers.constants.AddressZero, ethers.constants.AddressZero, feeBps, uniswapPoolFee);
        await tokenLiquidator.deployed();

        deployerProxy = await upgrades.upgradeProxy(deployerProxy, deployerFactory, { kind: 'uups', call: { fn: 'initialize(address,address,address,address)', args: [sourceDutchAuctionHouse.address, sourceEnglishAuctionHouse.address, nfuToken.address, tokenLiquidator.address] } });
    });

    it('Deploy Deployer_v006 as upgrade to v005', async () => {
        const nftRewardDataSourceFactory = await ethers.getContractFactory('NFTRewardDataSourceFactory', deployer);
        nftRewardDataSourceFactoryLibrary = await nftRewardDataSourceFactory.connect(deployer).deploy();

        const deployerFactory = await ethers.getContractFactory('Deployer_v006', {
            libraries: {
                NFTokenFactory: nfTokenFactoryLibrary.address,
                MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryLibrary.address,
                AuctionsFactory: auctionsFactoryFactoryLibrary.address,
                NFUTokenFactory: nfuTokenFactoryLibrary.address,
                PaymentProcessorFactory: paymentProcessorFactoryLibrary.address,
                NFTRewardDataSourceFactory: nftRewardDataSourceFactoryLibrary.address
            },
            signer: deployer
        });

        deployerProxy = await upgrades.upgradeProxy(deployerProxy, deployerFactory, { kind: 'uups', call: { fn: 'initialize(address,address,address,address)', args: [sourceDutchAuctionHouse.address, sourceEnglishAuctionHouse.address, nfuToken.address, tokenLiquidator.address] } });
    });

    it('Deploy Deployer_v007 as upgrade to v006', async () => {
        const auctionMachineFactory = await ethers.getContractFactory('AuctionMachineFactory', deployer);
        auctionMachineFactoryLibrary = await auctionMachineFactory.connect(deployer).deploy();

        const traitTokenFactoryFactory = await ethers.getContractFactory('TraitTokenFactory', deployer);
        traitTokenFactoryLibrary = await traitTokenFactoryFactory.connect(deployer).deploy();

        const deployerFactory = await ethers.getContractFactory('Deployer_v007', {
            libraries: {
                NFTokenFactory: nfTokenFactoryLibrary.address,
                MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryLibrary.address,
                AuctionsFactory: auctionsFactoryFactoryLibrary.address,
                NFUTokenFactory: nfuTokenFactoryLibrary.address,
                PaymentProcessorFactory: paymentProcessorFactoryLibrary.address,
                NFTRewardDataSourceFactory: nftRewardDataSourceFactoryLibrary.address,
                AuctionMachineFactory: auctionMachineFactoryLibrary.address,
                TraitTokenFactory: traitTokenFactoryLibrary.address
            },
            signer: deployer
        });

        const dutchAuctionMachineFactory = await ethers.getContractFactory('DutchAuctionMachine', { signer: deployer });
        dutchAuctionMachineSource = await dutchAuctionMachineFactory.connect(deployer).deploy();
        await dutchAuctionMachineSource.deployed();

        const englishAuctionMachineFactory = await ethers.getContractFactory('EnglishAuctionMachine', { signer: deployer });
        englishAuctionMachineSource = await englishAuctionMachineFactory.connect(deployer).deploy();
        await englishAuctionMachineSource.deployed();

        const traitTokenFactory = await ethers.getContractFactory('TraitToken', { signer: deployer });
        traitTokenSource = await traitTokenFactory.connect(deployer).deploy();
        await traitTokenSource.deployed();

        deployerProxy = await upgrades.upgradeProxy(deployerProxy, deployerFactory, { kind: 'uups', call: { fn: 'initialize(address,address,address,address,address,address,address)', args: [sourceDutchAuctionHouse.address, sourceEnglishAuctionHouse.address, nfuToken.address, tokenLiquidator.address, dutchAuctionMachineSource.address, englishAuctionMachineSource.address, traitTokenSource.address] } });

        await expect(englishAuctionMachineSource.transferOwnership(deployerProxy.address)).not.to.be.reverted;
        await expect(dutchAuctionMachineSource.transferOwnership(deployerProxy.address)).not.to.be.reverted;
    });

    it('Deploy EnglishAuctionMachine clone', async () => {
        const nfuTokenFactory = await ethers.getContractFactory('NFUToken', { signer: deployer });
        const englishAuctionMachineFactory = await ethers.getContractFactory('EnglishAuctionMachine', { signer: deployer });

        const name = 'Test NFT'
        const symbol = 'NFT';
        const baseUri = 'ipfs://hidden';
        const contractUri = 'ipfs://metadata';
        const projectId = 99;
        const unitPrice = ethers.utils.parseEther('0.001');
        const maxSupply = 20;
        const mintAllowance = 2;

        let tx = await deployerProxy.connect(deployer).deployNFUToken(deployer.address, name + ' A', symbol + 'A', baseUri, contractUri, projectId, jbxDirectory.address, maxSupply, unitPrice, mintAllowance);
        let receipt = await tx.wait();

        let [contractType, contractAddress] = receipt.events.filter(e => e.event === 'Deployment')[0].args;
        const token = await nfuTokenFactory.attach(contractAddress);

        const auctionCap = 10;
        const auctionDuration = 60 * 60;

        tx = await deployerProxy.connect(deployer).deployEnglishAuctionMachine(auctionCap, auctionDuration, projectId, jbxDirectory.address, token.address, deployer.address);
        receipt = await tx.wait();
        [contractType, contractAddress] = receipt.events.filter(e => e.event === 'Deployment')[0].args;
        const machine = await englishAuctionMachineFactory.attach(contractAddress);

        await expect(machine.initialize(auctionCap, auctionDuration, projectId, jbxDirectory, token.address, deployer.address)).to.be.reverted;
        await expect(token.connect(accounts[0]).addMinter(machine.address)).to.be.reverted;
        await token.connect(deployer).addMinter(machine.address);
        await expect(machine.connect(accounts[0]).bid({ value: 0 })).not.to.be.reverted;

        expect(await machine.currentTokenId()).to.equal(1);
        expect(await token.totalSupply()).to.equal(1);
        expect(await token.ownerOf(1)).to.equal(machine.address);
    });

    it('Deploy DutchAuctionMachine clone', async () => {
        const nfuTokenFactory = await ethers.getContractFactory('NFUToken', { signer: deployer });
        const dutchAuctionMachineFactory = await ethers.getContractFactory('DutchAuctionMachine', { signer: deployer });

        const name = 'Test NFT'
        const symbol = 'NFT';
        const baseUri = 'ipfs://hidden';
        const contractUri = 'ipfs://metadata';
        const projectId = 99;
        const unitPrice = ethers.utils.parseEther('0.001');
        const maxSupply = 20;
        const mintAllowance = 2;

        let tx = await deployerProxy.connect(deployer).deployNFUToken(deployer.address, name + ' A', symbol + 'A', baseUri, contractUri, projectId, jbxDirectory.address, maxSupply, unitPrice, mintAllowance);
        let receipt = await tx.wait();

        let [contractType, contractAddress] = receipt.events.filter(e => e.event === 'Deployment')[0].args;
        const token = await nfuTokenFactory.attach(contractAddress);

        const auctionCap = 10;
        const auctionDuration = 60 * 60;
        const periodDuration = 600;
        const priceMultiplier = 6;

        tx = await deployerProxy.connect(deployer).deployDutchAuctionMachine(auctionCap, auctionDuration, periodDuration, priceMultiplier, projectId, jbxDirectory.address, token.address, deployer.address);
        receipt = await tx.wait();
        [contractType, contractAddress] = receipt.events.filter(e => e.event === 'Deployment')[0].args;
        const machine = await dutchAuctionMachineFactory.attach(contractAddress);

        await expect(machine.initialize(auctionCap, auctionDuration, periodDuration, priceMultiplier, projectId, jbxDirectory, token.address, deployer.address)).to.be.reverted;
        await expect(token.connect(accounts[0]).addMinter(machine.address)).to.be.reverted;
        await token.connect(deployer).addMinter(machine.address);
        await expect(machine.connect(accounts[0]).bid({ value: 0 })).not.to.be.reverted;

        expect(await machine.currentTokenId()).to.equal(1);
        expect(await token.totalSupply()).to.equal(1);
        expect(await token.ownerOf(1)).to.equal(machine.address);
    });
});
