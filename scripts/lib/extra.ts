import type { BigNumber } from 'ethers';

enum BeneficiaryType { TokenReserve, Payout, Both }

export interface ProjectBeneficiary {
    beneficiaryType: BeneficiaryType;
    preferClaimed: boolean;
    preferAddToBalance: boolean;
    percent: number; // 1_000_000_000 = 100%
    projectId: BigNumber | number,
    beneficiary: string, // address
    lockedUntil: number; // timestamp as seconds
    allocator: string; // address
}

export interface FundingAccessConstraint {
    Terminal: string; // contract address
    Token: string; // contract address, eth (0x000000000000000000000000000000000000EEEe) or dai
    DistributionLimit: BigNumber | number;
    DistributionLimitCurrency: number; // enum
    OverflowAllowance: BigNumber | number;
    OverflowAllowanceCurrency: number; // enum
}

export interface FundingCycleInfo {
    Duration: number; // seconds
    DistributionLimit: BigNumber | number;
    DistributionCurrency: BigNumber | number; // enum
    TokenMintRate: BigNumber | number; // 18 decimals, per eth
    ReserveRate: BigNumber | number; // bps
    RedemptionRate: BigNumber | number; // bps
    DiscountRate: BigNumber | number; // 100% = 1_000_000_000
    ReconfigurationStrategy: string; // contract address
    Ballot: string; // contract address
    Payments: boolean;
    Redemptions: boolean;
    Distribution: boolean;
    TokenMinting: boolean;
    TerminalConfiguration: boolean;
    ControllerConfiguration: boolean;
    TerminalMigration: boolean;
    ControllerMigration: boolean;
    FundingAccessConstraints: FundingAccessConstraint[];
}

export interface Project {
    ProjectName: string;
    TokenName: string;
    TokenSymbol: string;
    Beneficiaries: ProjectBeneficiary[];
    InitialFundingCycle: FundingCycleInfo;
}
