import type { BigNumber, BytesLike, ethers } from 'ethers';

export type DeployResult = {
    address: string,
    abi: string,
    opHash: string
}

/**
 * Price tier definition used in NFTRewardDataSourceDelegate-relate contracts, specifically TieredPriceResolver that is created via `deployerWrapper.deployTieredPriceResolver`.
 */
export interface RewardTier {
    /**
     * Minimum contribution in Ether that will trigger an NFT issuance.
     */
    contributionFloor: BigNumber | number;
    /**
     * Highest token id within this tier. When creating arrays of these objects take care to match this and `remainingAllowance` across the entire range to avoid id collisions.
     */
    idCeiling: BigNumber | number;
    /**
     * Total number of NFTs to mint in this tier.
     */
    remainingAllowance: BigNumber | number;
}

/**
 * Price tier definition used in NFTRewardDataSourceDelegate-relate contracts,  specifically OpenTieredPriceResolver that is created via `deployerWrapper.deployOpenTieredPriceResolver`.
 */
export interface OpenRewardTier {
    /**
     * Minimum contribution in Ether that will trigger an NFT issuance.
     */
    contributionFloor: BigNumber | number;
}

/**
 * A Juicebox-ey way to define a token amount.
 */
export interface JBTokenAmount {
    token: string;
    value: BigNumber | number;
    decimals: BigNumber | number;
    currency: BigNumber | number;
}

export interface JBSplit {
    preferClaimed: boolean;
    preferAddToBalance: boolean;
    percent: BigNumber | number | string;
    projectId: BigNumber | number;
    beneficiary: string;
    lockedUntil: BigNumber | number;
    allocator: string;
}

export interface VestingPlan {
    receiver: string;
    sponsor: string;
    token: string;
    amount: BigNumber;
    cliff: BigNumber;
    periodDuration: BigNumber;
    eventCount: BigNumber;
}

/**
 * JBProjects contract stores these domain:content pairs per project. They appear to be arbitrary fields that are used published to the graph when the project is created or when they're updated. This is potentially expensive, depending on the length of the content provided.
 */
export interface JBProjectMetadata {
    content: string;
    domain: number;
}

/**
 * @member duration The number of seconds the funding cycle lasts for, after which a new funding cycle will start. A duration of 0 means that the funding cycle will stay active until the project owner explicitly issues a reconfiguration, at which point a new funding cycle will immediately start with the updated properties. If the duration is greater than 0, a project owner cannot make changes to a funding cycle's parameters while it is active – any proposed changes will apply to the subsequent cycle. If no changes are proposed, a funding cycle rolls over to another one with the same properties but new `start` timestamp and a discounted `weight`.
 * @member weight This value is used to determine how many tokens get minted per 1 Eth contribution. Generally it's a fixed point number with 18 decimals that contracts can use to base arbitrary calculations on. For example, payment terminals can use this to determine how many tokens should be minted when a payment is received.
 * @member discountRate A percent by how much the `weight` of the subsequent funding cycle should be reduced, if the project owner hasn't configured the subsequent funding cycle with an explicit `weight`. If it's 0, each funding cycle will have equal weight. If the number is 90%, the next funding cycle will have a 10% smaller weight. This weight is out of `JBConstants.MAX_DISCOUNT_RATE`.
 * @member ballot An address of a contract that says whether a proposed reconfiguration should be accepted or rejected. It can be used to create rules around how a project owner can change funding cycle parameters over time.
 */
export interface JBFundingCycleData {
    duration: number | BigNumber;
    weight: number | BigNumber;
    discountRate: number | BigNumber;
    ballot: string;
}

export interface JBGlobalFundingCycleMetadata {
    allowSetTerminals: boolean;
    allowSetController: boolean;
    pauseTransfers: boolean;
}

export interface JBFundingCycleMetadata {
    global: JBGlobalFundingCycleMetadata;
    reservedRate: number | BigNumber;
    redemptionRate: number | BigNumber;
    ballotRedemptionRate: number | BigNumber;
    pausePay: boolean;
    pauseDistributions: boolean;
    pauseRedeem: boolean;
    pauseBurn: boolean;
    allowMinting: boolean;
    allowTerminalMigration: boolean;
    allowControllerMigration: boolean;
    holdFees: boolean;
    preferClaimedTokenOverride: boolean;
    useTotalOverflowForRedemptions: boolean;
    useDataSourceForPay: boolean;
    useDataSourceForRedeem: boolean;
    dataSource: string;
    metadata: number;
}

export interface JBGroupedSplits {
    group: number;
    splits: JBSplit[];
}

export interface JBFundAccessConstraints {
    terminal: string;
    token: string;
    distributionLimit: number | BigNumber;
    distributionLimitCurrency: number | BigNumber;
    overflowAllowance: number | BigNumber;
    overflowAllowanceCurrency: number | BigNumber;
}

export interface JB721TierParams {
    contributionFloor: number | BigNumber;
    lockedUntil: number | BigNumber;
    initialQuantity: number | BigNumber;
    votingUnits: number | BigNumber;
    reservedRate: number | BigNumber;
    reservedTokenBeneficiary: string;
    encodedIPFSUri: BytesLike;
    allowManualMint: boolean;
    shouldUseBeneficiaryAsDefault: boolean;
    transfersPausable: boolean;
}

export interface JB721PricingParams {
    tiers: JB721TierParams[];
    currency: number | BigNumber;
    decimals: number | BigNumber;
    prices: string;
}

export interface JBTiered721Flags {
    lockReservedTokenChanges: boolean;
    lockVotingUnitChanges: boolean;
    lockManualMintingChanges: boolean;
}

export enum JB721GovernanceType {
    NONE,
    TIERED,
    GLOBAL,
}

export interface JBDeployTiered721DelegateData {
    directory: string;
    name: string;
    symbol: string;
    fundingCycleStore: string;
    baseUri: string;
    tokenUriResolver: string;
    contractUri: string;
    owner: string;
    pricing: JB721PricingParams;
    reservedTokenBeneficiary: string;
    store: string; // IJBTiered721DelegateStore
    flags: JBTiered721Flags;
    governanceType: JB721GovernanceType;
}

export interface JBPayDataSourceFundingCycleMetadata {
    global: JBGlobalFundingCycleMetadata;
    reservedRate: number | BigNumber;
    redemptionRate: number | BigNumber;
    ballotRedemptionRate: number | BigNumber;
    pausePay: boolean;
    pauseDistributions: boolean;
    pauseRedeem: boolean;
    pauseBurn: boolean;
    allowMinting: boolean;
    allowTerminalMigration: boolean;
    allowControllerMigration: boolean;
    holdFees: boolean;
    preferClaimedTokenOverride: boolean;
    useTotalOverflowForRedemptions: boolean;
    useDataSourceForRedeem: boolean;
    metadata: number | BigNumber;
}

export interface JBReconfigureFundingCyclesData {
    data: JBFundingCycleData;
    metadata: JBPayDataSourceFundingCycleMetadata;
    mustStartAtOrAfter: number | BigNumber;
    groupedSplits: JBGroupedSplits[];
    fundAccessConstraints: JBFundAccessConstraints[];
    memo: string;
}

export interface JBLaunchFundingCyclesData {
    data: JBFundingCycleData;
    metadata: JBPayDataSourceFundingCycleMetadata;
    mustStartAtOrAfter: number | BigNumber;
    groupedSplits: JBGroupedSplits[];
    fundAccessConstraints: JBFundAccessConstraints[];
    terminals: string[];
    memo: string;
}
export interface JBLaunchProjectData {
    projectMetadata: JBProjectMetadata;
    data: JBFundingCycleData;
    metadata: JBPayDataSourceFundingCycleMetadata;
    mustStartAtOrAfter: number | BigNumber;
    groupedSplits: JBGroupedSplits[];
    fundAccessConstraints: JBFundAccessConstraints[];
    terminals: string[];
    memo: string;
}

export type ContractMap = {
    // platform: juicebox2, juicebox3, daolabs
    [index: string]: {
        // network: mainnet, goerli
        [index: string]: {
            // contract name: JBController, etc
            [index: string]: {
                address: string;
                abi: ethers.ContractInterface;
            };
        };
    };
};

export const JBTOKENS_ETH = '0x000000000000000000000000000000000000EEEe';
export const JBCURRENCIES_ETH = 1;
