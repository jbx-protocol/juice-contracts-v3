# juice-contracts-v3

This repository contains the core Juicebox contracts. To learn more about the Juicebox protocol, visit the [docs](https://docs.juicebox.money/dev/). If you have question, join the [JuiceboxDAO Discord](https://discord.gg/juicebox).

## Dependencies

`juice-contracts-v3` uses the Foundry smart contract development toolchain. To install Foundry, open your terminal and run the following command:

```bash
curl -L https://foundry.paradigm.xyz | bash
```

Once you have Foundry installed, run `foundryup` to update to the latest versions of `forge`, `cast`, `anvil`, and `chisel`. More detailed instructions can be found in the [Foundry Book](https://book.getfoundry.sh/getting-started/installation).

`juice-contracts-v3` also has NPM dependencies. To use them, install [node.js](https://nodejs.org/).

To install both `forge` and `npm` dependencies, run:

```bash
forge install && npm install
```

If you encounter issues with nested `forge` dependencies, try running:

```bash
git submodule update --init --recursive
```

## Unit Tests

The `juice-contracts-v3` unit test suite is written in JavaScript with [Hardhat](https://hardhat.org/). To run the unit tests, install the JavaScript dependencies with `npm install`. Then manually run Hardhat to enable ESM support:

```bash
node --require esm ./node_modules/.bin/hardhat test --network hardhat
```

Alternatively, you can run a local Hardhat node in another terminal using:

```bash
npm run chain -- --network hardhat
```

then run the tests with:

```bash
npm run test
```

If Hardhat fails to resolve a custom error (i.e. tests fail on "Expecter nameOfTheError() but revert without a reason string"), restart `npm run chain`.

To check current unit test coverage, run:

```bash
node --require esm ./node_modules/.bin/hardhat coverage --network hardhat
```

A few notes:

- Unit tests can be found in the `test` directory.
- Hardhat doesn't support [esm](https://nodejs.org/api/esm.html) yet, hence running manually with node.
- We are currently using a forked version of [solidity-coverage](https://www.npmjs.com/package/solidity-coverage) that includes optimizer settings. Ideally we will move to the maintained version after this is fixed on their end.
- Juicebox V3 codebase being quite large, Solidity Coverage might run out of memory if you modify/add parts to it. Please check [Solidity-coverage FAQ](https://github.com/sc-forks/solidity-coverage/blob/master/docs/faq.md) in order to address the issue.

## System Tests

End-to-end tests have been written in Solidity, using Foundry. Once you have installed `forge` dependencies with `forge install`, you can run the tests with:

```bash
forge test
```

System tests can be found in the `forge_tests` directory.

## Deployment

Juicebox uses the [Hardhat Deploy](https://github.com/wighawag/hardhat-deploy) plugin to deploy contracts to a given network. To use it, you must create a `./mnemonic.txt` file containing the mnemonic phrase of the wallet used to deploy. You can generate a new mnemonic using [this tool](https://github.com/itinance/mnemonics). Generate a mnemonic at your own risk.

Then, to execute the `./deploy/deploy.js` script, run the following:

```bash
npx hardhat deploy --network $network
```

\_You'll likely want to set the optimizer runs to 10000 in `./hardhat.config.js` before deploying to prevent contract size errors. The preset value of 1000000 is necessary for hardhat to run unit tests successfully. Bug about this opened [here](https://github.com/NomicFoundation/hardhat/issues/2657#issuecomment-1113890401).

Contract artifacts will be outputted to `./deployments/$network/**` and should be checked in to the repo.

## Verification

To verify the contracts on [Etherscan](https://etherscan.io), make sure you have an `ETHERSCAN_API_KEY` set in your `./.env` file. Then run:

```bash
npx hardhat --network $network etherscan-verify
```

This will verify all of the deployed contracts in `./deployments`.

## Editor

We recommend using [VSCode](https://code.visualstudio.com/) with Juan Blanco's [solidity](https://marketplace.visualstudio.com/items?itemName=JuanBlanco.solidity) extension. To display code coverage in VSCode, install [Coverage Gutters](https://marketplace.visualstudio.com/items?itemName=ryanluker.vscode-coverage-gutters) (Ryan Luker). In VSCode, press `F1` and run "Coverage Gutters: Display Coverage". Coverage will be displayed as colored markdown lines in the left gutter, after the line numbers.
