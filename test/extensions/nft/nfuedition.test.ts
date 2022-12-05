import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { smock } from '@defi-wonderland/smock';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import * as helpers from '@nomicfoundation/hardhat-network-helpers';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbTerminal from '../../../artifacts/contracts/abstract/JBPayoutRedemptionPaymentTerminal.sol/JBPayoutRedemptionPaymentTerminal.json';
import iQuoter from '../../../artifacts/contracts/extensions/NFT/components/BaseNFT.sol/IQuoter.json';

describe('NFUEdition tests', () => {
    const jbxJbTokensEth = '0x000000000000000000000000000000000000EEEe';

    let deployer: SignerWithAddress;
    let accounts: SignerWithAddress[];

    let directory: any;
    let terminal: any;
    let uniswapQuoter: any;

    let nfTokenFactory: any;
    let editionToken: any;
    const basicBaseUri = 'ipfs://hidden';
    const basicContractUri = 'ipfs://metadata';
    const basicProjectId = 99;
    const basicUnitPrice = ethers.utils.parseEther('0.001');
    const basicMaxSupply = 20;
    const basicMintAllowance = 2;

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
        nfTokenFactory = await ethers.getContractFactory('NFUEdition');
        editionToken = await nfTokenFactory.connect(deployer).deploy();
        await editionToken.connect(deployer).initialize(
            deployer.address,
            'Test NFT',
            'NFT',
            basicBaseUri,
            basicContractUri,
            basicProjectId,
            directory.address,
            basicMaxSupply,
            basicUnitPrice,
            basicMintAllowance,
            0,
            0,
        );
    });

    it('Mint failures', async () => {
        await expect(editionToken.connect(accounts[0])['mint(string,bytes)']('', '0x00', { value: basicUnitPrice }))
            .to.be.revertedWithCustomError(editionToken, 'INVALID_OPERATION');

        await expect(editionToken.connect(accounts[0])['mint()']({ value: basicUnitPrice }))
            .to.be.revertedWithCustomError(editionToken, 'INVALID_OPERATION');

        await expect(editionToken.connect(accounts[0])['mint(uint256)'](0, { value: basicUnitPrice }))
            .to.be.revertedWithCustomError(editionToken, 'INVALID_OPERATION');

        await expect(editionToken.connect(accounts[0])['mint(uint256)'](1, { value: basicUnitPrice }))
            .to.be.revertedWithCustomError(editionToken, 'INVALID_OPERATION');

        await expect(editionToken.connect(deployer).mintFor(accounts[1].address))
            .to.be.revertedWithCustomError(editionToken, 'INVALID_OPERATION');
    });

    it('Register editions', async () => {
        await editionToken.connect(deployer).registerEdition(10, ethers.utils.parseEther('0.0001'));
        await editionToken.connect(deployer).registerEdition(8, ethers.utils.parseEther('0.001'));
        await editionToken.connect(deployer).registerEdition(2, ethers.utils.parseEther('0.01'));
        await expect(editionToken.connect(deployer).registerEdition(10, ethers.utils.parseEther('0.001'))).to.be.reverted;

        expect(await editionToken.editions(0)).to.equal(10);
        expect(await editionToken.editions(1)).to.equal(8);
        expect(await editionToken.editions(2)).to.equal(2);
    });

    it('Mint', async () => {
        await expect(editionToken.connect(accounts[0]).mintEditionFor(2, accounts[2].address)).to.be.reverted;
        expect(await editionToken.balanceOf(accounts[2].address)).to.equal(0);

        await editionToken.connect(deployer).mintEditionFor(2, accounts[2].address);
        expect(await editionToken.balanceOf(accounts[2].address)).to.equal(1);

        await editionToken.connect(accounts[0])['mint(uint256)'](1, { value: ethers.utils.parseEther('0.001') });
        expect(await editionToken.totalSupply()).to.equal(2);

        await expect(editionToken.connect(accounts[0])['mint(uint256)'](2, { value: ethers.utils.parseEther('0.001') })).to.be.reverted;
        await expect(editionToken.connect(accounts[0])['mint(uint256)'](3, { value: ethers.utils.parseEther('1') })).to.be.reverted;

        await editionToken.connect(accounts[0])['mint(uint256,string,bytes)'](1, '', '0x00', { value: ethers.utils.parseEther('0.001') });
        expect(await editionToken.totalSupply()).to.equal(3);
        expect(await editionToken.balanceOf(accounts[0].address)).to.equal(2);
        expect(await editionToken.mintedEditions(1)).to.equal(2);

        expect(await editionToken.mintedEditions(0)).to.equal(0);
    });
});
