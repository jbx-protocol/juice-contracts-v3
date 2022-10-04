import { expect } from 'chai';
import { ethers } from 'hardhat';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import * as helpers from '@nomicfoundation/hardhat-network-helpers';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbTerminal from '../../../artifacts/contracts/abstract/JBPayoutRedemptionPaymentTerminal.sol/JBPayoutRedemptionPaymentTerminal.json';

describe('EnglishAuctionMachine tests', () => {
    const jbxJbTokensEth = '0x000000000000000000000000000000000000EEEe';

    let deployer: SignerWithAddress;
    let accounts: SignerWithAddress[];

    let directory;
    let terminal: any;

    let basicToken: any;
    let englishAuctionMachine: any;

    const basicBaseUri = 'ipfs://hidden';
    const basicBaseUriRevealed = 'ipfs://revealed/';
    const basicContractUri = 'ipfs://metadata';
    const basicProjectId = 99;
    const basicUnitPrice = ethers.utils.parseEther('0.001');
    const basicMaxSupply = 20;
    const basicMintAllowance = 2
    let basicMintPeriodStart: number;
    let basicMintPeriodEnd: number;

    before('Initialize accounts', async () => {
        [deployer, ...accounts] = await ethers.getSigners();
    });

    before('Setup JBX components', async () => {
        directory = await deployMockContract(deployer, jbDirectory.abi);
        terminal = await deployMockContract(deployer, jbTerminal.abi);

        await terminal.mock.pay.returns(0);
        await directory.mock.isTerminalOf.withArgs(basicProjectId, terminal.address).returns(true);
        await directory.mock.primaryTerminalOf.withArgs(basicProjectId, jbxJbTokensEth).returns(terminal.address);
    });

    before('Initialize NFT', async () => {
        const basicName = 'Test NFT'
        const basicSymbol = 'NFT';

        const now = await helpers.time.latest();
        basicMintPeriodStart = Math.floor(now + 60 * 60);
        basicMintPeriodEnd = Math.floor(now + 24 * 60 * 60);

        const nfTokenFactory = await ethers.getContractFactory('NFToken');
        basicToken = await nfTokenFactory
            .connect(deployer)
            .deploy(
                basicName,
                basicSymbol,
                basicBaseUri,
                basicContractUri,
                basicProjectId,
                directory.address,
                basicMaxSupply,
                basicUnitPrice,
                basicMintAllowance,
                basicMintPeriodStart,
                basicMintPeriodEnd
            );
    });

    before('Initialize Auction Machine', async () => {
        const englishAuctionMachineFactory = await ethers.getContractFactory('EnglishAuctionMachine');
        englishAuctionMachine = await englishAuctionMachineFactory.connect(deployer)
            .deploy(10, 60 * 60, basicProjectId, directory.address, basicToken.address);

        await basicToken.connect(deployer).addMinter(englishAuctionMachine.address);
    });

    it('Create first contract by placing a valid bid', async () => {
        expect(await basicToken.totalSupply()).to.equal(0);

        await englishAuctionMachine.connect(accounts[0]).bid({ value: basicUnitPrice });

        expect(await basicToken.totalSupply()).to.equal(1);
        expect(await basicToken.balanceOf(englishAuctionMachine.address)).to.equal(1);
    });

    it('Increase bid', async () => {
        expect(await englishAuctionMachine.timeLeft()).to.be.greaterThan(0);

        await englishAuctionMachine.connect(accounts[1]).bid({ value: basicUnitPrice.mul(2) });
    });

    it('Complete auction', async () => {
        const now = await helpers.time.latest();
        const remaining = await englishAuctionMachine.timeLeft();
        await helpers.time.increaseTo(remaining.add(now).add(60));

        await englishAuctionMachine.settle();

        expect(await basicToken.totalSupply()).to.equal(2);
        expect(await basicToken.balanceOf(englishAuctionMachine.address)).to.equal(1);
        expect(await basicToken.balanceOf(accounts[1].address)).to.equal(1);
    });
});
