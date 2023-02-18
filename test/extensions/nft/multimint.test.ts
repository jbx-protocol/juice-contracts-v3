import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { smock } from '@defi-wonderland/smock';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import * as helpers from '@nomicfoundation/hardhat-network-helpers';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbTerminal from '../../../artifacts/contracts/abstract/JBPayoutRedemptionPaymentTerminal.sol/JBPayoutRedemptionPaymentTerminal.json';
import iQuoter from '../../../artifacts/contracts/extensions/NFT/components/BaseNFT.sol/IQuoter.json';

describe('Multi-mint NFT tests (static price)', () => {
    const jbxJbTokensEth = '0x000000000000000000000000000000000000EEEe';

    let deployer: SignerWithAddress;
    let accounts: SignerWithAddress[];

    let directory: any;
    let terminal: any;
    let uniswapQuoter: any;

    let nfTokenFactory: any;
    let basicToken: any;
    let editionTokenFactory: any;
    let randomizedEditionToken: any;
    let editionToken: any;
    const basicBaseUri = 'ipfs://hidden';
    const basicBaseUriRevealed = 'ipfs://revealed/';
    const basicContractUri = 'ipfs://metadata';
    const basicProjectId = 99;
    const basicUnitPrice = ethers.utils.parseEther('0.001');
    const basicMaxSupply = 20;
    const basicMintAllowance = 4;
    let basicMintPeriodStart: number;
    let basicMintPeriodEnd: number;

    before('Initialize accounts', async () => {
        [deployer, ...accounts] = await ethers.getSigners();
    });

    before('Mock related contracts', async () => {
        directory = await smock.fake(jbDirectory.abi);
        terminal = await smock.fake(jbTerminal.abi);
        uniswapQuoter = await smock.fake(iQuoter.abi, { address: '0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6' });

        await terminal.pay.returns(0);
        await directory.isTerminalOf.whenCalledWith(basicProjectId, terminal.address).returns(true);
        await directory.primaryTerminalOf.whenCalledWith(basicProjectId, jbxJbTokensEth).returns(terminal.address);
        uniswapQuoter.quoteExactInputSingle.returns(BigNumber.from('1000000000000000000000'));
    });

    before('Initialize contracts', async () => {
        const basicName = 'Test NFT'
        const basicSymbol = 'NFT';

        basicMintPeriodStart = 0;
        basicMintPeriodEnd = 0;

        nfTokenFactory = await ethers.getContractFactory('NFToken');
        basicToken = await nfTokenFactory
            .connect(deployer)
            .deploy(
                basicName,
                basicSymbol,
                basicBaseUri,
                basicContractUri,
                basicMaxSupply,
                basicUnitPrice,
                basicMintAllowance,
                basicMintPeriodStart,
                basicMintPeriodEnd
            );

        editionTokenFactory = await ethers.getContractFactory('NFUEdition');
        editionToken = await editionTokenFactory.connect(deployer).deploy();
        await editionToken.connect(deployer).initialize(
            deployer.address,
            'Test NFT',
            'NFT',
            basicBaseUri,
            basicContractUri,
            basicMaxSupply,
            basicUnitPrice,
            basicMintAllowance,
            0,
            0,
        );

        randomizedEditionToken = await editionTokenFactory.connect(deployer).deploy();
        await randomizedEditionToken.connect(deployer).initialize(
            deployer.address,
            'Test NFT',
            'NFT',
            basicBaseUri,
            basicContractUri,
            basicMaxSupply,
            basicUnitPrice,
            basicMintAllowance,
            0,
            0,
        );

        await randomizedEditionToken.connect(deployer).setRandomizedMint(true);
    });

    it('Mint a single token', async () => {
        const minter = accounts[0];

        expect(await basicToken.getMintPrice(minter.address)).to.equal(basicUnitPrice);

        await basicToken.connect(accounts[0])['mint()']({ value: basicUnitPrice });
        expect(await basicToken.balanceOf(accounts[0].address)).to.equal(1);
    });

    it('Mint multiple tokens up to allowance', async () => {
        const minter = accounts[0];

        expect(await basicToken.getMintPrice(accounts[0].address)).to.equal(basicUnitPrice);

        const accountBalance = await basicToken.balanceOf(accounts[0].address);
        await basicToken.connect(accounts[0])['mint()']({ value: basicUnitPrice.mul(basicMintAllowance - accountBalance) });
        expect(await basicToken.balanceOf(accounts[0].address)).to.equal(4);
    });

    it('Mint multiple tokens with refund', async () => {
        const minter = accounts[0];

        expect(await basicToken.getMintPrice(accounts[1].address)).to.equal(basicUnitPrice);

        const accountBalance = await ethers.provider.getBalance(accounts[1].address);
        await basicToken.connect(accounts[1])['mint()']({ value: basicUnitPrice.mul(2).add(basicUnitPrice.div(2)) });
        expect(await basicToken.balanceOf(accounts[1].address)).to.equal(2);
        expect(await ethers.provider.getBalance(accounts[1].address)).to.be.greaterThan(accountBalance.sub(basicUnitPrice.mul(2).add(basicUnitPrice.div(2))));
    });

    it('Mint multiple tokens up to allowance with refund', async () => {
        const minter = accounts[0];

        expect(await basicToken.getMintPrice(accounts[2].address)).to.equal(basicUnitPrice);

        const accountBalance = await ethers.provider.getBalance(accounts[2].address);
        await basicToken.connect(accounts[2])['mint()']({ value: basicUnitPrice.mul(5) });
        expect(await basicToken.balanceOf(accounts[2].address)).to.equal(4);
        expect(await ethers.provider.getBalance(accounts[2].address)).to.be.greaterThan(accountBalance.sub(basicUnitPrice.mul(5)));
    });
});

// npx hardhat test test/extensions/nft/multimint.test.ts
