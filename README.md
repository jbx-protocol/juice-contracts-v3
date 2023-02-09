# DAOLABS ❤️ Juicebox v3 Fork 🍽️

This repo is a fork of the [Juicebox protocol](https://github.com/jbx-protocol/juice-contracts-v3). For an overview, architecture, and API specification, see the documentation at [juicebox.money](https://info.juicebox.money/dev/). While effort has been made to ensure the repository extension tests are demonstrative of how the protocol and its add-ons operate, front-end wrapper classes intended to simplify the [Svelte frontend](https://github.com/tankbottoms/juice-interface-svelte/tree/feature/contracts/src/utils/web3) integration are additionally illustrative. The repository deployments folder contains consolidated JSON files for the [platform](deployments/goerli/platform.json) and [extensions](deployments/goerli/extensions.json) integrations.

## Environment variables

```bash
INFURA_API_KEY=
ALCHEMY_MAINNET_URL=
ALCHEMY_MAINNET_API_KEY=
ETHERSCAN_API_KEY=
PRIVATE_KEY=
REPORT_GAS=yes
```

## TL;DR

The deployment and verification of all the contracts may take between 45 mins to 1 hour. The following commands will:

- Deploy a Juicebox fork to the specified network,
- Configure the first project-Juicebox,
- Verify the contracts via Etherscan; and,
- Add-On by deploying specific platform extensions, _each subsequent deployer aggregates the previous._

```bash
yarn
npx hardhat run scripts/platform/deploy.ts --network goerli
npx hardhat run scripts/platform/configure.ts --network goerli
npx hardhat run scripts/platform/verify.ts --network goerli
npx hardhat run scripts/deploy/Deployer_v001.ts --network goerli
npx hardhat run scripts/deploy/Deployer_v002.ts --network goerli
npx hardhat run scripts/deploy/Deployer_v003.ts --network goerli
...
```

## Differences

This repo provides [extra functionality built on Juicebox](./contracts/extensions/), adheres more closely to the latest hardhat conventions, uses more up-to-date dependencies, uses typescript for chai unit tests and simplifies the build process.

## Developing

After cloning run `yarn` or `npm i` to install dependencies. Some instructions below are macOS-specific, but will work with some modification in other environments.

This is a hardhat project you should be able to run hardhat commands directly like `npx hardhat test`, `npx hardhat compile`, etc. There is extensive code coverage that you can check with `npx hardhat coverage`. You can also run unit tests from node with `yarn test` or `npm test`.

Code coverage may run out of memory, feed it more with `export NODE_OPTIONS=--max-old-space-size=8192`.

These commands will require a .env file to be placed at the root of the project. An example is [included](./.example.env). DAOLABS uses a combination of Infura and Alchemy infrastructure, you can modify [hardhat config](./hardhat.config.ts) to use only one.

## Deploying

There are two sets of deployment scripts, one for the core platform in [scripts/platform](./scripts/platform/) and another set for the extended features in [scripts/deploy/](./scripts/deploy/). To deploy the core platform run `npx hardhat run scripts/platform/deploy.ts --network goerli` then `npx hardhat run scripts/platform/configure.ts --network goerli` and `npx hardhat run scripts/platform/verify.ts --network goerli`. The configure and verify steps can be run in parallel. The verification step is optional, it publishes the contract code to etherscan. It's worth reviewing the configuration script to make sure it's in line with what you require.

Some contracts are not included in the above scripts. You'll need to separately run the following scripts to get the rest of them deployed. These contracts are optional.

```bash
npx hardhat run scripts/deploy/NFToken.ts --network goerli
npx hardhat run scripts/deploy/RoleManager.ts --network goerli
npx hardhat run scripts/deploy/VestingPlanManager.ts --network goerli
```

When deploying this platform with the intent of using the Svelte UI, also run

```bash
npx hardhat run scripts/platform/export.ts --network goerli
```

This creates files for that code to import which contain contract addresses and ABIs.

## Economics

There are some economic differences between this fork and the original. Notably it deploys a DAI payment terminal. This happens in the deploy script. There is also a new contract, `DaiHedgeDelegate` which allows projects to automatically maintain a DAI and Ether treasury subject to configuration which is described in more detail in the documentation of that contract.

## Extras

### forge

Forge is an awesome unit testing tool for solidity smart contracts from [Foundry](https://github.com/gakonst/foundry). Some [Juicebox tests](./contracts/system_tests/) use it. Install it with `curl -L https://foundry.paradigm.xyz | sh`. Then run it as `forge test`. Forge is a fast-moving project, to update to the latest run `foundryup`. If you add new functionality it may be necessary to run `git submodule update --init` to install additional dependencies, but this step is not required for the code here. For more see [The Forge-Book](https://onbjerg.github.io/foundry-book/forge).

### slither

This project uses [slither](https://github.com/crytic/slither) for static analysis. To install it run `pip3 install slither-analyzer`. You may need to install `solc` as a stand-alone tool. To do use use:

```bash
brew update
brew upgrade
brew tap ethereum/ethereum
brew install solidity
```

You can run slither with `npm run slither` or as `npx hardhat clean && slither .`. Hardhat clean is a required step as of Oct 2022.

### Contributing

We welcome PRs and make an effort to stay current with the original project. We make minimally invasive changes to the source contracts. New functionality inside `/extensions` follows these conventions:

- Function arguments start with an underscore.
- Storage parameters do not start with an underscore regardless of visibility.
- Functions dealing with Ether transfer are marked as `nonReentrant`.
- Use `revert` with named errors instead of `require`.
- `for` loops increment at the end as `++i` and test for continuation with `!=`.
- Solidity version is defined with a caret, currently as `^0.8.0`.
- Use Typescript instead of JavaScript.
- Use Hardhat when possible unless there is good reason not to.
